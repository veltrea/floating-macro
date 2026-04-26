import Foundation

/// Pure-logic layer for resolving icon references to local file paths.
///
/// NSImage loading happens in the App layer (AppKit-dependent). This layer
/// decides *what* path to load — tilde expansion, existence check, and the
/// distinction between a user-supplied image path and an app bundle that
/// should be resolved via NSWorkspace.
public enum IconResolver {

    public enum Resolved: Equatable {
        /// A concrete image file we can load directly (PNG, JPEG, ICO, ICNS).
        case imageFile(URL)
        /// A macOS application; the caller is expected to fetch its icon via
        /// NSWorkspace.icon(forFile:) or .icon(forFileAt:).
        case appBundle(URL)
        /// A bundle identifier; caller should NSWorkspace.urlForApplication(
        /// withBundleIdentifier:) then fetch icon.
        case bundleIdentifier(String)
        /// SF Symbol name (Apple system icon). Caller resolves via
        /// `NSImage(systemSymbolName:accessibilityDescription:)`.
        /// Apple restricts SF Symbol usage to Apple-platform applications,
        /// which is fine for FloatingMacro since we're a macOS-only app.
        case systemSymbol(String)
        /// A resource icon bundled with the app, addressed by pack name +
        /// icon name (no extension). Caller resolves via `Bundle.module`
        /// for the owning target.
        case bundledIcon(pack: String, name: String)
    }

    public enum ResolveError: Error, Equatable {
        case empty
        case fileNotFound(String)
    }

    /// Supported image file extensions (case-insensitive).
    public static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "tiff", "tif", "icns", "ico", "bmp", "webp", "svg"
    ]

    /// Helper: strip a leading prefix and return the remainder, or nil if the
    /// string doesn't start with the prefix.
    private static func stripPrefix(_ s: String, _ prefix: String) -> String? {
        guard s.hasPrefix(prefix) else { return nil }
        return String(s.dropFirst(prefix.count))
    }

    /// Decide what kind of icon reference `raw` represents.
    public static func resolve(_ raw: String) -> Result<Resolved, ResolveError> {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return .failure(.empty) }

        // "sf:<name>" → SF Symbol (Apple-provided system icon).
        if let name = stripPrefix(trimmed, "sf:") {
            let cleaned = name.trimmingCharacters(in: .whitespaces)
            guard !cleaned.isEmpty else { return .failure(.empty) }
            return .success(.systemSymbol(cleaned))
        }

        // "lucide:<name>" → bundled Lucide SVG.
        if let name = stripPrefix(trimmed, "lucide:") {
            let cleaned = name.trimmingCharacters(in: .whitespaces)
            guard !cleaned.isEmpty else { return .failure(.empty) }
            return .success(.bundledIcon(pack: "lucide", name: cleaned))
        }

        // Bundle identifier: "com.xxx.yyy" (at least two dots, no slashes).
        let looksLikeBundleId = trimmed.split(separator: ".").count >= 3
            && !trimmed.contains("/")
            && trimmed.first?.isLetter == true
        if looksLikeBundleId {
            return .success(.bundleIdentifier(trimmed))
        }

        // Expand ~/ paths.
        let expanded: String
        if trimmed.hasPrefix("~/") {
            expanded = NSString(string: trimmed).expandingTildeInPath
        } else {
            expanded = trimmed
        }

        // Existence check.
        guard FileManager.default.fileExists(atPath: expanded) else {
            return .failure(.fileNotFound(trimmed))
        }

        let url = URL(fileURLWithPath: expanded)
        let ext = url.pathExtension.lowercased()

        if ext == "app" {
            return .success(.appBundle(url))
        }
        if imageExtensions.contains(ext) {
            return .success(.imageFile(url))
        }
        // Unknown extension but file exists — treat as an image-like file and
        // let NSImage decide.
        return .success(.imageFile(url))
    }
}
