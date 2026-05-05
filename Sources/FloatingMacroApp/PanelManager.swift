import AppKit
import FloatingMacroCore

/// Phase 3 (P3-3) で導入。複数のフローティングパネル（とそれぞれのミニアイコン）を
/// 永続 id で管理する。AppDelegate はこれを通じて全パネルを操作する。
///
/// **設計ポリシー:**
/// - パネルの内容（NSView / SwiftUI）は AppDelegate が `contentBuilder` クロージャで
///   供給する。PanelManager 自身は SwiftUI / PresetManager に依存しない（AppKit のみ）。
/// - panel id は `PanelConfig.id`（UUID）と一致。`PresetManager.appConfig.panels`
///   が真実の源で、PanelManager は描画中の id を保持するだけ。
/// - ミニアイコンは現状ペアで作成するが、複数パネル時の `MiniIconPanel.savedOrigin`
///   競合は将来課題（panels.count >= 2 の UI を有効化する Phase 3 の後段で対応）。
final class PanelManager {

    /// id → 1 セット（フローティングパネル + ミニアイコン）。
    private var entries: [String: Entry] = [:]

    /// パネル id → コンテンツビュー生成関数。AppDelegate から差し込まれる。
    private let contentBuilder: (PanelConfig) -> NSView
    /// 折りたたみ要求（× ボタン経由）が来たとき呼ばれる。引数は対象 panel id。
    private let onCollapseRequested: (String) -> Void
    /// ミニアイコンのダブルクリックで呼ばれる。引数は対象 panel id。
    private let onExpandRequested: (String) -> Void
    /// ミニアイコンの右クリックで呼ばれる。
    private let onMiniMenuRequested: (String, NSEvent) -> Void

    /// FloatingPanel が `floatingPanelWantsCollapse` 通知を送るので、
    /// それを購読して `object` から panel id を逆引きする。
    private var collapseObserver: NSObjectProtocol?

    init(contentBuilder: @escaping (PanelConfig) -> NSView,
         onCollapseRequested: @escaping (String) -> Void,
         onExpandRequested: @escaping (String) -> Void,
         onMiniMenuRequested: @escaping (String, NSEvent) -> Void) {
        self.contentBuilder       = contentBuilder
        self.onCollapseRequested  = onCollapseRequested
        self.onExpandRequested    = onExpandRequested
        self.onMiniMenuRequested  = onMiniMenuRequested
        self.collapseObserver = NotificationCenter.default.addObserver(
            forName: .floatingPanelWantsCollapse,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let self,
                  let window = note.object as? NSWindow,
                  let id = self.panelID(forWindow: window) else { return }
            self.onCollapseRequested(id)
        }
    }

