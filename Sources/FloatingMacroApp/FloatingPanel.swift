import AppKit

/// フォーカスを奪わないフローティングパネル
final class FloatingPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        // フローティング設定
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        isFloatingPanel = true
        hidesOnDeactivate = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true

        // フォーカスを奪わない
        becomesKeyOnlyIfNeeded = true

        // 背景
        isOpaque = false
        backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.95)

        // ドラッグ移動
        isMovableByWindowBackground = true

        // Position/size are owned by config.json — the app loads them on
        // launch and writes them back on terminate via
        // PresetManager.setPanelFrame. We intentionally do NOT use
        // setFrameAutosaveName here, which would otherwise race with the
        // config file for the source of truth.
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// `#RRGGBB` hex → NSColor。nil や不正な文字列ならシステムデフォルトに戻す。
    func applyBackgroundColor(hex: String?) {
        guard let hex, hex.count >= 7, hex.hasPrefix("#"),
              let r = UInt8(hex.dropFirst().prefix(2), radix: 16),
              let g = UInt8(hex.dropFirst(3).prefix(2), radix: 16),
              let b = UInt8(hex.dropFirst(5).prefix(2), radix: 16) else {
            backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.95)
            return
        }
        backgroundColor = NSColor(
            srgbRed: CGFloat(r) / 255,
            green:   CGFloat(g) / 255,
            blue:    CGFloat(b) / 255,
            alpha:   0.95
        )
    }

    /// ×ボタン / ⌘W → ミニアイコンに折りたたむ。
    /// canBecomeKey == false な NSPanel では close() が直接呼ばれるため両方オーバーライド。
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

    /// 黄色ボタン（ミニマイズ）→ 画面端にドックする。
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
