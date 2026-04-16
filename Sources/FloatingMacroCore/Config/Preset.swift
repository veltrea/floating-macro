import Foundation

public struct ButtonGroup: Codable, Equatable {
    public let id: String
    public var label: String
    /// Icon source: app bundle id, file path, or `sf:symbolName`.
    /// Uses the same resolution as ButtonDefinition.icon (via IconLoader).
    public var icon: String?
    /// Emoji or short glyph used as a lightweight icon fallback.
    public var iconText: String?
    /// Background color in `#RRGGBB` hex for the group header.
    public var backgroundColor: String?
    /// Text color in `#RRGGBB` hex for the group header label.
    public var textColor: String?
    /// Tooltip shown on mouse hover over the group header.
    public var tooltip: String?
    public var collapsed: Bool
    public var buttons: [ButtonDefinition]

    public init(id: String, label: String, icon: String? = nil,
                iconText: String? = nil,
                backgroundColor: String? = nil, textColor: String? = nil,
                tooltip: String? = nil,
                collapsed: Bool = false, buttons: [ButtonDefinition]) {
        self.id = id
        self.label = label
        self.icon = icon
        self.iconText = iconText
        self.backgroundColor = backgroundColor
        self.textColor = textColor
        self.tooltip = tooltip
        self.collapsed = collapsed
        self.buttons = buttons
    }

    private enum CodingKeys: String, CodingKey {
        case id, label, icon, iconText, backgroundColor, textColor, tooltip, collapsed, buttons
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id              = try c.decode(String.self, forKey: .id)
        self.label           = try c.decode(String.self, forKey: .label)
        self.icon            = try c.decodeIfPresent(String.self, forKey: .icon)
        self.iconText        = try c.decodeIfPresent(String.self, forKey: .iconText)
        self.backgroundColor = try c.decodeIfPresent(String.self, forKey: .backgroundColor)
        self.textColor       = try c.decodeIfPresent(String.self, forKey: .textColor)
        self.tooltip         = try c.decodeIfPresent(String.self, forKey: .tooltip)
        self.collapsed       = try c.decodeIfPresent(Bool.self, forKey: .collapsed) ?? false
        self.buttons         = try c.decode([ButtonDefinition].self, forKey: .buttons)
    }
}

public struct Preset: Codable, Equatable {
    public let version: Int
    public let name: String
    public var displayName: String
    public var groups: [ButtonGroup]

    public init(version: Int = 1, name: String, displayName: String, groups: [ButtonGroup]) {
        self.version = version
        self.name = name
        self.displayName = displayName
        self.groups = groups
    }
}

public struct WindowConfig: Codable, Equatable {
    public var x: Double
    public var y: Double
    /// Width is optional on disk for backward compatibility — older configs
    /// that predate this field continue to load with the default.
    public var width: Double
    public var height: Double
    public var orientation: String
    public var alwaysOnTop: Bool
    public var hideAfterAction: Bool
    public var opacity: Double

    public init(x: Double = 100, y: Double = 100,
                width: Double = 200, height: Double = 300,
                orientation: String = "vertical",
                alwaysOnTop: Bool = true,
                hideAfterAction: Bool = false,
                opacity: Double = 1.0) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.orientation = orientation
        self.alwaysOnTop = alwaysOnTop
        self.hideAfterAction = hideAfterAction
        self.opacity = opacity
    }

    private enum CodingKeys: String, CodingKey {
        case x, y, width, height, orientation, alwaysOnTop, hideAfterAction, opacity
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.x               = try c.decodeIfPresent(Double.self, forKey: .x) ?? 100
        self.y               = try c.decodeIfPresent(Double.self, forKey: .y) ?? 100
        self.width           = try c.decodeIfPresent(Double.self, forKey: .width) ?? 200
        self.height          = try c.decodeIfPresent(Double.self, forKey: .height) ?? 300
        self.orientation     = try c.decodeIfPresent(String.self, forKey: .orientation) ?? "vertical"
        self.alwaysOnTop     = try c.decodeIfPresent(Bool.self,   forKey: .alwaysOnTop) ?? true
        self.hideAfterAction = try c.decodeIfPresent(Bool.self,   forKey: .hideAfterAction) ?? false
        self.opacity         = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 1.0
    }
}

/// The role the AI agent is expected to play when connected to the control API.
/// Set via `controlAPI.agentMode` in config.json.
public enum AgentMode: String, Codable, Equatable {
    /// General-purpose operator: transparent tool usage + context awareness.
    /// The agent checks current state on connect and acts as invisible hands.
    case normal
    /// Dedicated test agent: reads logs first, generates test cases from
    /// SPEC.md, proposes fixes as diffs, and produces a test-completion report.
    case test
    /// Claude Code assistant: specialised for coding sessions. Sets up
    /// terminal layouts, injects prompts, and keeps the environment tidy.
    case claudeCode
}

/// Local HTTP control API settings. See Sources/FloatingMacroApp/ControlAPI/.
public struct ControlAPIConfig: Codable, Equatable {
    /// When true, the GUI process opens a localhost-bound HTTP listener so
    /// external tools (and AI assistants) can observe and drive the app.
    public var enabled: Bool
    /// Preferred port. If taken, the server tries `port+1` … `port+9`.
    public var port: Int
    /// Controls which system prompt GET /manifest returns.
    /// Defaults to `.normal`. See `AgentMode` for available values.
    public var agentMode: AgentMode

    public init(enabled: Bool = false, port: Int = 17430, agentMode: AgentMode = .normal) {
        self.enabled = enabled
        self.port = port
        self.agentMode = agentMode
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, port, agentMode
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.enabled   = try c.decodeIfPresent(Bool.self,      forKey: .enabled)   ?? false
        self.port      = try c.decodeIfPresent(Int.self,       forKey: .port)      ?? 17430
        self.agentMode = try c.decodeIfPresent(AgentMode.self, forKey: .agentMode) ?? .normal
    }
}

public struct AppConfig: Codable, Equatable {
    public let version: Int
    public var activePreset: String
    public var window: WindowConfig
    public var controlAPI: ControlAPIConfig

    public init(version: Int = 1,
                activePreset: String = "default",
                window: WindowConfig = WindowConfig(),
                controlAPI: ControlAPIConfig = ControlAPIConfig()) {
        self.version = version
        self.activePreset = activePreset
        self.window = window
        self.controlAPI = controlAPI
    }

    private enum CodingKeys: String, CodingKey {
        case version, activePreset, window, controlAPI
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.version      = try c.decodeIfPresent(Int.self,             forKey: .version) ?? 1
        self.activePreset = try c.decodeIfPresent(String.self,          forKey: .activePreset) ?? "default"
        self.window       = try c.decodeIfPresent(WindowConfig.self,    forKey: .window) ?? WindowConfig()
        self.controlAPI   = try c.decodeIfPresent(ControlAPIConfig.self, forKey: .controlAPI) ?? ControlAPIConfig()
    }
}
