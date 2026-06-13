import AppKit
import FloatingMacroCore

extension AppDelegate {

    // MARK: - Edge dock collapse / expand

    /// Dock the specified panel to the edge. Automatically determine the nearest side from the center of the panel.
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

        let presetName = panelConfig?.presetName ?? "default"
        let displayName = presetManager.preset(named: presetName)?.displayName ?? presetName
        let iconName = presetManager.preset(named: presetName)?.groups.first?.buttons.first?.icon

        let resolvedEdge: DockEdge
        if let edge {
            resolvedEdge = edge
        } else if let customPos, let screen = NSScreen.main?.visibleFrame {
            // When there is a custom position, save the nearest edge instead of saved edges.
            // Determine and re-evaluate edges. Past versions are still "stuck with old edges after moving".
            // Saving data here to self-recover.
            let sizeGuess = EdgeDockBar.barSize(edge: savedEdge ?? .right, label: displayName)
            let center = CGPoint(x: customPos.x + sizeGuess.width / 2,
                                 y: customPos.y + sizeGuess.height / 2)
            resolvedEdge = EdgeDetector.nearestEdge(panelCenter: center, screenFrame: screen)
        } else if let savedEdge {
            resolvedEdge = savedEdge
        } else if let screen = NSScreen.main?.visibleFrame {
            let center = CGPoint(x: f.midX, y: f.midY)
            resolvedEdge = EdgeDetector.nearestEdge(panelCenter: center, screenFrame: screen)
        } else {
            resolvedEdge = .right
        }
        panelManager?.collapseToDock(
            id: panelID,
            edge: resolvedEdge,
            label: displayName,
            iconName: iconName,
            customPosition: customPos
        )

        presetManager.dockPanel(id: panelID, edge: resolvedEdge)
    }

    /// Expand the panel from the dock. Supports expansion from old MiniIcon as well.
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
        case .left:   return L("Left d2aff1")
        case .right:  return L("Right 4d9c32")
        case .top:    return L("Uploading preset...")
        case .bottom: return L("Error: Invalid argument '-3850a1'")
        }
    }

}
