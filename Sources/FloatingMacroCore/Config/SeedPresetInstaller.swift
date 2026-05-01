import Foundation

/// Copies app-bundled "seed" presets (e.g. MidJourney 用, note.com
/// ハッシュタグ) into the user's presets directory on first launch. Once
/// `AppConfig.seedInstalled` flips to true the install pass is skipped on
/// subsequent launches; the control API exposes a `force` mode for tests
/// and for users who want to restore the originals after deleting them.
///
/// File-level idempotency: even with `force=false`, an individual seed is
/// skipped when a file with the same internal id already exists, so user
/// edits are never overwritten.
public final class SeedPresetInstaller {
    private let writer: ConfigWriter
    private let loader: ConfigLoader

    public init(baseURL: URL? = nil) {
        self.writer = ConfigWriter(baseURL: baseURL)
        self.loader = ConfigLoader(baseURL: baseURL)
    }

    /// Result of a single install pass. `installed` lists the internal ids
    /// that were newly created on this run; `skipped` lists ids that were
    /// already present on disk.
    public struct Result: Equatable {
        public let installed: [String]
        public let skipped:   [String]
        public init(installed: [String], skipped: [String]) {
            self.installed = installed
            self.skipped   = skipped
        }
    }

    /// Run the install pass.
    /// - Parameter force: when true, ignore per-file existence and
    ///   overwrite. Use only for explicit user / API requests.
    @discardableResult
    public func install(force: Bool = false) throws -> Result {
        try loader.ensureDirectories()
        let seeds = Self.bundledSeedPresets()
        var installed: [String] = []
        var skipped:   [String] = []
        let fm = FileManager.default
        for preset in seeds {
            let url = loader.presetsURL.appendingPathComponent("\(preset.name).json")
            let exists = fm.fileExists(atPath: url.path)
            if exists && !force {
                skipped.append(preset.name)
                continue
            }
            try writer.savePreset(preset)
            installed.append(preset.name)
        }
        LoggerContext.shared.info("SeedInstaller", "Install pass complete", [
            "installed": installed.joined(separator: ","),
            "skipped":   skipped.joined(separator: ","),
            "force":     String(force),
        ])
        return Result(installed: installed, skipped: skipped)
    }

    /// Decode every JSON file shipped under `Resources/seedPresets/` in
    /// the module bundle. Files that fail to parse are skipped with a
    /// warning so a single bad seed cannot block the rest.
    public static func bundledSeedPresets() -> [Preset] {
        let urls = Bundle.module.urls(
            forResourcesWithExtension: "json",
            subdirectory: "seedPresets"
        ) ?? []
        let decoder = JSONDecoder()
        var out: [Preset] = []
        for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            do {
                let data = try Data(contentsOf: url)
                let preset = try decoder.decode(Preset.self, from: data)
                out.append(preset)
            } catch {
                LoggerContext.shared.error("SeedInstaller", "Failed to decode seed", [
                    "url":   url.path,
                    "error": String(describing: error),
                ])
            }
        }
        return out
    }
}
