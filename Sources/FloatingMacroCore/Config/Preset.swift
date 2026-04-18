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

/// Blacklist of forbidden substrings checked before any terminal / text action
/// is executed. When `enabled` is true and the command or pasted text contains
/// any of the `patterns` (case-insensitive substring match), a confirmation
/// dialog is shown before execution proceeds.
///
/// ## Autopilot mode
/// When `autopilotEnabled` is true the confirmation dialog is skipped and all
/// commands run without user interaction (useful for fully automated workflows).
/// Enabling autopilot requires the user to enter the passphrase whose SHA-256
/// hash is stored in `autopilotPasswordHash`. If no hash is stored, autopilot
/// cannot be enabled from the UI.
public struct CommandBlacklist: Codable, Equatable {
    public var enabled: Bool
    /// Forbidden substrings. Each entry is matched case-insensitively anywhere
    /// within the command / pasted text.
    public var patterns: [String]
    /// When true, all commands are executed without a confirmation dialog even
    /// if they match a forbidden pattern.
    public var autopilotEnabled: Bool
    /// SHA-256 hex digest of the passphrase required to enable autopilot.
    /// `nil` means no password has been set and autopilot cannot be enabled.
    public var autopilotPasswordHash: String?

    /// Sensible defaults — covers the most common destructive shell commands.
    public static let defaultPatterns: [String] = [
        "rm -rf",
        "rm -fr",
        "sudo rm",
        "> /dev/",
        "dd if=/dev/",
        "mkfs",
        ":(){ :|:& };:",   // fork bomb
        "chmod -R 777",
        "chmod 777 /",
        "sudo chmod",
        "shred ",
        "wipefs",
        "diskutil eraseDisk",
        "diskutil zeroDisk",
        "format c:",
    ]

    public init(enabled: Bool = true,
                patterns: [String] = CommandBlacklist.defaultPatterns,
                autopilotEnabled: Bool = false,
                autopilotPasswordHash: String? = nil) {
        self.enabled              = enabled
        self.patterns             = patterns
        self.autopilotEnabled     = autopilotEnabled
        self.autopilotPasswordHash = autopilotPasswordHash
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, patterns, autopilotEnabled, autopilotPasswordHash
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.enabled               = try c.decodeIfPresent(Bool.self,     forKey: .enabled)               ?? true
        self.patterns              = try c.decodeIfPresent([String].self, forKey: .patterns)              ?? CommandBlacklist.defaultPatterns
        self.autopilotEnabled      = try c.decodeIfPresent(Bool.self,     forKey: .autopilotEnabled)      ?? false
        self.autopilotPasswordHash = try c.decodeIfPresent(String.self,   forKey: .autopilotPasswordHash)
    }
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
    /// When true, all endpoints except /ping require a Bearer token that
    /// matches the value stored in Keychain. Defaults to true.
    public var requireAuth: Bool
    /// When true, Bearer authentication is skipped entirely regardless of
    /// `requireAuth`. Intended for smoke tests and CI environments where
    /// interactive Keychain dialogs are not acceptable.
    public var testMode: Bool

    public init(enabled: Bool = false,
                port: Int = 17430,
                agentMode: AgentMode = .normal,
                requireAuth: Bool = true,
                testMode: Bool = false) {
        self.enabled     = enabled
        self.port        = port
        self.agentMode   = agentMode
        self.requireAuth = requireAuth
        self.testMode    = testMode
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, port, agentMode, requireAuth, testMode
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.enabled     = try c.decodeIfPresent(Bool.self,      forKey: .enabled)     ?? false
        self.port        = try c.decodeIfPresent(Int.self,       forKey: .port)        ?? 17430
        self.agentMode   = try c.decodeIfPresent(AgentMode.self, forKey: .agentMode)   ?? .normal
        self.requireAuth = try c.decodeIfPresent(Bool.self,      forKey: .requireAuth) ?? true
        self.testMode    = try c.decodeIfPresent(Bool.self,      forKey: .testMode)    ?? false
    }
}

public struct AppConfig: Codable, Equatable {
    public let version: Int
    public var activePreset: String
    public var window: WindowConfig
    public var controlAPI: ControlAPIConfig
    public var commandBlacklist: CommandBlacklist

    public init(version: Int = 1,
                activePreset: String = "default",
                window: WindowConfig = WindowConfig(),
                controlAPI: ControlAPIConfig = ControlAPIConfig(),
                commandBlacklist: CommandBlacklist = CommandBlacklist()) {
        self.version          = version
        self.activePreset     = activePreset
        self.window           = window
        self.controlAPI       = controlAPI
        self.commandBlacklist = commandBlacklist
    }

    private enum CodingKeys: String, CodingKey {
        case version, activePreset, window, controlAPI, commandBlacklist
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.version          = try c.decodeIfPresent(Int.self,               forKey: .version)          ?? 1
        self.activePreset     = try c.decodeIfPresent(String.self,            forKey: .activePreset)     ?? "default"
        self.window           = try c.decodeIfPresent(WindowConfig.self,      forKey: .window)           ?? WindowConfig()
        self.controlAPI       = try c.decodeIfPresent(ControlAPIConfig.self,  forKey: .controlAPI)       ?? ControlAPIConfig()
        self.commandBlacklist = try c.decodeIfPresent(CommandBlacklist.self,  forKey: .commandBlacklist) ?? CommandBlacklist()
    }
}
