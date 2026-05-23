import Foundation

/// How to draw buttons in a group.
/// .icon: Existing small icon + label (horizontal layout, compact)
/// .wide: Wide cell (icon left-aligned, label centered, long title allowed)
/// .card: Large card (thumbnail above + title below, for prompt gallery)
/// .grid: Icon grid (icon on top + label below, launcher style)
public enum GroupDisplayType: String, Codable, Equatable, CaseIterable {
    case icon
    case wide
    case card
    case grid
}

/// How to fit thumbnails into square cells in a card layout.
/// .fill: fill + crop (default. fills the entire cell with an image)
/// .fit: Fit with padding (shows the entire image. Long side matches cell size).
public enum CardThumbnailMode: String, Codable, Equatable, CaseIterable {
    case fill
    case fit
}

/// Specify column count for card layout.
/// - `auto`: Minimum cell width based responsive (equivalent to CSS Grid's minmax())
/// Fixed column count
public enum GroupColumns: Equatable, Hashable {
    case auto
    case fixed(Int)
}

extension GroupColumns: Codable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let n = try? c.decode(Int.self) {
            self = .fixed(n)
        } else {
            let s = try c.decode(String.self)
            if s == "auto" {
                self = .auto
            } else {
                self = .auto
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .auto: try c.encode("auto")
        case .fixed(let n): try c.encode(n)
        }
    }
}

/// Icon display size for wide layout icons.
/// The card layout is also used for app icon caps.
public enum IconSize: String, Codable, Equatable, CaseIterable, Hashable {
    case small  // 16pt
    case medium // 32pt
    case large  // 48pt
    case xlarge // 64pt

    public var points: CGFloat {
        switch self {
        case .small:  return 16
        case .medium: return 32
        case .large:  return 48
        case .xlarge: return 64
        }
    }
}

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
    /// Layout type of group button. Default `.icon` retains existing behavior.
    /// Old preset files (those without this field) are loaded with `.icon`.
    public var displayType: GroupDisplayType
    /// Number of columns in the card layout. nil = auto (minimum 120pt based).
    /// Fixed column count in 1/2/3. Ignored in icon/wide layout.
    public var columns: GroupColumns
    /// Icon display size. Icon drawing size for wide layout icons,
    /// Used for the app icon cap in card layout applications.
    public var iconSize: IconSize
    /// Display label in grid layout? False: only icon.
    public var showLabels: Bool
    public var buttons: [ButtonDefinition]

    public init(id: String, label: String, icon: String? = nil,
                iconText: String? = nil,
                backgroundColor: String? = nil, textColor: String? = nil,
                tooltip: String? = nil,
                collapsed: Bool = false,
                displayType: GroupDisplayType = .icon,
                columns: GroupColumns = .auto,
                iconSize: IconSize = .medium,
                showLabels: Bool = true,
                buttons: [ButtonDefinition]) {
        self.id = id
        self.label = label
        self.icon = icon
        self.iconText = iconText
        self.backgroundColor = backgroundColor
        self.textColor = textColor
        self.tooltip = tooltip
        self.collapsed = collapsed
        self.displayType = displayType
        self.columns = columns
        self.iconSize = iconSize
        self.showLabels = showLabels
        self.buttons = buttons
    }

    private enum CodingKeys: String, CodingKey {
        case id, label, icon, iconText, backgroundColor, textColor, tooltip,
             collapsed, displayType, columns, iconSize, showLabels, buttons
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
        self.displayType     = try c.decodeIfPresent(GroupDisplayType.self, forKey: .displayType) ?? .icon
        self.columns         = try c.decodeIfPresent(GroupColumns.self, forKey: .columns) ?? .auto
        self.iconSize        = try c.decodeIfPresent(IconSize.self, forKey: .iconSize) ?? .medium
        self.showLabels      = try c.decodeIfPresent(Bool.self, forKey: .showLabels) ?? true
        self.buttons         = try c.decode([ButtonDefinition].self, forKey: .buttons)
    }

    /// When `.icon`, omit the `displayType` key from the encoded result. Existing preset
    /// File (saved before v0.10) unintentionally treated as diff when resaved
    /// Consider backward compatibility to avoid it. Also omit `columns` if `.auto`.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(label, forKey: .label)
        try c.encodeIfPresent(icon, forKey: .icon)
        try c.encodeIfPresent(iconText, forKey: .iconText)
        try c.encodeIfPresent(backgroundColor, forKey: .backgroundColor)
        try c.encodeIfPresent(textColor, forKey: .textColor)
        try c.encodeIfPresent(tooltip, forKey: .tooltip)
        try c.encode(collapsed, forKey: .collapsed)
        if displayType != .icon { try c.encode(displayType, forKey: .displayType) }
        if columns != .auto { try c.encode(columns, forKey: .columns) }
        if iconSize != .medium { try c.encode(iconSize, forKey: .iconSize) }
        if !showLabels { try c.encode(showLabels, forKey: .showLabels) }
        try c.encode(buttons, forKey: .buttons)
    }
}

