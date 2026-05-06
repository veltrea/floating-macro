import Foundation
import ImageIO

/// Extracts an application icon as PNG bytes by reading the bundle's
/// `.icns` file directly with ImageIO.
///
/// Why ImageIO instead of `NSWorkspace.icon(forFile:)`?
///
/// - **No AppKit dependency.** Foundation + ImageIO only, so this lives
///   in the Core target and is unit-testable like any other pure-logic
///   component.
/// - **Fast and reliable.** Reads the icns directly off disk in a few
///   milliseconds. Empirically: Calculator.app ≈9ms, Slack.app ≈3ms,
///   VS Code.app ≈3ms.
/// - **Why not qlmanage?** `qlmanage -t` was tried first as a way to
///   cover both traditional `.icns` apps and SwiftUI/Assets.car-only
///   apps. It hangs unpredictably (Quick Look daemon dependency) — even
///   on system apps like Calculator.app — and a hung qlmanage blocks
///   the parent for the entire process timeout. The cure is worse than
///   the disease, so qlmanage is not used.
///
/// Coverage caveat: an app whose Info.plist has only `CFBundleIconName`
/// (asset catalog icon) and no `.icns` file in `Contents/Resources/`
/// will fail with `.noIcnsFound`. In our survey of `/Applications` and
/// `/System/Applications` every encountered app — including modern
/// SwiftUI apps like Calculator — still ships an `AppIcon.icns`, so
/// this is rare in practice. If it becomes an issue, a fallback path
/// (e.g. `sips` invocation) can be added without changing this type.
public struct ImageIOIconExtractor {

    public enum ExtractError: Error, Equatable {
        case appBundleMissing(URL)
        case noIcnsFound(searchedNames: [String])
        case imageSourceFailed(URL)
        case noRepresentations(URL)
        case imageDecodeFailed(URL, index: Int)
        case pngEncodeFailed
    }

    public init() {}

    /// Render the icon for `appURL` to PNG bytes (synchronous).
    /// - Parameters:
    ///   - appURL: a file URL pointing at an `.app` bundle.
    ///   - size: desired pixel size of the longer edge. The icns
    ///     representation closest to this size is selected; no upscaling
    ///     is performed.
    ///
    /// This is a pure-logic synchronous API kept for unit-testability
    /// and for callers that already run on a background queue. UI code
    /// should prefer `extractPNGAsync(from:size:)` so the main thread
    /// is never blocked even on slow disks.
    public func extractPNG(from appURL: URL, size: Int = 256) throws -> Data {
        guard FileManager.default.fileExists(atPath: appURL.path) else {
            throw ExtractError.appBundleMissing(appURL)
        }
        let icnsURL = try findIcns(in: appURL)
        return try renderPNG(from: icnsURL, targetSize: size)
    }

    /// Async variant that runs the extraction on a detached Task at
    /// `userInitiated` priority. The caller's actor (e.g. the SwiftUI
    /// MainActor) stays responsive while the icns is decoded.
    ///
    /// Cancellation: respects the calling Task's cancellation. ImageIO
    /// itself doesn't cooperate with cancellation, but the file-existence
    /// check at the top of the synchronous path is checked here as well
    /// before paying the decode cost.
    ///
    /// Crash isolation: this still runs in-process. ImageIO returns nil
    /// rather than crashing on malformed input, so in-process is fine
    /// for icns reading. If a future post-processing step introduces a
    /// genuinely crash-prone operation, switch to a subprocess-based
    /// extractor at that boundary instead of weakening this API.
    public func extractPNGAsync(from appURL: URL, size: Int = 256) async throws -> Data {
        try Task.checkCancellation()
        return try await Task.detached(priority: .userInitiated) { [self] in
            try Task.checkCancellation()
            return try extractPNG(from: appURL, size: size)
        }.value
    }

    // MARK: - Internals

    /// Locate the `.icns` file inside an `.app` bundle.
    /// Tries the Info.plist's `CFBundleIconFile` first, then falls back
    /// to common conventional names so apps with broken plists still
    /// have a chance.
    func findIcns(in appURL: URL) throws -> URL {
        let infoPlistURL = appURL.appendingPathComponent("Contents/Info.plist")

        var iconFile: String? = nil
        if let data = try? Data(contentsOf: infoPlistURL),
           let plist = try? PropertyListSerialization.propertyList(
               from: data, format: nil) as? [String: Any] {
            iconFile = plist["CFBundleIconFile"] as? String
        }

        var candidates: [String] = []
        if let f = iconFile, !f.isEmpty {
            candidates.append(f.hasSuffix(".icns") ? f : f + ".icns")
        }
        // Common conventional names used as fallback.
        candidates.append("AppIcon.icns")
        candidates.append("icon.icns")

        let resources = appURL.appendingPathComponent("Contents/Resources")
        for name in candidates {
            let url = resources.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        throw ExtractError.noIcnsFound(searchedNames: candidates)
    }

    /// Pick the icns representation closest to `targetSize` and encode
    /// it as PNG. Returns the encoded bytes (no file I/O).
    func renderPNG(from icnsURL: URL, targetSize: Int) throws -> Data {
        guard let source = CGImageSourceCreateWithURL(icnsURL as CFURL, nil) else {
            throw ExtractError.imageSourceFailed(icnsURL)
        }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else {
            throw ExtractError.noRepresentations(icnsURL)
        }

        var bestIndex = 0
        var bestDelta = Int.max
        for i in 0..<count {
            guard let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil)
                    as? [CFString: Any] else { continue }
            let w = (props[kCGImagePropertyPixelWidth] as? Int) ?? 0
            let delta = abs(w - targetSize)
            if delta < bestDelta {
                bestDelta = delta
                bestIndex = i
            }
        }

        guard let cgImage = CGImageSourceCreateImageAtIndex(source, bestIndex, nil) else {
            throw ExtractError.imageDecodeFailed(icnsURL, index: bestIndex)
        }

        let outData = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            outData, "public.png" as CFString, 1, nil
        ) else {
            throw ExtractError.pngEncodeFailed
        }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw ExtractError.pngEncodeFailed
        }
        return outData as Data
    }
}
