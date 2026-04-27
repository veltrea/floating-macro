import AppKit

/// パネルを折りたたんだ時に表示する小さなフローティングアイコン。
/// ダブルクリックで `onRestore` を呼び出し、元のパネルに復帰させる。
final class MiniIconPanel: NSPanel {
    var onRestore: (() -> Void)?

    /// ユーザーがドラッグで動かした最終位置を覚えるための UserDefaults キー
    static let savedOriginKey = "MiniIconPanel.savedOrigin"

    /// 保存済み位置 (前回ユーザーが置いた場所)。無ければ nil
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
        // 保存位置があればそれを優先、無ければアンカー (元パネル) の左上付近
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
        contentView = iconView

        // ドラッグで移動した時に位置を保存
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

    override init(frame: NSRect) {
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let inner = bounds.insetBy(dx: 2, dy: 2)

        // 縦方向グラデ背景: v1 アイコンの dark purple frame と揃える
        // 上: やや明るい紫、下: 深い紫
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

        // 縁: 薄い紫の outline
        let stroke = NSBezierPath(ovalIn: inner.insetBy(dx: 0.5, dy: 0.5))
        NSColor(srgbRed: 0.87, green: 0.72, blue: 1.0, alpha: 0.45).setStroke()
        stroke.lineWidth = 1
        stroke.stroke()

        // SF Symbol を AI accent (#ddb7ff) で描画
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
}
