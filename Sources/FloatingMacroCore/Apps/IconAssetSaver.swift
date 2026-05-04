import Foundation

/// Saves an extracted PNG icon under the FloatingMacro Application
/// Support directory in a deterministic per-preset/per-button location.
///
/// Path layout (under `~/Library/Application Support` by default):
///   ```
///   FloatingMacro/presets/<presetName>/icons/<buttonId>.png
///   ```
///
/// `applicationSupportDirectory` can be overridden in tests so the
/// real user directory is never touched.
public enum IconAssetSaver {

    public enum SaveError: Error, Equatable {
        case extractFailed
        case writeFailed(path: String)
    }

    /// Extract `appURL`'s icon via ImageIO and write it under the preset's
    /// `icons/` directory. Returns the absolute path of the saved PNG.
    ///
    /// The extractor is injected so tests can substitute a deterministic
    /// implementation (e.g. one that returns fixed PNG bytes).
    public static func saveAppIcon(
        appURL: URL,
        buttonId: String,
        presetName: String,
        size: Int = 64,
        extractor: ImageIOIconExtractor = ImageIOIconExtractor(),
        applicationSupportDirectory: URL? = nil
    ) throws -> String {
        let pngData: Data
        do {
            pngData = try extractor.extractPNG(from: appURL, size: size)
        } catch {
            throw SaveError.extractFailed
        }
        return try saveData(
            pngData,
            buttonId: buttonId,
            presetName: presetName,
            applicationSupportDirectory: applicationSupportDirectory
        )
    }

    /// Lower-level: persist arbitrary PNG bytes to the per-preset
    /// `icons/<buttonId>.png` location and return the absolute path.
    public static func saveData(
        _ pngData: Data,
        buttonId: String,
        presetName: String,
        applicationSupportDirectory: URL? = nil
    ) throws -> String {
        let iconsDir = iconsDirectory(
            presetName: presetName,
            applicationSupportDirectory: applicationSupportDirectory
        )
        let dest = iconsDir.appendingPathComponent("\(buttonId).png")
        do {
            try FileManager.default.createDirectory(
                at: iconsDir, withIntermediateDirectories: true)
            try pngData.write(to: dest)
            return dest.path
        } catch {
            throw SaveError.writeFailed(path: dest.path)
        }
    }

    /// Resolve the directory where icons for `presetName` are stored.
    /// Public so tests can read it back; pure path computation, no I/O.
    public static func iconsDirectory(
        presetName: String,
        applicationSupportDirectory: URL? = nil
    ) -> URL {
        let supportDir: URL
        if let d = applicationSupportDirectory {
            supportDir = d
        } else {
            supportDir = (try? FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )) ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support")
        }
        return supportDir
            .appendingPathComponent("FloatingMacro")
            .appendingPathComponent("presets")
            .appendingPathComponent(presetName)
            .appendingPathComponent("icons")
    }
}
