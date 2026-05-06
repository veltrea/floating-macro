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
    /// ドック要求（黄色ボタン経由）が来たとき呼ばれる。引数は対象 panel id。
    private let onCollapseRequested: (String) -> Void
    /// 非表示要求（× ボタン経由）が来たとき呼ばれる。引数は対象 panel id。
    private let onHideRequested: (String) -> Void
    /// ミニアイコンのダブルクリックで呼ばれる。引数は対象 panel id。
    private let onExpandRequested: (String) -> Void
    /// ミニアイコンの右クリックで呼ばれる。
    private let onMiniMenuRequested: (String, NSEvent) -> Void
    /// ドックバーがドラッグで移動された。引数は (panel id, origin)。
    var onDockBarDragged: ((String, NSPoint) -> Void)?

    private var collapseObserver: NSObjectProtocol?
    private var hideObserver: NSObjectProtocol?

    init(contentBuilder: @escaping (PanelConfig) -> NSView,
         onCollapseRequested: @escaping (String) -> Void,
         onHideRequested: @escaping (String) -> Void,
         onExpandRequested: @escaping (String) -> Void,
         onMiniMenuRequested: @escaping (String, NSEvent) -> Void) {
        self.contentBuilder       = contentBuilder
        self.onCollapseRequested  = onCollapseRequested
        self.onHideRequested      = onHideRequested
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
        self.hideObserver = NotificationCenter.default.addObserver(
            forName: .floatingPanelWantsHide,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let self,
                  let window = note.object as? NSWindow,
                  let id = self.panelID(forWindow: window) else { return }
            self.onHideRequested(id)
        }
    }

    deinit {
        if let observer = collapseObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = hideObserver {
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
    func openInitial(from configPanels: [PanelConfig],
                     dockLabelProvider: ((PanelConfig) -> (label: String, iconName: String?))? = nil) {
        for config in configPanels {
            guard entries[config.id] == nil else { continue }
            let entry = makeEntry(for: config)
            entries[config.id] = entry

            if let edge = config.dockedEdge, config.visible {
                let info = dockLabelProvider?(config) ?? (label: config.presetName, iconName: nil)
                let customPos = config.dockBarPosition.map { NSPoint(x: $0.x, y: $0.y) }
                collapseToDock(
                    id: config.id,
                    edge: edge,
                    label: info.label,
                    iconName: info.iconName,
                    customPosition: customPos
                )
            } else if config.visible {
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
        entry.dockBar?.orderOut(nil)
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

    /// パネル / ミニアイコン / ドックバーの状態に応じてトグル。
    func toggle(id: String) {
        guard let entry = entries[id] else { return }
        if entry.panel.isVisible {
            onCollapseRequested(id)
        } else if entry.dockBar?.isVisible == true {
            onExpandRequested(id)
        } else if entry.mini.isVisible {
            onExpandRequested(id)
        } else {
            entry.panel.orderFront(nil)
        }
    }

    // MARK: - Edge dock

    /// パネルを画面端にドックする。
    /// `customPosition` が指定されていれば、ドックバーをその位置に固定し、
    /// ジニーアニメーションの吸い込み先もそこになる。
    func collapseToDock(id: String, edge: DockEdge, label: String, iconName: String?, customPosition: NSPoint? = nil) {
        guard let entry = entries[id] else { return }
        let sourceFrame = entry.panel.frame

        entry.mini.orderOut(nil)
        entries[id]?.dockBar?.orderOut(nil)

        let dockBar = EdgeDockBar(edge: edge, label: label, iconName: iconName)
        dockBar.onExpand = { [weak self] in self?.onExpandRequested(id) }
        dockBar.onShowMenu = { [weak self] event in self?.onMiniMenuRequested(id, event) }
        dockBar.onDragEnd = { [weak self] origin in
            self?.onDockBarDragged?(id, origin)
        }
        entries[id]?.dockBar = dockBar

        if let customPosition {
            dockBar.hasCustomPosition = true
            dockBar.setFrameOrigin(customPosition)
        }
        relayoutDockBars()

        let destFrame = dockBar.frame
        dockBar.alphaValue = 0
        dockBar.orderFront(nil)

        entry.panel.orderOut(nil)
        DockTransitionAnimator.animateSlide(
            from: sourceFrame,
            to: destFrame
        ) { [weak self] in
            guard self?.entries[id]?.dockBar === dockBar else { return }
            dockBar.alphaValue = 1
        }
    }

    /// ドックからパネルを展開する。
    func expandFromDock(id: String) {
        guard let entry = entries[id] else { return }
        let dockFrame = entry.dockBar?.frame ?? .zero
        let panelFrame = entry.panel.frame

        entry.dockBar?.orderOut(nil)
        entries[id]?.dockBar = nil
        relayoutDockBars()

        if dockFrame != .zero {
            entry.panel.alphaValue = 0
            entry.panel.orderFront(nil)
            DockTransitionAnimator.animateSlide(
                from: dockFrame,
                to: panelFrame
            ) { [weak self] in
                self?.entries[id]?.panel.alphaValue = 1
            }
        } else {
            entry.panel.orderFront(nil)
        }
    }

    /// 指定 id のドックバーを返す。
    func dockBar(id: String) -> EdgeDockBar? { entries[id]?.dockBar }

    /// すべての EdgeDockBar の位置を再計算する。カスタム位置のバーはスキップ。
    func relayoutDockBars() {
        guard let screen = NSScreen.main?.visibleFrame else { return }

        var edgeBars: [DockEdge: [(id: String, size: CGSize)]] = [
            .left: [], .right: [], .top: [], .bottom: [],
        ]
        for (id, entry) in entries {
            guard let bar = entry.dockBar else { continue }
            if bar.hasCustomPosition { continue }
            edgeBars[bar.edge]?.append((id: id, size: bar.frame.size))
        }

        for (edge, bars) in edgeBars where !bars.isEmpty {
            let positions = EdgeDockLayout.positions(
                edge: edge,
                screenFrame: screen,
                bars: bars
            )
            for pos in positions {
                entries[pos.id]?.dockBar?.setFrameOrigin(pos.origin)
            }
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

    /// 指定パネルの背景色を反映（永続化は呼び出し元で）。
    func setBackgroundColor(id: String, hex: String?) {
        entries[id]?.panel.applyBackgroundColor(hex: hex)
    }

    /// ドックバーのカスタム位置をクリアし、自動レイアウトに戻す。
    func resetDockBarPosition(id: String) {
        guard let bar = entries[id]?.dockBar else { return }
        bar.hasCustomPosition = false
        relayoutDockBars()
    }

    /// 全ドックバーのカスタム位置をクリアし、自動レイアウトに戻す。
    func resetAllDockBarPositions() {
        for entry in entries.values {
            entry.dockBar?.hasCustomPosition = false
        }
        relayoutDockBars()
    }

    // MARK: - Internals

    private struct Entry {
        let panel: FloatingPanel
        let mini: MiniIconPanel
        var dockBar: EdgeDockBar?
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
        panel.applyBackgroundColor(hex: config.window.backgroundColor)

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
