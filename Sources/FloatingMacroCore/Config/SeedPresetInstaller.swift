import Foundation

/// Copies "seed" presets (e.g. MidJourney 用, note.com ハッシュタグ) into the
/// user's presets directory on first launch. Two sources are supported:
///
/// - **Bundled**: JSON files shipped inside the app bundle under
///   `Resources/seedPresets/`. Always available, used as the offline-safe
///   fallback and as the synchronous baseline so the panel is never empty.
/// - **Network**: the public catalog at
///   `github.com/veltrea/floating-macro-preset` fetched via
///   `PresetCatalogClient`. Used to refresh seeds with newer revisions
///   shipped after the app was built. Network calls are best-effort — any
///   failure leaves the bundled copy untouched.
///
/// Once `AppConfig.seedInstalled` flips to true the install pass is skipped
/// on subsequent launches; the control API exposes a `force` mode for tests
/// and for users who want to restore the originals after deleting them.
///
/// File-level idempotency: even with `force=false`, an individual seed is
/// skipped when a file with the same internal id already exists, so user
/// edits are never overwritten.
public final class SeedPresetInstaller {
    private let writer:         ConfigWriter
    private let loader:         ConfigLoader
    private let catalogClient:  PresetCatalogClient

    public init(baseURL: URL? = nil,
                catalogClient: PresetCatalogClient = PresetCatalogClient()) {
        self.writer        = ConfigWriter(baseURL: baseURL)
        self.loader        = ConfigLoader(baseURL: baseURL)
        self.catalogClient = catalogClient
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

    /// Run the bundled install pass. Synchronous, local-only, fast.
    ///
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
            try writer.savePresetToSeed(preset)
            installed.append(preset.name)
        }
        LoggerContext.shared.info("SeedInstaller", "Bundled install pass complete", [
            "installed": installed.joined(separator: ","),
            "skipped":   skipped.joined(separator: ","),
            "force":     String(force),
        ])
        return Result(installed: installed, skipped: skipped)
    }

    /// Run the network refresh pass: fetch `index.json` from the catalog and
    /// overwrite any default-listed seed with the live version. Each fetch
    /// is best-effort — if the catalog is unreachable or a single preset
    /// fails to download, the bundled copy already on disk stays in place.
    ///
    /// Designed to be called from a background dispatch queue. Returns the
    /// list of ids that were actually overwritten from the network.
    @discardableResult
    public func refreshFromCatalog() -> [String] {
        try? loader.ensureDirectories()
        guard let index = catalogClient.fetchIndex() else {
            LoggerContext.shared.info("SeedInstaller", "Catalog unreachable, keeping bundled seeds", [:])
            return []
        }
        let entriesById = Dictionary(uniqueKeysWithValues: index.presets.map { ($0.id, $0) })
        var refreshed: [String] = []
        for id in index.defaults {
            guard let entry = entriesById[id] else { continue }
            guard let preset = catalogClient.fetchPreset(filePath: entry.file) else { continue }
            do {
                try writer.savePresetToSeed(preset)
                refreshed.append(id)
            } catch {
                LoggerContext.shared.warn("SeedInstaller", "Failed to save catalog preset", [
                    "id":    id,
                    "error": String(describing: error),
                ])
            }
        }
        LoggerContext.shared.info("SeedInstaller", "Catalog refresh complete", [
            "refreshed": refreshed.joined(separator: ","),
            "total":     String(index.defaults.count),
        ])
        return refreshed
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