public struct Preset: Codable, Equatable {
    public let version: Int
    public let name: String
    public var displayName: String
    /// Free-form memo for the entire preset. "Assumption before use", "F1-F12 are used by the OS"
    /// Function key needs to be set. Make the target app frontmost before...
    /// A column for leaving operational notes such as "tap" or other precautions. Multiple lines allowed, Markdown decoration not supported.
    /// Draw the collapsible block on the panel side only if nil or empty string.
    public var memo: String?
    public var groups: [ButtonGroup]

    public init(version: Int = 1, name: String, displayName: String,
                memo: String? = nil, groups: [ButtonGroup]) {
        self.version = version
        self.name = name
        self.displayName = displayName
        self.memo = memo
        self.groups = groups
    }

    private enum CodingKeys: String, CodingKey {
        case version, name, displayName, memo, groups
    }

    /// Decoder is tolerant of missing `displayName` so older / hand-written
    /// preset files still load. ConfigLoader also performs an explicit
    /// write-back so the file gets healed on disk; this fallback only
    /// ensures the in-memory value is sane when displayName is absent.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.version     = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        self.name        = try c.decode(String.self, forKey: .name)
        self.displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? self.name
        self.memo        = try c.decodeIfPresent(String.self, forKey: .memo)
        self.groups      = try c.decode([ButtonGroup].self, forKey: .groups)
    }
}

/// Multiple presets bundled into one file for distribution / backup.
/// Single-preset exports use the bare `Preset` JSON; bundles wrap a list.
/// Importers detect the format by checking for the `presets` key.
public struct PresetBundle: Codable, Equatable {
    public let version: Int
    public var presets: [Preset]

    public init(version: Int = 1, presets: [Preset]) {
        self.version = version
        self.presets = presets
    }

    private enum CodingKeys: String, CodingKey {
        case version, presets
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        self.presets = try c.decode([Preset].self, forKey: .presets)
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
    /// Panel background color in `#RRGGBB` hex. nil = system default
    /// (`NSColor.windowBackgroundColor` at 95% opacity).
    public var backgroundColor: String?

    public init(x: Double = 100, y: Double = 100,
                width: Double = 200, height: Double = 300,
                orientation: String = "vertical",
                alwaysOnTop: Bool = true,
                hideAfterAction: Bool = false,
                opacity: Double = 1.0,
                backgroundColor: String? = nil) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.orientation = orientation
        self.alwaysOnTop = alwaysOnTop
        self.hideAfterAction = hideAfterAction
        self.opacity = opacity
        self.backgroundColor = backgroundColor
    }

    private enum CodingKeys: String, CodingKey {
        case x, y, width, height, orientation, alwaysOnTop, hideAfterAction, opacity, backgroundColor
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
        self.backgroundColor = try c.decodeIfPresent(String.self, forKey: .backgroundColor)
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
    /// Introduced in Phase 5 (v0.13). When true, only use loopback for the HTTP listener.
    /// Bind to all interfaces (0.0.0.0) and other terminals on the same local network
    /// Accept connections from (smartphones, tablets, etc.). Default is false.
    /// When publicly available, change the menu bar icon to red color and visually warn.
    /// Existing Bearer token, plus ephemeral LAN token for restart invalidation.
    /// Separate from PanelManager, perform authentication via QR code.
    public var lanExposureEnabled: Bool
    /// LAN remote control port. ACP (loopback) is used with a separate listener.
    /// The default is `port + 1` (= 17431). If not existing in the existing JSON,
    /// Fallback to `port + 1` (backward compatibility).
    public var lanPort: Int

