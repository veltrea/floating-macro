import Foundation

/// Phase 3 (v0.12) で導入された複数パネル対応のための、`AppConfig.panels` を
/// 操作する純粋関数群。すべて値型を返し、AppKit / UI に依存しないので
/// `FloatingMacroCore` の単体テストでカバー可能。
///
/// 移行期間中、旧 `activePreset` / `window` フィールドは `panels[0]` と
/// 同期しておく必要がある（古いコードパスがまだ参照しているため）。各 op の
/// 末尾で `withSyncedLegacyFields()` を呼んで自動同期する設計。
extension AppConfig {

    /// 新規パネルを末尾に追加し、生成された panel id とともに新しい AppConfig を返す。
    /// `panels[0]` が新規追加されたパネル（つまり初回追加で空配列だった場合）の
    /// ときは旧 `activePreset` / `window` も同期する。
    public func addingPanel(presetName: String,
                            window: WindowConfig = WindowConfig(),
                            dockedEdge: DockEdge? = nil,
                            visible: Bool = true) -> (AppConfig, String) {
        let panel = PanelConfig(presetName: presetName,
                                window: window,
                                dockedEdge: dockedEdge,
                                visible: visible)
        var copy = self
        copy.panels.append(panel)
        return (copy.withSyncedLegacyFields(), panel.id)
    }

    /// 指定 id のパネルを削除。最後の 1 件は削除拒否（空状態を作らない）し、
    /// 一致する id が無い場合は no-op。
    public func removingPanel(id: String) -> AppConfig {
        guard panels.count > 1 else { return self }
        guard panels.contains(where: { $0.id == id }) else { return self }
        var copy = self
        copy.panels.removeAll { $0.id == id }
        return copy.withSyncedLegacyFields()
    }

    /// 任意のパネルに対する変換を適用。一致する id が無い場合は no-op。
    public func updatingPanel(id: String,
                              _ transform: (PanelConfig) -> PanelConfig) -> AppConfig {
        guard let idx = panels.firstIndex(where: { $0.id == id }) else { return self }
        var copy = self
        copy.panels[idx] = transform(copy.panels[idx])
        return copy.withSyncedLegacyFields()
    }

    /// 指定パネルのウィンドウ位置・サイズを更新。
    public func updatingPanelFrame(id: String,
                                   x: Double, y: Double,
                                   width: Double, height: Double) -> AppConfig {
        return updatingPanel(id: id) { panel in
            var p = panel
            p.window.x = x
            p.window.y = y
            p.window.width = max(120, width)
            p.window.height = max(80, height)
            return p
        }
    }

    /// 指定パネルの透明度を [0.25, 1.0] にクランプして更新。
    public func updatingPanelOpacity(id: String, opacity: Double) -> AppConfig {
        return updatingPanel(id: id) { panel in
            var p = panel
            p.window.opacity = max(0.25, min(1.0, opacity))
            return p
        }
    }

    /// 指定パネルの背景色を更新。nil でシステムデフォルトに戻す。
    public func updatingPanelBackgroundColor(id: String, hex: String?) -> AppConfig {
        return updatingPanel(id: id) { panel in
            var p = panel
            p.window.backgroundColor = hex
            return p
        }
    }

    /// 指定パネルの表示プリセットを切り替え。
    public func settingPanelPreset(id: String, presetName: String) -> AppConfig {
        return updatingPanel(id: id) { panel in
            var p = panel
            p.presetName = presetName
            return p
        }
    }

    /// 指定パネルの可視状態を更新（メニューバーから show/hide するときに使う）。
    public func settingPanelVisible(id: String, visible: Bool) -> AppConfig {
        return updatingPanel(id: id) { panel in
            var p = panel
            p.visible = visible
            return p
        }
    }

    /// パネルを指定した辺にドックする。
    public func dockingPanel(id: String, edge: DockEdge) -> AppConfig {
        return updatingPanel(id: id) { panel in
            var p = panel
            p.dockedEdge = edge
            return p
        }
    }

    /// ドックからパネルを展開する。dockBarPosition は保持し、再ドック時に復元する。
    public func undockingPanel(id: String) -> AppConfig {
        return updatingPanel(id: id) { panel in
            var p = panel
            p.dockedEdge = nil
            return p
        }
    }

    /// ドックバーのカスタム位置を保存する。
    public func updatingDockBarPosition(id: String, x: Double, y: Double) -> AppConfig {
        return updatingPanel(id: id) { panel in
            var p = panel
            p.dockBarPosition = DockBarPosition(x: x, y: y)
            return p
        }
    }

    /// ドックバーのカスタム位置をクリアする。
    public func clearingDockBarPosition(id: String) -> AppConfig {
        return updatingPanel(id: id) { panel in
            var p = panel
            p.dockBarPosition = nil
            return p
        }
    }

    /// 全パネルのドックバーカスタム位置をクリアする。
    public func clearingAllDockBarPositions() -> AppConfig {
        var copy = self
        copy.panels = panels.map { panel in
            var p = panel
            p.dockBarPosition = nil
            return p
        }
        return copy
    }

    /// 指定パネルのスクロール位置 (`scrollY`) を更新。負値は 0 にクランプ。
    /// アプリ再起動後の表示位置復元 (`PanelScrollView`) が読む値。
    public func updatingPanelScrollY(id: String, scrollY: Double) -> AppConfig {
        return updatingPanel(id: id) { panel in
            var p = panel
            p.scrollY = max(0, scrollY)
            return p
        }
    }

    /// `panels[0]` の値を旧 `activePreset` / `window` フィールドにコピーする。
    /// Phase 3 の移行期間中、旧フィールドを参照する既存コードと整合性を保つために
    /// 各 op の末尾で呼ばれる。`panels` が空の場合は no-op（decoder 側で必ず
    /// 1 件以上に正規化されているはずだが、防衛的に空チェックを残す）。
    public func withSyncedLegacyFields() -> AppConfig {
        guard let first = panels.first else { return self }
        var copy = self
        copy.activePreset = first.presetName
        copy.window = first.window
        return copy
    }
}
