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

    /// Preset category of management directory. Used when specifying the save destination with `copyImage`.
    public enum AssetSubdirectory: String {
        /// `presets/<name>/icons/` - button/icon for group
        case icons
        /// `presets/<name>/images/` - thumbnail type for card representation
        case images
    }

    public enum SaveError: Error, Equatable {
        case extractFailed
        case writeFailed(path: String)
        case sourceNotReadable(path: String)
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
        return presetSubdirectory(
            presetName: presetName,
            subdirectory: "icons",
            applicationSupportDirectory: applicationSupportDirectory
        )
    }

    /// Persist a card-tab thumbnail under `presets/<name>/images/<buttonId>.<ext>`.
    /// `ext` defaults to "png" but JPEG / WebP files can be passed unchanged so
    /// large photographic thumbnails do not get re-encoded into bloated PNGs.
    /// Returns the saved absolute path. Callers should set
    /// `ButtonDefinition.thumbnail` to the returned string.
    public static func saveThumbnail(
        _ data: Data,
        buttonId: String,
        presetName: String,
        ext: String = "png",
        applicationSupportDirectory: URL? = nil
    ) throws -> String {
        let imagesDir = imagesDirectory(
            presetName: presetName,
            applicationSupportDirectory: applicationSupportDirectory
        )
        let normalizedExt = ext.lowercased().trimmingCharacters(in: .whitespaces)
        let dest = imagesDir.appendingPathComponent("\(buttonId).\(normalizedExt)")
        do {
            try FileManager.default.createDirectory(
                at: imagesDir, withIntermediateDirectories: true)
            try data.write(to: dest)
            return dest.path
        } catch {
            throw SaveError.writeFailed(path: dest.path)
        }
    }

    /// Resolve the directory where card-tab thumbnails for `presetName` live.
    public static func imagesDirectory(
        presetName: String,
        applicationSupportDirectory: URL? = nil
    ) -> URL {
        return presetSubdirectory(
            presetName: presetName,
            subdirectory: "images",
            applicationSupportDirectory: applicationSupportDirectory
        )
    }

    /// The user selects an image file in the Finder's file picker under the preset category.
    /// Returns the absolute path to save, copying directly into the management directory.
    ///
    /// Design Intent:
    /// The absolute path of the original file to `ButtonDefinition.icon` / `.thumbnail` as-is
    /// If the previous behavior is saved, when the user moves, deletes, or renames the original file at that moment,
    /// The button icon disappears. If you duplicate it under the preset, it can be used individually without preset.
    /// Portability is maintained, and preset.json, icons/, and images/ are exported together.
    /// Can be run on a different machine.
    ///
    /// The extension is inherited from the original file (PNG remains PNG, JPEG remains JPEG).
    /// Remove files with the same `assetId` that were previously copied (including different extensions).
    /// Because a new copy is created, orphan will not increase.
    ///
    /// Note: SF Symbol (`sf:foo`) and bundle id (`com.apple.Safari`) are files
    /// Copy target excluded. These references are dynamically resolved by the `IconLoader` side.
    /// Does not need to be saved as a path. This method selects the local file.
    /// Handle only cases.
    @discardableResult
    public static func copyImage(
        from sourceURL: URL,
        into subdirectory: AssetSubdirectory,
        assetId: String,
        presetName: String,
        applicationSupportDirectory: URL? = nil
    ) throws -> String {
        let dir = presetSubdirectory(
            presetName: presetName,
            subdirectory: subdirectory.rawValue,
            applicationSupportDirectory: applicationSupportDirectory
        )
        let rawExt = sourceURL.pathExtension.lowercased()
            .trimmingCharacters(in: .whitespaces)
        let ext = rawExt.isEmpty ? "png" : rawExt
        let dest = dir.appendingPathComponent("\(assetId).\(ext)")

        // If the file has already been reselected within the management directory, it is a no-op.
        if sourceURL.standardizedFileURL == dest.standardizedFileURL {
            return dest.path
        }
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw SaveError.sourceNotReadable(path: sourceURL.path)
        }

        do {
            try FileManager.default.createDirectory(
                at: dir, withIntermediateDirectories: true)
            // Delete files with the same assetId, including different extensions.
            // For example, when replacing old PNG with new JPEG, if the PNG is an orphan
            // Remove duplicates.
            if let existing = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil
            ) {
                for url in existing
                where url.deletingPathExtension().lastPathComponent == assetId {
                    try? FileManager.default.removeItem(at: url)
                }
            }
            try FileManager.default.copyItem(at: sourceURL, to: dest)
            return dest.path
        } catch {
            throw SaveError.writeFailed(path: dest.path)
        }
    }

    /// Existing button/group storing external absolute image path under preset
    /// Copy and return a new absolute path. Used for automatic repair during bulk migration / commit time.
    ///
    /// No-operation case (returns the original `path` as-is):
    /// - `nil` / empty string
    /// Reference category like `sf:foo`, `lucide:foo`, or bundle ID (e.g., `com.apple.Safari`).
    /// .app bundle
    /// Element file does not exist on disk (broken link)
    /// Already placed in the management directory (`presets/<name>/icons|images/`).
    /// Copy failed for some reason.
    ///
    /// Only a new path is returned when the migration succeeds. A fail-safe implementation for the user's
    /// Prioritize not breaking settings on its own.
    public static func migrateExternalImagePath(
        _ path: String?,
        into subdirectory: AssetSubdirectory,
        assetId: String,
        presetName: String,
        applicationSupportDirectory: URL? = nil
    ) -> String? {
        guard let path = path,
              !path.trimmingCharacters(in: .whitespaces).isEmpty
        else { return path }

        // Classify whether a file reference is real using IconResolver. SF Symbol and
        // Bundle ID is skipped. The .app bundle is not an image file, so it's skipped.
        let resolved = IconResolver.resolve(path)
        let sourceURL: URL
        switch resolved {
        case .success(.imageFile(let u)):
            sourceURL = u
        default:
            return path
        }

        // Do nothing if the file is already in a managed directory (avoiding duplicate copies).
        let managedDir = presetSubdirectory(
            presetName: presetName,
            subdirectory: subdirectory.rawValue,
            applicationSupportDirectory: applicationSupportDirectory
        ).standardizedFileURL
        let standardSource = sourceURL.standardizedFileURL
        if standardSource.path.hasPrefix(managedDir.path + "/") {
            return path
        }

        do {
            return try copyImage(
                from: sourceURL,
                into: subdirectory,
                assetId: assetId,
                presetName: presetName,
                applicationSupportDirectory: applicationSupportDirectory
            )
        } catch {
            return path
        }
    }

    private static func presetSubdirectory(
        presetName: String,
        subdirectory: String,
        applicationSupportDirectory: URL?
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
            .appendingPathComponent(subdirectory)
    }
}
