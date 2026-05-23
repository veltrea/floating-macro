import AppKit
import FloatingMacroCore

/// The thin bar that appears when a panel is docked to the screen edge.
/// Expand with double-click, move by dragging, display context menu on right-click.
final class EdgeDockBar: NSPanel {
    var onExpand: (() -> Void)?
    var onShowMenu: ((NSEvent) -> Void)?
    var onDragEnd: ((NSPoint) -> Void)?
    /// True if moved to a custom position by drag. Do not overwrite with relayoutDockBars.
    var hasCustomPosition = false

    let edge: DockEdge

    private let label: String
    private let iconName: String?

    init(edge: DockEdge, label: String, iconName: String?) {
        self.edge = edge
        self.label = label
        self.iconName = iconName

        let size = EdgeDockBar.barSize(edge: edge, label: label)
        let frame = NSRect(origin: .zero, size: size)

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
        isMovableByWindowBackground = false
        hasShadow = true

        let barView = EdgeDockBarView(
            frame: NSRect(origin: .zero, size: size),
            edge: edge,
            label: label,
            iconName: iconName
        )
        barView.onDoubleClick = { [weak self] in self?.onExpand?() }
        barView.onRightClick = { [weak self] event in self?.onShowMenu?(event) }
        barView.onDragEnd = { [weak self] origin in
            guard let self else { return }
            self.hasCustomPosition = true
            self.onDragEnd?(origin)
        }
        contentView = barView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    static func barSize(edge: DockEdge, label: String) -> NSSize {
        switch edge {
        case .left, .right:
            let charHeight: CGFloat = 12
            let labelHeight = min(CGFloat(label.count) * charHeight, 200)
            let h = max(80, 16 + 8 + labelHeight + 8)
            return NSSize(width: 28, height: h)
        case .top, .bottom:
            let font = NSFont.systemFont(ofSize: 10, weight: .medium)
            let attrs: [NSAttributedString.Key: Any] = [.font: font]
            let textWidth = (label as NSString).size(withAttributes: attrs).width
            let w = max(80, 16 + 8 + textWidth + 8)
            return NSSize(width: w, height: 26)
        }
    }
}

// MARK: - Bar view

private final class EdgeDockBarView: NSView {
    var onDoubleClick: (() -> Void)?
    var onRightClick: ((NSEvent) -> Void)?
    var onDragEnd: ((NSPoint) -> Void)?

    private let edge: DockEdge
    private let label: String
    private let iconName: String?

    private var dragOrigin: NSPoint?
    private var didDrag = false
    private static let dragThreshold: CGFloat = 4

    init(frame: NSRect, edge: DockEdge, label: String, iconName: String?) {
        self.edge = edge
        self.label = label
        self.iconName = iconName
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)

        if let ctx = NSGraphicsContext.current?.cgContext {
            let colors = [
                NSColor(srgbRed: 0.27, green: 0.18, blue: 0.42, alpha: 0.92).cgColor,
                NSColor(srgbRed: 0.13, green: 0.08, blue: 0.25, alpha: 0.92).cgColor,
            ] as CFArray
            let space = CGColorSpaceCreateDeviceRGB()
            if let grad = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) {
                ctx.saveGState()
                path.addClip()
                ctx.drawLinearGradient(
                    grad,
                    start: CGPoint(x: rect.midX, y: rect.maxY),
                    end: CGPoint(x: rect.midX, y: rect.minY),
                    options: []
                )
                ctx.restoreGState()
            }
        }

        // destiny
        NSColor(srgbRed: 0.87, green: 0.72, blue: 1.0, alpha: 0.35).setStroke()
        let stroke = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        stroke.lineWidth = 1
        stroke.stroke()

        let textColor = NSColor(srgbRed: 0.87, green: 0.72, blue: 1.0, alpha: 1.0)

        switch edge {
        case .left, .right:
            drawVerticalContent(textColor: textColor)
        case .top, .bottom:
            drawHorizontalContent(textColor: textColor)
        }
    }

    private func drawVerticalContent(textColor: NSColor) {
        // icon (top)
        var yOffset = bounds.maxY - 8 - 16
        if let sym = resolveIcon() {
            let cfg = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
            let img = sym.withSymbolConfiguration(cfg) ?? sym
            let tinted = tintImage(img, color: textColor)
            let origin = NSPoint(x: bounds.midX - tinted.size.width / 2, y: yOffset)
            tinted.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1.0)
        }
        yOffset -= 6

        // Label (vertical writing: draw each character)
        let font = NSFont.systemFont(ofSize: 10, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
        for char in label {
            let str = String(char)
            let charSize = (str as NSString).size(withAttributes: attrs)
            let x = bounds.midX - charSize.width / 2
            yOffset -= charSize.height
            guard yOffset >= bounds.minY + 4 else { break }
            (str as NSString).draw(at: NSPoint(x: x, y: yOffset), withAttributes: attrs)
            yOffset -= 1
        }
    }

    private func drawHorizontalContent(textColor: NSColor) {
        var xOffset: CGFloat = 8

        // icon
        if let sym = resolveIcon() {
            let cfg = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
            let img = sym.withSymbolConfiguration(cfg) ?? sym
            let tinted = tintImage(img, color: textColor)
            let y = bounds.midY - tinted.size.height / 2
            tinted.draw(at: NSPoint(x: xOffset, y: y), from: .zero, operation: .sourceOver, fraction: 1.0)
            xOffset += tinted.size.width + 6
        }

        // Label
        let font = NSFont.systemFont(ofSize: 10, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
        let labelSize = (label as NSString).size(withAttributes: attrs)
        let y = bounds.midY - labelSize.height / 2
        (label as NSString).draw(at: NSPoint(x: xOffset, y: y), withAttributes: attrs)
    }

    private func resolveIcon() -> NSImage? {
        if let name = iconName, let sym = NSImage(systemSymbolName: name, accessibilityDescription: nil) {
            return sym
        }
        return NSImage(systemSymbolName: "command", accessibilityDescription: nil)
    }

    private func tintImage(_ image: NSImage, color: NSColor) -> NSImage {
        NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick?()
            return
        }
        dragOrigin = NSEvent.mouseLocation
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let origin = dragOrigin, let win = window else { return }
        let current = NSEvent.mouseLocation
        let dx = current.x - origin.x
        let dy = current.y - origin.y
        if abs(dx) < Self.dragThreshold && abs(dy) < Self.dragThreshold { return }
        didDrag = true
        let frame = win.frame
        let raw = NSPoint(x: frame.origin.x + dx, y: frame.origin.y + dy)
        win.setFrameOrigin(Self.clampedOrigin(raw, size: frame.size))
        dragOrigin = current
    }

    override func mouseUp(with event: NSEvent) {
        if didDrag, let win = window {
            onDragEnd?(win.frame.origin)
        }
        dragOrigin = nil
        didDrag = false
    }

    /// Clamp the origin so that all edges of the bar fit within visibleFrame.
    private static func clampedOrigin(_ origin: NSPoint, size: NSSize) -> NSPoint {
        guard let screen = NSScreen.main?.visibleFrame else { return origin }
        return NSPoint(
            x: max(screen.minX, min(origin.x, screen.maxX - size.width)),
            y: max(screen.minY, min(origin.y, screen.maxY - size.height))
        )
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?(event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        nil
    }
}
