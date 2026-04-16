import Foundation

public struct ButtonDefinition: Codable, Equatable {
    public let id: String
    public var label: String
    /// Absolute or `~/` path to an icon image (PNG / ICO / ICNS / JPEG).
    /// When set, takes priority over `iconText` for display.
    public var icon: String?
    /// Emoji or 1–2 character glyph used as a lightweight icon fallback.
    public var iconText: String?
    /// Optional background color in `#RRGGBB` or `#RRGGBBAA` hex. When nil
    /// the button uses the system default (transparent with hover tint).
    public var backgroundColor: String?
    /// Optional text color in `#RRGGBB` or `#RRGGBBAA` hex. nil = automatic
    /// (white if a background color is set, primary otherwise).
    public var textColor: String?
    /// Explicit width override in points. nil = auto-size (container width).
    public var width: Double?
    /// Explicit height override in points. nil = auto-size.
    public var height: Double?
    /// Tooltip shown on mouse hover. nil = no tooltip.
    public var tooltip: String?
    public var action: Action

    public init(id: String,
                label: String,
                icon: String? = nil,
                iconText: String? = nil,
                backgroundColor: String? = nil,
                textColor: String? = nil,
                width: Double? = nil,
                height: Double? = nil,
                tooltip: String? = nil,
                action: Action) {
        self.id = id
        self.label = label
        self.icon = icon
        self.iconText = iconText
        self.backgroundColor = backgroundColor
        self.textColor = textColor
        self.width = width
        self.height = height
        self.tooltip = tooltip
        self.action = action
    }

    private enum CodingKeys: String, CodingKey {
        case id, label, icon, iconText, backgroundColor, textColor, width, height, tooltip, action
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id              = try c.decode(String.self, forKey: .id)
        self.label           = try c.decode(String.self, forKey: .label)
        self.icon            = try c.decodeIfPresent(String.self, forKey: .icon)
        self.iconText        = try c.decodeIfPresent(String.self, forKey: .iconText)
        self.backgroundColor = try c.decodeIfPresent(String.self, forKey: .backgroundColor)
        self.textColor       = try c.decodeIfPresent(String.self, forKey: .textColor)
        self.width           = try c.decodeIfPresent(Double.self, forKey: .width)
        self.height          = try c.decodeIfPresent(Double.self, forKey: .height)
        self.tooltip         = try c.decodeIfPresent(String.self, forKey: .tooltip)
        self.action          = try c.decode(Action.self, forKey: .action)
    }
}
