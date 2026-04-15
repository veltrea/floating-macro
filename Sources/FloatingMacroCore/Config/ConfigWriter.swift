import Foundation

public final class ConfigWriter {
    private let encoder: JSONEncoder
    private let baseURL: URL

    public init(baseURL: URL? = nil) {
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.baseURL = baseURL ?? ConfigLoader.defaultBaseURL
    }

    public func saveAppConfig(_ config: AppConfig) throws {
        let url = baseURL.appendingPathComponent("config.json")
        let data = try encoder.encode(config)
        try data.write(to: url, options: .atomic)
    }

    public func savePreset(_ preset: Preset) throws {
        let url = baseURL.appendingPathComponent("presets/\(preset.name).json")
        let data = try encoder.encode(preset)
        try data.write(to: url, options: .atomic)
    }

    public func writeDefaultConfigIfNeeded() throws {
        let fm = FileManager.default
        let loader = ConfigLoader(baseURL: baseURL)
        try loader.ensureDirectories()

        let configURL = baseURL.appendingPathComponent("config.json")
        if !fm.fileExists(atPath: configURL.path) {
            try saveAppConfig(AppConfig())
        }

        let defaultPresetURL = baseURL.appendingPathComponent("presets/default.json")
        if !fm.fileExists(atPath: defaultPresetURL.path) {
            let preset = Preset(
                name: "default",
                displayName: "デフォルト",
                groups: [
                    ButtonGroup(
                        id: "group-1",
                        label: "AI",
                        buttons: [
                            ButtonDefinition(
                                id: "btn-ultrathink",
                                label: "ultrathink",
                                iconText: "🧠",
                                action: .text(
                                    content: "ultrathink で次のタスクに取り組んでください。",
                                    pasteDelayMs: 120,
                                    restoreClipboard: true
                                )
                            ),
                            ButtonDefinition(
                                id: "btn-stop-loop",
                                label: "止まって",
                                iconText: "⏸",
                                action: .text(
                                    content: "ループっぽいので一旦止まって、現状と次のアクションを報告してください。",
                                    pasteDelayMs: 120,
                                    restoreClipboard: true
                                )
                            ),
                        ]
                    )
                ]
            )
            try savePreset(preset)
        }
    }
}
