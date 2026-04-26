import Foundation

public final class ConfigLoader {
    private let decoder: JSONDecoder
    private let baseURL: URL

    /// Environment variable that, when set, overrides the default config
    /// directory. Primarily useful for integration tests and for users who
    /// want to keep config on an external drive.
    public static let configDirEnvVar = "FLOATINGMACRO_CONFIG_DIR"

    public static var defaultBaseURL: URL {
        if let override = ProcessInfo.processInfo.environment[configDirEnvVar],
           !override.isEmpty {
            let expanded = NSString(string: override).expandingTildeInPath
            return URL(fileURLWithPath: expanded, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/FloatingMacro")
    }

    public init(baseURL: URL? = nil) {
        self.decoder = JSONDecoder()
        self.baseURL = baseURL ?? Self.defaultBaseURL
    }

    public var configURL: URL {
        baseURL.appendingPathComponent("config.json")
    }

    public var presetsURL: URL {
        baseURL.appendingPathComponent("presets")
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
        let url = presetsURL.appendingPathComponent("\(name).json")
        do {
            let data = try Data(contentsOf: url)
            let preset = try decoder.decode(Preset.self, from: data)
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
        guard fm.fileExists(atPath: presetsURL.path) else { return [] }
        let files = try fm.contentsOfDirectory(at: presetsURL, includingPropertiesForKeys: nil)
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
        try fm.createDirectory(at: presetsURL, withIntermediateDirectories: true)
        let logsURL = baseURL.appendingPathComponent("logs")
        try fm.createDirectory(at: logsURL, withIntermediateDirectories: true)
    }
}
