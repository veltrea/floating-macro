import Foundation

/// Where a preset file lives on disk. The two locations are kept physically
/// separate so user-authored presets cannot accidentally end up in the
/// distribution `seedPresets/` directory or vice versa.
public enum PresetSource {
    /// Bundled seed (`~/Library/Application Support/FloatingMacro/presets/`).
    /// Treated as read-only — edits trigger a copy-on-write into the user
    /// directory.
    case seed
    /// User-authored (`~/Documents/FloatingMacro/presets/`).
    case user
}

public final class ConfigLoader {
    private let decoder: JSONDecoder
    private let baseURL: URL
    private let userBaseURL: URL

    /// Environment variable that, when set, overrides the default config
    /// directory. Primarily useful for integration tests and for users who
    /// want to keep config on an external drive.
    public static let configDirEnvVar = "FLOATINGMACRO_CONFIG_DIR"

    /// Environment variable that overrides the user-presets directory
    /// (`~/Documents/FloatingMacro`). Used by tests.
    public static let userDirEnvVar = "FLOATINGMACRO_USER_DIR"

    public static var defaultBaseURL: URL {
        if let override = ProcessInfo.processInfo.environment[configDirEnvVar],
           !override.isEmpty {
            let expanded = NSString(string: override).expandingTildeInPath
            return URL(fileURLWithPath: expanded, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/FloatingMacro")
    }

    public static var defaultUserBaseURL: URL {
        if let override = ProcessInfo.processInfo.environment[userDirEnvVar],
           !override.isEmpty {
            let expanded = NSString(string: override).expandingTildeInPath
            return URL(fileURLWithPath: expanded, isDirectory: true)
        }
        // ~/Documents/FloatingMacro
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/FloatingMacro")
    }

    public init(baseURL: URL? = nil, userBaseURL: URL? = nil) {
        self.decoder = JSONDecoder()
        self.baseURL = baseURL ?? Self.defaultBaseURL
        self.userBaseURL = userBaseURL ?? Self.defaultUserBaseURL
    }

    public var configURL: URL {
        baseURL.appendingPathComponent("config.json")
    }

    /// Bundled seed presets directory (read-only territory).
    public var seedPresetsURL: URL {
        baseURL.appendingPathComponent("presets")
    }

    /// User-authored presets directory (`~/Documents/FloatingMacro/presets/`).
    public var userPresetsURL: URL {
        userBaseURL.appendingPathComponent("presets")
    }

    /// Compatibility alias: many call sites still use `presetsURL` and assume
    /// it points at the seed directory. Keep it pointing there so existing
    /// behavior (writing in-place) stays intact for the seed area; new code
    /// should prefer `seedPresetsURL` / `userPresetsURL` explicitly.
    public var presetsURL: URL { seedPresetsURL }

    /// Resolve a preset name to a concrete file URL. User wins over seed when
    /// the same name exists in both directories.
    public func presetURL(name: String) -> URL {
        let userURL = userPresetsURL.appendingPathComponent("\(name).json")
        if FileManager.default.fileExists(atPath: userURL.path) {
            return userURL
        }
        return seedPresetsURL.appendingPathComponent("\(name).json")
    }

    /// Where the preset currently lives. Returns `nil` if the preset doesn't
    /// exist in either directory.
    public func presetSource(name: String) -> PresetSource? {
        let fm = FileManager.default
        let userURL = userPresetsURL.appendingPathComponent("\(name).json")
        if fm.fileExists(atPath: userURL.path) { return .user }
        let seedURL = seedPresetsURL.appendingPathComponent("\(name).json")
        if fm.fileExists(atPath: seedURL.path) { return .seed }
        return nil
    }

    public func loadAppConfig() throws -> AppConfig {
        let log = LoggerContext.shared
        do {
            let data = try Data(contentsOf: configURL)
            let cfg = try decoder.decode(AppConfig.self, from: data)
            log.debug("ConfigLoader", "Loaded app config", [
                "activePreset": cfg.activePreset,
                "path":         configURL.path,
            ])
            return cfg
        } catch {
            log.error("ConfigLoader", "Failed to load app config", [
                "path":  configURL.path,
                "error": String(describing: error),
            ])
            throw error
        }
    }

    public func loadPreset(name: String) throws -> Preset {
        let log = LoggerContext.shared
        let url = presetURL(name: name)
        do {
            let data = try Data(contentsOf: url)
            var preset = try decoder.decode(Preset.self, from: data)

            // Self-heal: if the JSON file lacks a `displayName` key, fall
            // back to the filename and persist the fix. Files dropped in by
            // hand or coming from older versions get a usable display label
            // automatically.
            let raw = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            if raw?["displayName"] == nil {
                let healed = Preset(
                    version: preset.version,
                    name: preset.name,
                    displayName: name,
                    groups: preset.groups
                )
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                if let healedData = try? encoder.encode(healed) {
                    try? healedData.write(to: url, options: .atomic)
                    log.info("ConfigLoader", "Self-healed displayName from filename", [
                        "name":        name,
                        "displayName": name,
                    ])
                }
                preset = healed
            }

            log.debug("ConfigLoader", "Loaded preset", [
                "name":   name,
                "groups": String(preset.groups.count),
            ])
            return preset
        } catch {
            log.error("ConfigLoader", "Failed to load preset", [
                "name":  name,
                "path":  url.path,
                "error": String(describing: error),
            ])
            throw error
        }
    }

    public func listPresets() throws -> [String] {
        let fm = FileManager.default
        var names = Set<String>()
        for url in [userPresetsURL, seedPresetsURL] {
            guard fm.fileExists(atPath: url.path) else { continue }
            let files = try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            for f in files where f.pathExtension == "json" {
                names.insert(f.deletingPathExtension().lastPathComponent)
            }
        }
        return Array(names).sorted()
    }

    /// List preset names that live in the seed (Application Support) area
    /// only. Useful for the migration alert that needs to count "things that
    /// look like user presets in the legacy location".
    public func listSeedPresets() throws -> [String] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: seedPresetsURL.path) else { return [] }
        let files = try fm.contentsOfDirectory(at: seedPresetsURL, includingPropertiesForKeys: nil)
        return files
            .filter { $0.pathExtension == "json" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }

    /// List preset names that live in the user (Documents) area only.
    public func listUserPresets() throws -> [String] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: userPresetsURL.path) else { return [] }
        let files = try fm.contentsOfDirectory(at: userPresetsURL, includingPropertiesForKeys: nil)
        return files
            .filter { $0.pathExtension == "json" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }

    public func findButton(presetName: String, buttonId: String) throws -> ButtonDefinition? {
        let preset = try loadPreset(name: presetName)
        for group in preset.groups {
            if let btn = group.buttons.first(where: { $0.id == buttonId }) {
                return btn
            }
        }
        return nil
    }

    public func ensureDirectories() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: seedPresetsURL, withIntermediateDirectories: true)
        try fm.createDirectory(at: userPresetsURL, withIntermediateDirectories: true)
        let logsURL = baseURL.appendingPathComponent("logs")
        try fm.createDirectory(at: logsURL, withIntermediateDirectories: true)
    }
}
