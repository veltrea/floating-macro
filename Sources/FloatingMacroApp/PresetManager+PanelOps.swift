import Foundation
import AppKit
import FloatingMacroCore

extension PresetManager {

    /// `window.opacity` も自動同期される（`AppConfig+Panels.withSyncedLegacyFields()`）。
    func setOpacity(_ value: Double) {
        guard let cfg = appConfig, let primaryID = cfg.panels.first?.id else { return }
        let next = cfg.updatingPanelOpacity(id: primaryID, opacity: value)
        appConfig = next
        try? writer.saveAppConfig(next)
    }

    /// Persist panel geometry so the window reopens where the user left it.
    /// Called on applicationWillTerminate and opportunistically after moves.
    /// Phase 3 移行期: プライマリパネル (panels[0]) の frame を更新し、legacy
    /// `window` フィールドも自動同期される。複数パネル時は `updatePanelFrame(id:)`
    /// を使うこと。
    func setPanelFrame(x: Double, y: Double, width: Double, height: Double) {
        guard let cfg = appConfig, let primaryID = cfg.panels.first?.id else { return }
        let next = cfg.updatingPanelFrame(id: primaryID, x: x, y: y, width: width, height: height)
        appConfig = next
        try? writer.saveAppConfig(next)
    }

    // MARK: - Phase 3: per-panel ops

    /// 指定 id のパネルの frame を更新して永続化。
    func updatePanelFrame(id: String, x: Double, y: Double,
                          width: Double, height: Double) {
        guard let cfg = appConfig else { return }
        let next = cfg.updatingPanelFrame(id: id, x: x, y: y, width: width, height: height)
        appConfig = next
        try? writer.saveAppConfig(next)
    }

    /// 指定 id のパネルの透明度を更新して永続化。
    func updatePanelOpacity(id: String, opacity: Double) {
        guard let cfg = appConfig else { return }
        let next = cfg.updatingPanelOpacity(id: id, opacity: opacity)
        appConfig = next
        try? writer.saveAppConfig(next)
    }

    /// 指定 id のパネルの背景色を更新して永続化。nil でシステムデフォルトに戻す。
    func updatePanelBackgroundColor(id: String, hex: String?) {
        guard let cfg = appConfig else { return }
        let next = cfg.updatingPanelBackgroundColor(id: id, hex: hex)
        appConfig = next
        try? writer.saveAppConfig(next)
    }

    /// 指定 id のパネルの可視状態（メニューバー show/hide）を更新。
    func setPanelVisible(id: String, visible: Bool) {
        guard let cfg = appConfig else { return }
        let next = cfg.settingPanelVisible(id: id, visible: visible)
        appConfig = next
        try? writer.saveAppConfig(next)
    }

    /// 指定 id のパネルを縁にドック。
    func dockPanel(id: String, edge: DockEdge) {
        guard let cfg = appConfig else { return }
        let next = cfg.dockingPanel(id: id, edge: edge)
        appConfig = next
        try? writer.saveAppConfig(next)
    }

    /// 指定 id のパネルをドックから展開。
    func undockPanel(id: String) {
        guard let cfg = appConfig else { return }
        let next = cfg.undockingPanel(id: id)
        appConfig = next
        try? writer.saveAppConfig(next)
    }

    /// ドックバーのカスタム位置を保存。
    func updateDockBarPosition(id: String, x: Double, y: Double, edge: DockEdge? = nil) {
        guard let cfg = appConfig else { return }
        let next = cfg.updatingDockBarPosition(id: id, x: x, y: y, edge: edge)
        appConfig = next
        try? writer.saveAppConfig(next)
    }

    /// ドックバーのカスタム位置をクリアし、自動レイアウトに戻す。
    func clearDockBarPosition(id: String) {
        guard let cfg = appConfig else { return }
        let next = cfg.clearingDockBarPosition(id: id)
        appConfig = next
        try? writer.saveAppConfig(next)
    }

    /// 全パネルのドックバーカスタム位置をクリアし、自動レイアウトに戻す。
    func clearAllDockBarPositions() {
        guard let cfg = appConfig else { return }
        let next = cfg.clearingAllDockBarPositions()
        appConfig = next
        try? writer.saveAppConfig(next)
    }

    /// 指定 id のパネルのスクロール位置を更新。AppKit のスクロール通知から
    /// 高頻度 (1 ドラッグで数十〜百回) で呼ばれるため、disk 書き込みは
    /// 350ms デバウンスで集約する。in-memory の `appConfig` は即時反映。
    func updatePanelScrollY(id: String, y: Double) {
        guard let cfg = appConfig else { return }
        let next = cfg.updatingPanelScrollY(id: id, scrollY: y)
        // 値が変わっていなければ何もしない (スクロール停止中の無駄打ち防止)。
        if cfg == next { return }
        appConfig = next

        scrollYSaveDebouncers[id]?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let c = self.appConfig else { return }
            try? self.writer.saveAppConfig(c)
        }
        scrollYSaveDebouncers[id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    /// 新規パネルを追加。生成された id を返す（呼び出し側で NSWindow 生成に使う）。
    @discardableResult
    func addPanel(presetName: String, window: WindowConfig = WindowConfig()) -> String? {
        guard let cfg = appConfig else { return nil }
        let (next, id) = cfg.addingPanel(presetName: presetName, window: window)
        appConfig = next
        try? writer.saveAppConfig(next)
        return id
    }

    /// 指定 id のパネルを削除。最後の 1 件は削除されない（Core 側で拒否）。
    /// 削除に成功した場合 true を返す。
    @discardableResult
    func removePanel(id: String) -> Bool {
        guard let cfg = appConfig else { return false }
        let next = cfg.removingPanel(id: id)
        guard next != cfg else { return false }
        appConfig = next
        try? writer.saveAppConfig(next)
        return true
    }

}
