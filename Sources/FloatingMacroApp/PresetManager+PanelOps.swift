import Foundation
import AppKit
import FloatingMacroCore

extension PresetManager {

    /// The window's opacity is also automatically synchronized (in `AppConfig+Panels.withSyncedLegacyFields()`).
    func setOpacity(_ value: Double) {
        guard let cfg = appConfig, let primaryID = cfg.panels.first?.id else { return }
        let next = cfg.updatingPanelOpacity(id: primaryID, opacity: value)
        appConfig = next
        try? writer.saveAppConfig(next)
    }

    /// Persist panel geometry so the window reopens where the user left it.
    /// Called on applicationWillTerminate and opportunistically after moves.
    /// Update the frame of primary panel (panels[0]), legacy
    /// The window field is also automatically synchronized. For multiple panels, updatePanelFrame(id:) is used.
    /// Using it.
    func setPanelFrame(x: Double, y: Double, width: Double, height: Double) {
        guard let cfg = appConfig, let primaryID = cfg.panels.first?.id else { return }
        let next = cfg.updatingPanelFrame(id: primaryID, x: x, y: y, width: width, height: height)
        appConfig = next
        try? writer.saveAppConfig(next)
    }

    // MARK: - Phase 3: per-panel ops

    /// Update the frame of the specified panel and persist it.
    func updatePanelFrame(id: String, x: Double, y: Double,
                          width: Double, height: Double) {
        guard let cfg = appConfig else { return }
        let next = cfg.updatingPanelFrame(id: id, x: x, y: y, width: width, height: height)
        appConfig = next
        try? writer.saveAppConfig(next)
    }

    /// Update the transparency of the specified panel and persist it.
    func updatePanelOpacity(id: String, opacity: Double) {
        guard let cfg = appConfig else { return }
        let next = cfg.updatingPanelOpacity(id: id, opacity: opacity)
        appConfig = next
        try? writer.saveAppConfig(next)
    }

    /// Update the background color of the panel with the specified ID and persist it. Set to nil for system default.
    func updatePanelBackgroundColor(id: String, hex: String?) {
        guard let cfg = appConfig else { return }
        let next = cfg.updatingPanelBackgroundColor(id: id, hex: hex)
        appConfig = next
        try? writer.saveAppConfig(next)
    }

    /// Update the visibility state of a specified panel (menu bar show/hide).
    func setPanelVisible(id: String, visible: Bool) {
        guard let cfg = appConfig else { return }
        let next = cfg.settingPanelVisible(id: id, visible: visible)
        appConfig = next
        try? writer.saveAppConfig(next)
    }

    /// Dock panel with specified ID on edge.
    func dockPanel(id: String, edge: DockEdge) {
        guard let cfg = appConfig else { return }
        let next = cfg.dockingPanel(id: id, edge: edge)
        appConfig = next
        try? writer.saveAppConfig(next)
    }

    /// Expand panel with specified ID from the dock.
    func undockPanel(id: String) {
        guard let cfg = appConfig else { return }
        let next = cfg.undockingPanel(id: id)
        appConfig = next
        try? writer.saveAppConfig(next)
    }

    /// Save custom position of Dock bar.
    func updateDockBarPosition(id: String, x: Double, y: Double, edge: DockEdge? = nil) {
        guard let cfg = appConfig else { return }
        let next = cfg.updatingDockBarPosition(id: id, x: x, y: y, edge: edge)
        appConfig = next
        try? writer.saveAppConfig(next)
    }

    /// Clear the custom position of the Dock bar and return to automatic layout.
    func clearDockBarPosition(id: String) {
        guard let cfg = appConfig else { return }
        let next = cfg.clearingDockBarPosition(id: id)
        appConfig = next
        try? writer.saveAppConfig(next)
    }

    /// Clear custom dock bar position for all panels and revert to automatic layout.
    func clearAllDockBarPositions() {
        guard let cfg = appConfig else { return }
        let next = cfg.clearingAllDockBarPositions()
        appConfig = next
        try? writer.saveAppConfig(next)
    }

    /// Update the scroll position of a panel with a specified ID from AppKit scroll notifications.
    /// High frequency (called tens to hundreds of times with one drag), so disk writing is
    /// Debounce aggregation for 350ms. In-memory `appConfig` reflects immediately.
    func updatePanelScrollY(id: String, y: Double) {
        guard let cfg = appConfig else { return }
        let next = cfg.updatingPanelScrollY(id: id, scrollY: y)
        // Do nothing if the value hasn't changed (preventing unnecessary typing during scroll stop).
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

    /// Add a new panel. Returns the generated ID (used by the caller for creating an NSWindow).
    @discardableResult
    func addPanel(presetName: String, window: WindowConfig = WindowConfig()) -> String? {
        guard let cfg = appConfig else { return nil }
        let (next, id) = cfg.addingPanel(presetName: presetName, window: window)
        appConfig = next
        try? writer.saveAppConfig(next)
        return id
    }

    /// Delete the panel with the specified ID. The last one is not deleted (rejected by Core).
    /// Returns true if deletion was successful.
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