    public init(enabled: Bool = false,
                port: Int = 17430,
                agentMode: AgentMode = .normal,
                requireAuth: Bool = true,
                testMode: Bool = false,
                lanExposureEnabled: Bool = false,
                lanPort: Int? = nil) {
        self.enabled            = enabled
        self.port               = port
        self.agentMode          = agentMode
        self.requireAuth        = requireAuth
        self.testMode           = testMode
        self.lanExposureEnabled = lanExposureEnabled
        let lp = lanPort ?? (port + 1)
        self.lanPort            = lp == port ? port + 1 : lp
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, port, agentMode, requireAuth, testMode, lanExposureEnabled, lanPort
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.enabled            = try c.decodeIfPresent(Bool.self,      forKey: .enabled)            ?? false
        self.port               = try c.decodeIfPresent(Int.self,       forKey: .port)               ?? 17430
        self.agentMode          = try c.decodeIfPresent(AgentMode.self, forKey: .agentMode)          ?? .normal
        self.requireAuth        = try c.decodeIfPresent(Bool.self,      forKey: .requireAuth)        ?? true
        self.testMode           = try c.decodeIfPresent(Bool.self,      forKey: .testMode)           ?? false
        self.lanExposureEnabled = try c.decodeIfPresent(Bool.self,      forKey: .lanExposureEnabled) ?? false
        let lp = try c.decodeIfPresent(Int.self, forKey: .lanPort) ?? (self.port + 1)
        self.lanPort            = lp == self.port ? self.port + 1 : lp
    }
}

/// The edge of the screen on which the panel is docked.
public enum DockEdge: String, Codable, Sendable {
    case left, right, top, bottom
}

/// Introduced in Phase 3 (v0.12). One floating window = one Panel.
/// Combination of old `AppConfig.activePreset` and `AppConfig.window` to form a panel array
/// persistent identifier (UUID string), PanelManager is
/// Manage an NSWindow with this ID.
public struct PanelConfig: Codable, Equatable {
    public let id: String
    public var presetName: String
    public var window: WindowConfig
    /// nil = Normal display (expanding). If edges are set, docked to screen edge.
    /// Phase 3.5 type change from old minimizedToEdge: Bool to new type.
    public var dockedEdge: DockEdge?
    /// Custom position when dragging the dock bar. nil means automatic layout.
    public var dockBarPosition: DockBarPosition?
    public var visible: Bool
    public var scrollY: Double

    public init(id: String = UUID().uuidString,
                presetName: String,
                window: WindowConfig = WindowConfig(),
                dockedEdge: DockEdge? = nil,
                dockBarPosition: DockBarPosition? = nil,
                visible: Bool = true,
                scrollY: Double = 0) {
        self.id              = id
        self.presetName      = presetName
        self.window          = window
        self.dockedEdge      = dockedEdge
        self.dockBarPosition = dockBarPosition
        self.visible         = visible
        self.scrollY         = scrollY
    }

