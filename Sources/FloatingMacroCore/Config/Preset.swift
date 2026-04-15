import Foundation

public struct ButtonGroup: Codable, Equatable {
    public let id: String
    public var label: String
    public var collapsed: Bool
    public var buttons: [ButtonDefinition]

    public init(id: String, label: String, collapsed: Bool = false, buttons: [ButtonDefinition]) {
        self.id = id
        self.label = label
        self.collapsed = collapsed
        self.buttons = buttons
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

/// Local HTTP control API settings. See Sources/FloatingMacroApp/ControlAPI/.
public struct ControlAPIConfig: Codable, Equatable {
    /// When true, the GUI process opens a localhost-bound HTTP listener so
    /// external tools (and AI assistants) can observe and drive the app.
    public var enabled: Bool
    /// Preferred port. If taken, the server tries `port+1` … `port+9`.
    public var port: Int

    public init(enabled: Bool = false, port: Int = 17430) {
        self.enabled = enabled
        self.port = port
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