    deinit {
        if let observer = collapseObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Lookup

    /// 与えられた NSWindow に対応する panel id を返す。
    func panelID(forWindow window: NSWindow) -> String? {
        for (id, entry) in entries where entry.panel === window {
            return id
        }
        return nil
    }

    /// 現在開いている全パネルの id 配列。
    var allPanelIDs: [String] { Array(entries.keys) }

    /// 指定 id のフローティングパネル本体を返す（無ければ nil）。
    func panel(id: String) -> FloatingPanel? { entries[id]?.panel }

    /// 指定 id のミニアイコンパネルを返す（無ければ nil）。
    func miniIcon(id: String) -> MiniIconPanel? { entries[id]?.mini }

    // MARK: - Lifecycle

    /// 設定の panels 配列を読んで visible なものを生成・表示する。
    /// 生成順は配列順。既に同じ id で生成済みの場合はスキップ。
    func openInitial(from configPanels: [PanelConfig]) {
        for config in configPanels {
            guard entries[config.id] == nil else { continue }
            let entry = makeEntry(for: config)
            entries[config.id] = entry
            if config.visible {
                entry.panel.orderFront(nil)
            }
        }
    }

    /// 新規パネル定義を反映して NSWindow を生成・表示。
    /// `PresetManager.addPanel` で追加された後に呼び出す想定。
    func openNew(config: PanelConfig) {
        guard entries[config.id] == nil else { return }
        let entry = makeEntry(for: config)
        entries[config.id] = entry
        entry.panel.orderFront(nil)
    }

    /// 指定 id のパネルとそのミニアイコンを破棄。
    /// `PresetManager.removePanel` 成功後に呼ぶ。
    func close(id: String) {
        guard let entry = entries.removeValue(forKey: id) else { return }
        entry.panel.orderOut(nil)
        entry.mini.orderOut(nil)
    }

    // MARK: - Visibility / collapse

    /// フローティングパネル → ミニアイコン折りたたみ。frame は永続化のため呼び出し
    /// 元（AppDelegate）が PresetManager 経由で書き戻す想定（保存タイミングをここに
    /// 押し込まないことで、テスト時のディスク I/O を切り離せる）。
    func collapseToMini(id: String) {
        guard let entry = entries[id] else { return }
        let f = entry.panel.frame
        let size: CGFloat = 48
        let origin = MiniIconPanel.savedOrigin ?? NSPoint(
            x: f.origin.x,
            y: f.origin.y + f.size.height - size
        )
        entry.mini.setFrameOrigin(origin)
        entry.panel.orderOut(nil)
        entry.mini.orderFront(nil)
    }

    func expandFromMini(id: String) {
        guard let entry = entries[id] else { return }
        entry.mini.orderOut(nil)
        entry.panel.orderFront(nil)
    }

    /// パネル / ミニアイコンの状態に応じて折りたたみ / 展開 / 表示をトグル。
    func toggle(id: String) {
        guard let entry = entries[id] else { return }
        if entry.panel.isVisible {
            onCollapseRequested(id)
        } else if entry.mini.isVisible {
            onExpandRequested(id)
        } else {
            entry.panel.orderFront(nil)
        }
    }

    // MARK: - Frame / opacity

    /// 指定 id のフローティングパネルの現在 frame を返す（無ければ nil）。
    func currentFrame(id: String) -> NSRect? {
        return entries[id]?.panel.frame
    }

    /// 全パネルの現在 frame を `(id, NSRect)` のタプル配列で返す。
    /// 呼び出し元はこれを PresetManager.updatePanelFrame に渡して永続化する。
    func currentFrames() -> [(id: String, frame: NSRect)] {
        return entries.map { ($0.key, $0.value.panel.frame) }
    }

    /// 指定パネルの透明度を反映（永続化は呼び出し元で）。
    func setOpacity(id: String, opacity: Double) {
        entries[id]?.panel.alphaValue = CGFloat(opacity)
    }

    // MARK: - Internals

    private struct Entry {
        let panel: FloatingPanel
        let mini: MiniIconPanel
    }

    private func makeEntry(for config: PanelConfig) -> Entry {
        let frame = NSRect(
            x: config.window.x,
            y: config.window.y,
            width: config.window.width,
            height: config.window.height
        )
        let panel = FloatingPanel(contentRect: frame)
        panel.contentView = NSHostingViewIfNeeded(contentBuilder(config))
        panel.alphaValue = CGFloat(config.window.opacity)

        let mini = MiniIconPanel(near: frame)
        // クロージャは self を弱参照しないと Mini→Manager のレファサイクル化を
        // 避けられない。`weak self` 経由で id-base のディスパッチに乗せ替え。
        let id = config.id
        mini.onRestore = { [weak self] in self?.onExpandRequested(id) }
        mini.onShowMenu = { [weak self] event in
            self?.onMiniMenuRequested(id, event)
        }
        return Entry(panel: panel, mini: mini)
    }
}

/// `contentBuilder` が `NSView` を返す形式に揃えるための薄いヘルパー。
/// SwiftUI 側では `NSHostingView(rootView:)` を使うので素通しで良いが、
/// 仮の AppKit-only View を渡すケースも将来想定して関数化しておく。
@inline(__always)
private func NSHostingViewIfNeeded(_ view: NSView) -> NSView { view }