    private enum CodingKeys: String, CodingKey {
        case id, presetName, window, dockedEdge, dockBarPosition, minimizedToEdge, visible, scrollY
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id              = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        self.presetName      = try c.decode(String.self, forKey: .presetName)
        self.window          = try c.decodeIfPresent(WindowConfig.self, forKey: .window) ?? WindowConfig()
        // Phase 3.5: If dockedEdge exists, use it; otherwise, migrate the old minimizedToEdge: true to .right.
        if let edge = try c.decodeIfPresent(DockEdge.self, forKey: .dockedEdge) {
            self.dockedEdge = edge
        } else if let legacy = try c.decodeIfPresent(Bool.self, forKey: .minimizedToEdge),
                  legacy == true {
            self.dockedEdge = .right
        } else {
            self.dockedEdge = nil
        }
        self.dockBarPosition = try c.decodeIfPresent(DockBarPosition.self, forKey: .dockBarPosition)
        self.visible         = try c.decodeIfPresent(Bool.self, forKey: .visible) ?? true
        self.scrollY         = try c.decodeIfPresent(Double.self, forKey: .scrollY) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(presetName, forKey: .presetName)
        try c.encode(window, forKey: .window)
        try c.encodeIfPresent(dockedEdge, forKey: .dockedEdge)
        try c.encodeIfPresent(dockBarPosition, forKey: .dockBarPosition)
        try c.encode(visible, forKey: .visible)
        try c.encode(scrollY, forKey: .scrollY)
    }
}

public struct DockBarPosition: Codable, Equatable {
    public var x: Double
    public var y: Double
    public var edge: DockEdge?
    public init(x: Double, y: Double, edge: DockEdge? = nil) {
        self.x = x
        self.y = y
        self.edge = edge
    }
}

public struct AppConfig: Codable, Equatable {
    public let version: Int
    /// Legacy v1 compatibility field. Phase 3 migration period synchronized with `panels[0].presetName`.
    /// Written out. New code treats `panels` as the true source.
    public var activePreset: String
    /// Legacy v1 compatibility fields. Synchronize with panels[0].window during Phase 3 migration period.
    /// Written out. New code treats each PanelConfig.window as the true source.
    public var window: WindowConfig
    public var controlAPI: ControlAPIConfig
    public var commandBlacklist: CommandBlacklist
    /// Set to true the first time bundled seed presets (MidJourney, note
    /// hashtags, etc.) have been copied into the user's presets directory.
    /// Subsequent launches skip the install pass so user edits are not
    /// overwritten. The control API exposes a `force` re-install endpoint.
    public var seedInstalled: Bool
    /// One-shot flag: set to true after the v0.16+ "personal-preset location
    /// changed" alert has been shown.
    ///
    /// - Newly-created config: initialized to `true` (no alert needed —
    ///   nothing to migrate).
    /// - Existing config decoded without this key: defaults to `false` so
    ///   the user gets the alert exactly once. The alert simply tells them
    ///   that their old personal presets still live in
    ///   `~/Library/Application Support/FloatingMacro/presets/` and that
    ///   they should move the ones they want to keep into
    ///   `~/Documents/FloatingMacro/presets/` before migrating to a new
    ///   Mac (the legacy folder is hidden in `~/Library/`, easy to miss).
    public var migrationAlertShown: Bool
    /// User-chosen order of presets in the picker. Names not listed here are
    /// appended at the end in alphabetical order. Empty array means "fall
    /// back to alphabetical order entirely" — that is also the default for
    /// configs written by older versions.
    public var presetOrder: [String]
    /// Introduced in Phase 3 (v0.12). Multiple floating panel definitions introduced.
    /// Old configuration file (this field is missing / empty) the decoder will
    /// Automatically migrate one panel from `activePreset` and `window`.
    public var panels: [PanelConfig]

    public init(version: Int = 1,
                activePreset: String = "default",
                window: WindowConfig = WindowConfig(),
                controlAPI: ControlAPIConfig = ControlAPIConfig(),
                commandBlacklist: CommandBlacklist = CommandBlacklist(),
                seedInstalled: Bool = false,
                migrationAlertShown: Bool = true,
                presetOrder: [String] = [],
                panels: [PanelConfig] = []) {
        self.version             = version
        self.activePreset        = activePreset
        self.window              = window
        self.controlAPI          = controlAPI
        self.commandBlacklist    = commandBlacklist
        self.seedInstalled       = seedInstalled
        self.migrationAlertShown = migrationAlertShown
        self.presetOrder         = presetOrder
        // If panels is empty, automatically generate one from the active preset and window (migration from old v1 to v2).
        if panels.isEmpty {
            self.panels = [PanelConfig(presetName: activePreset, window: window)]
        } else {
            self.panels = panels
        }
    }

    private enum CodingKeys: String, CodingKey {
        case version, activePreset, window, controlAPI, commandBlacklist, seedInstalled, migrationAlertShown, presetOrder, panels
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.version             = try c.decodeIfPresent(Int.self,               forKey: .version)             ?? 1
        self.activePreset        = try c.decodeIfPresent(String.self,            forKey: .activePreset)        ?? "default"
        self.window              = try c.decodeIfPresent(WindowConfig.self,      forKey: .window)              ?? WindowConfig()
        self.controlAPI          = try c.decodeIfPresent(ControlAPIConfig.self,  forKey: .controlAPI)          ?? ControlAPIConfig()
        self.commandBlacklist    = try c.decodeIfPresent(CommandBlacklist.self,  forKey: .commandBlacklist)    ?? CommandBlacklist()
        self.seedInstalled       = try c.decodeIfPresent(Bool.self,              forKey: .seedInstalled)       ?? false
        self.migrationAlertShown = try c.decodeIfPresent(Bool.self,              forKey: .migrationAlertShown) ?? false
        self.presetOrder         = try c.decodeIfPresent([String].self,          forKey: .presetOrder)         ?? []
        let decodedPanels     = try c.decodeIfPresent([PanelConfig].self,     forKey: .panels)           ?? []
        // Form (missing panels / empty) is generated once from activePreset + window and migrated.
        if decodedPanels.isEmpty {
            self.panels = [PanelConfig(presetName: self.activePreset, window: self.window)]
        } else {
            self.panels = decodedPanels
        }
    }
}
