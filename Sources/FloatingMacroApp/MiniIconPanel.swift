import AppKit

/// Floating icon displayed when folding the panel.
/// Call `onRestore` with a double-click, returning to the original panel.
final class MiniIconPanel: NSPanel {
    var onRestore: (() -> Void)?
    var onShowMenu: ((NSEvent) -> Void)?

    /// finalUserLocationUserDefaultsKey
    static let savedOriginKey = "MiniIconPanel.savedOrigin"

    /// Saved position (last place user placed). Nil if none.
    static var savedOrigin: NSPoint? {
        get {
            guard let str = UserDefaults.standard.string(forKey: savedOriginKey) else { return nil }
            return NSPointFromString(str) == .zero ? nil : NSPointFromString(str)
        }
        set {
            if let v = newValue {
                UserDefaults.standard.set(NSStringFromPoint(v), forKey: savedOriginKey)
            } else {
                UserDefaults.standard.removeObject(forKey: savedOriginKey)
            }
        }
    }

    init(near anchor: NSRect) {
        let size: CGFloat = 48
        // If there is a saved position, prioritize that; otherwise, near the top-left of the anchor (original panel).
        let origin: NSPoint
        if let saved = MiniIconPanel.savedOrigin {
            origin = saved
        } else {
            origin = NSPoint(
                x: anchor.origin.x,
                y: anchor.origin.y + anchor.size.height - size
            )
        }
        let frame = NSRect(origin: origin, size: NSSize(width: size, height: size))

        super.init(
            contentRect: frame,
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        isFloatingPanel = true
        hidesOnDeactivate = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        becomesKeyOnlyIfNeeded = true
        isOpaque = false
        backgroundColor = .clear
        isMovableByWindowBackground = true
        hasShadow = true

        let iconView = MiniIconView(frame: NSRect(origin: .zero, size: frame.size))
        iconView.onDoubleClick = { [weak self] in
            self?.onRestore?()
        }
        iconView.onRightClick = { [weak self] event in
            self?.onShowMenu?(event)
        }
        contentView = iconView

        // Save position when moved by drag-and-drop
        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: self,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            MiniIconPanel.savedOrigin = self.frame.origin
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Icon view with double-click detection

private final class MiniIconView: NSView {
    var onDoubleClick: (() -> Void)?
    var onRightClick: ((NSEvent) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let inner = bounds.insetBy(dx: 2, dy: 2)

        // Vertical gradient background: Align with dark purple frame of v1 icon.
        // Upper: Slightly brighter purple, lower: Deep purple
        if let ctx = NSGraphicsContext.current?.cgContext {
            let colors = [
                NSColor(srgbRed: 0.27, green: 0.18, blue: 0.42, alpha: 0.95).cgColor,
                NSColor(srgbRed: 0.13, green: 0.08, blue: 0.25, alpha: 0.95).cgColor,
            ] as CFArray
            let space = CGColorSpaceCreateDeviceRGB()
            if let grad = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) {
                ctx.saveGState()
                NSBezierPath(ovalIn: inner).addClip()
                ctx.drawLinearGradient(
                    grad,
                    start: CGPoint(x: inner.midX, y: inner.maxY),
                    end: CGPoint(x: inner.midX, y: inner.minY),
                    options: []
                )
                ctx.restoreGState()
            }
        }

        // Outline: Thin purple
        let stroke = NSBezierPath(ovalIn: inner.insetBy(dx: 0.5, dy: 0.5))
        NSColor(srgbRed: 0.87, green: 0.72, blue: 1.0, alpha: 0.45).setStroke()
        stroke.lineWidth = 1
        stroke.stroke()

        // Draw SF Symbol with AI accent (#ddb7ff).
        if let sym = NSImage(systemSymbolName: "command",
                             accessibilityDescription: nil) {
            let cfg = NSImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
            let img = sym.withSymbolConfiguration(cfg) ?? sym
            let tinted = NSImage(size: img.size, flipped: false) { rect in
                img.draw(in: rect)
                NSColor(srgbRed: 0.87, green: 0.72, blue: 1.0, alpha: 1.0).set()
                rect.fill(using: .sourceAtop)
                return true
            }
            let size = tinted.size
            let origin = NSPoint(
                x: bounds.midX - size.width / 2,
                y: bounds.midY - size.height / 2
            )
            tinted.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1.0)
        }
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick?()
        } else {
            super.mouseDown(with: event)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?(event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        return nil
    }
}
