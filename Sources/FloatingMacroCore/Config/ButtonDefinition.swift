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
    /// Display a confirmation dialog before clicking. Prevent accidental clicks and gaze input users.
    /// Prevent unintended triggering to avoid operations (restart, shutdown, etc.) - true.
    public var confirm: Bool
    /// Confirmation dialog body. If empty or nil, automatically generate from button label.
    public var confirmMessage: String?
    /// True to make the "Execute" button red with a destructive style.
    /// Only allow true for irreversible operations (shutdown, etc.).
    public var confirmDestructive: Bool
    /// How to fit an image into square cells in a card layout.
    /// .fill (default) = crop, .fit = full display. Select by button unit.
    public var cardThumbnailMode: CardThumbnailMode
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
                confirm: Bool = false,
                confirmMessage: String? = nil,
                confirmDestructive: Bool = false,
                cardThumbnailMode: CardThumbnailMode = .fill,
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
        self.confirm = confirm
        self.confirmMessage = confirmMessage
        self.confirmDestructive = confirmDestructive
        self.cardThumbnailMode = cardThumbnailMode
        self.action = action
    }

    private enum CodingKeys: String, CodingKey {
        case id, label, icon, iconText, backgroundColor, textColor, width, height, tooltip,
             confirm, confirmMessage, confirmDestructive, thumbnail, cardThumbnailMode, action
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id                 = try c.decode(String.self, forKey: .id)
        self.label              = try c.decode(String.self, forKey: .label)
        self.icon               = try c.decodeIfPresent(String.self, forKey: .icon)
        self.iconText           = try c.decodeIfPresent(String.self, forKey: .iconText)
        self.backgroundColor    = try c.decodeIfPresent(String.self, forKey: .backgroundColor)
        self.textColor          = try c.decodeIfPresent(String.self, forKey: .textColor)
        self.width              = try c.decodeIfPresent(Double.self, forKey: .width)
        self.height             = try c.decodeIfPresent(Double.self, forKey: .height)
        self.tooltip            = try c.decodeIfPresent(String.self, forKey: .tooltip)
        self.confirm            = try c.decodeIfPresent(Bool.self, forKey: .confirm) ?? false
        self.confirmMessage     = try c.decodeIfPresent(String.self, forKey: .confirmMessage)
        self.confirmDestructive = try c.decodeIfPresent(Bool.self, forKey: .confirmDestructive) ?? false
        let legacyThumbnail     = try c.decodeIfPresent(String.self, forKey: .thumbnail)
        if self.icon == nil, let t = legacyThumbnail { self.icon = t }
        self.cardThumbnailMode  = try c.decodeIfPresent(CardThumbnailMode.self, forKey: .cardThumbnailMode) ?? .fill
        self.action             = try c.decode(Action.self, forKey: .action)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(label, forKey: .label)
        try c.encodeIfPresent(icon, forKey: .icon)
        try c.encodeIfPresent(iconText, forKey: .iconText)
        try c.encodeIfPresent(backgroundColor, forKey: .backgroundColor)
        try c.encodeIfPresent(textColor, forKey: .textColor)
        try c.encodeIfPresent(width, forKey: .width)
        try c.encodeIfPresent(height, forKey: .height)
        try c.encodeIfPresent(tooltip, forKey: .tooltip)
        try c.encode(confirm, forKey: .confirm)
        try c.encodeIfPresent(confirmMessage, forKey: .confirmMessage)
        try c.encode(confirmDestructive, forKey: .confirmDestructive)
        if cardThumbnailMode != .fill { try c.encode(cardThumbnailMode, forKey: .cardThumbnailMode) }
        try c.encode(action, forKey: .action)
    }
}
