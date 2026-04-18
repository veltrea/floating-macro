import AppKit

/// パネルを折りたたんだ時に表示する小さなフローティングアイコン。
/// ダブルクリックで `onRestore` を呼び出し、元のパネルに復帰させる。
final class MiniIconPanel: NSPanel {
    var onRestore: (() -> Void)?

    init(near anchor: NSRect) {
        let size: CGFloat = 48
        // アンカー (元パネル) の左上付近に配置
        let origin = NSPoint(
            x: anchor.origin.x,
            y: anchor.origin.y + anchor.size.height - size
        )
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
        // 丸背景
        let bg = NSBezierPath(ovalIn: bounds.insetBy(dx: 2, dy: 2))
        NSColor(white: 0.15, alpha: 0.85).setFill()
        bg.fill()

        // SF Symbol (バンドル依存なし)
        if let sym = NSImage(systemSymbolName: "command.square.fill",
                             accessibilityDescription: nil) {
            let cfg = NSImage.SymbolConfiguration(pointSize: 26, weight: .medium)
            let img = sym.withSymbolConfiguration(cfg) ?? sym
            let size = img.size
            let origin = NSPoint(
                x: bounds.midX - size.width / 2,
                y: bounds.midY - size.height / 2
            )
            img.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 0.9)
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
