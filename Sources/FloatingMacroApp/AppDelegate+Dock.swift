import AppKit
import FloatingMacroCore

extension AppDelegate {

    // MARK: - Edge dock collapse / expand

    /// 指定 id のパネルを縁にドックする。パネル中心から最寄りの辺を自動判定。
    func collapseToDock(panelID: String, edge: DockEdge? = nil) {
        guard let p = panelManager?.panel(id: panelID) else { return }
        let f = p.frame
        presetManager.updatePanelFrame(
            id: panelID,
            x: Double(f.origin.x),
            y: Double(f.origin.y),
            width: Double(f.size.width),
            height: Double(f.size.height)
        )
        let panelConfig = presetManager.appConfig?.panels.first(where: { $0.id == panelID })
        let savedEdge = panelConfig?.dockBarPosition?.edge
        let customPos = panelConfig?.dockBarPosition.map { NSPoint(x: $0.x, y: $0.y) }

        let resolvedEdge: DockEdge
        if let edge {
            resolvedEdge = edge
        } else if let savedEdge {
            resolvedEdge = savedEdge
        } else if let screen = NSScreen.main?.visibleFrame {
            let center = CGPoint(x: f.midX, y: f.midY)
            resolvedEdge = EdgeDetector.nearestEdge(panelCenter: center, screenFrame: screen)
        } else {
            resolvedEdge = .right
        }

        let presetName = panelConfig?.presetName ?? "default"
        let displayName = presetManager.preset(named: presetName)?.displayName ?? presetName
        let iconName = presetManager.preset(named: presetName)?.groups.first?.buttons.first?.icon
        panelManager?.collapseToDock(
            id: panelID,
            edge: resolvedEdge,
            label: displayName,
            iconName: iconName,
            customPosition: customPos
        )

        presetManager.dockPanel(id: panelID, edge: resolvedEdge)
    }

    /// ドックからパネルを展開する。旧 MiniIcon からの展開にも対応。
    func expandFromDock(panelID: String) {
        panelManager?.expandFromDock(id: panelID)
        panelManager?.expandFromMini(id: panelID)
        presetManager.undockPanel(id: panelID)
    }

    // MARK: - Mini icon

    func collapseToMiniIcon(panelID: String) {
        panelManager?.collapseToMini(id: panelID)
    }

    func expandFromMiniIcon(panelID: String) {
        panelManager?.expandFromMini(id: panelID)
    }

    func hidePanel(panelID: String) {
        panelManager?.panel(id: panelID)?.orderOut(nil)
    }

    func edgeLabel(_ edge: DockEdge) -> String {
        switch edge {
        case .left:   return L("左_d2aff1")
        case .right:  return L("右_4d9c32")
        case .top:    return L("上_af767b")
        case .bottom: return L("下_3850a1")
        }
    }

}
