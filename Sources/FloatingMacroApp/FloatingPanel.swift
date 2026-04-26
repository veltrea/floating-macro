import AppKit

/// フォーカスを奪わないフローティングパネル
final class FloatingPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .titled, .closable, .resizable, .fullSizeContentView],
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

    /// ×ボタン / ⌘W → パネルを隠してミニアイコンに折りたたむ。
    /// 実際の close ではなく通知を飛ばし、AppDelegate が処理する。
    ///
    /// canBecomeKey == false な NSPanel では、×ボタンが performClose ではなく
    /// close() を直接呼ぶため、両方をオーバーライドする必要がある。
    override func performClose(_ sender: Any?) {
        NotificationCenter.default.post(
            name: .floatingPanelWantsCollapse,
            object: self
        )
    }

    override func close() {
        NotificationCenter.default.post(
            name: .floatingPanelWantsCollapse,
            object: self
        )
    }
}

extension Notification.Name {
    static let floatingPanelWantsCollapse = Notification.Name("FloatingPanelWantsCollapse")
}
