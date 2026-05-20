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
    ///
    /// カスタム背景色が設定されている場合、背景の明度に応じて
    /// ウィンドウの appearance を `.aqua`（ライト）/ `.darkAqua`（ダーク）に
    /// 強制し、SwiftUI の `Color.primary` / `.secondary` がテキスト色として
    /// 読める状態を保つ。カスタム背景色なし（= システムデフォルト）のときは
    /// appearance を nil に戻してシステム追従する。
    func applyBackgroundColor(hex: String?) {
        guard let hex, hex.count >= 7, hex.hasPrefix("#"),
              let r = UInt8(hex.dropFirst().prefix(2), radix: 16),
              let g = UInt8(hex.dropFirst(3).prefix(2), radix: 16),
              let b = UInt8(hex.dropFirst(5).prefix(2), radix: 16) else {
            backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.95)
            appearance = nil   // システム追従に戻す
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

        // sRGB 相対輝度 (ITU-R BT.709) で明暗を判定
        let luminance = 0.2126 * rf + 0.7152 * gf + 0.0722 * bf
        appearance = NSAppearance(named: luminance > 0.5 ? .aqua : .darkAqua)
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
