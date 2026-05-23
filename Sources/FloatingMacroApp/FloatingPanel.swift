import AppKit

/// Floating panel that does not steal focus
final class FloatingPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        // floating settings
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        isFloatingPanel = true
        hidesOnDeactivate = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true

        // non-intrusive focus
        becomesKeyOnlyIfNeeded = true

        // background
        isOpaque = false
        backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.95)

        // drag move
        isMovableByWindowBackground = true

        // Position/size are owned by config.json — the app loads them on
        // launch and writes them back on terminate via
        // PresetManager.setPanelFrame. We intentionally do NOT use
        // setFrameAutosaveName here, which would otherwise race with the
        // config file for the source of truth.
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Convert `#RRGGBB` hex to NSColor. Return nil or default if string is invalid or nil.
    ///
    /// If a custom background color is set, adjust the brightness of the background accordingly.
    /// Set the window's appearance to `.aqua` (light) / `.darkAqua` (dark).
    /// Forcedly, SwiftUI's `Color.primary` and `.secondary` as text color
    /// Maintain the readable state. No custom background color (equals system default) when.
    /// Set appearance to nil and follow the system.
    func applyBackgroundColor(hex: String?) {
        guard let hex, hex.count >= 7, hex.hasPrefix("#"),
              let r = UInt8(hex.dropFirst().prefix(2), radix: 16),
              let g = UInt8(hex.dropFirst(3).prefix(2), radix: 16),
              let b = UInt8(hex.dropFirst(5).prefix(2), radix: 16) else {
            backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.95)
            appearance = nil   // Return to system follow-up
            return
        }
        let rf = CGFloat(r) / 255
        let gf = CGFloat(g) / 255
        let bf = CGFloat(b) / 255
        backgroundColor = NSColor(
            srgbRed: rf,
            green:   gf,
            blue:    bf,
            alpha:   0.95
        )

        // Determine brightness using sRGB relative luminance (ITU-R BT.709).
        let luminance = 0.2126 * rf + 0.7152 * gf + 0.0722 * bf
        appearance = NSAppearance(named: luminance > 0.5 ? .aqua : .darkAqua)
    }

    /// Close button / ⌘W → Minimize to icon.
    /// In an NSPanel where canBecomeKey is false, both override close().
    override func performClose(_ sender: Any?) {
        NotificationCenter.default.post(
            name: .floatingPanelWantsHide,
            object: self
        )
    }

    override func close() {
        NotificationCenter.default.post(
            name: .floatingPanelWantsHide,
            object: self
        )
    }

    /// Minimize button (yellow) → Dock to screen edge.
    override func performMiniaturize(_ sender: Any?) {
        NotificationCenter.default.post(
            name: .floatingPanelWantsCollapse,
            object: self
        )
    }

    override func miniaturize(_ sender: Any?) {
        NotificationCenter.default.post(
            name: .floatingPanelWantsCollapse,
            object: self
        )
    }
}

extension Notification.Name {
    static let floatingPanelWantsCollapse = Notification.Name("FloatingPanelWantsCollapse")
    static let floatingPanelWantsHide = Notification.Name("FloatingPanelWantsHide")
}
