import Foundation

/// Introduced for multi-panel support in Phase 3 (v0.12), `AppConfig.panels`.
/// Pure functions that operate. All return value types and do not depend on AppKit/UI.
/// Coverable by unit tests in `FloatingMacroCore`.
///
/// During the transition period, the old `activePreset` / `window` fields are equivalent to `panels[0]`.
/// Synchronize if necessary (because old code paths still reference). Each op of
/// Design to call `withSyncedLegacyFields()` at the end for automatic synchronization.
extension AppConfig {

    /// Add a new panel to the end and return a new AppConfig with the generated panel ID.
    /// the newly added panel (i.e., the first addition when the array is initially empty) of `panels[0]`
    /// When the old activePreset / window also synchronizes.
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

    /// Delete the panel with the specified ID. The last one is rejected from deletion (to avoid creating an empty state).
    /// If there are no matching IDs, do nothing.
    public func removingPanel(id: String) -> AppConfig {
        guard panels.count > 1 else { return self }
        guard panels.contains(where: { $0.id == id }) else { return self }
        var copy = self
        copy.panels.removeAll { $0.id == id }
        return copy.withSyncedLegacyFields()
    }

    /// Apply conversion to any panel. If there is no matching id, it's a no-op.
    public func updatingPanel(id: String,
                              _ transform: (PanelConfig) -> PanelConfig) -> AppConfig {
        guard let idx = panels.firstIndex(where: { $0.id == id }) else { return self }
        var copy = self
        copy.panels[idx] = transform(copy.panels[idx])
        return copy.withSyncedLegacyFields()
    }

    /// Update the window position and size of the specified panel.
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

    /// Clamp the transparency of the specified panel to [0.25, 1.0] and update.
    public func updatingPanelOpacity(id: String, opacity: Double) -> AppConfig {
        return updatingPanel(id: id) { panel in
            var p = panel
            p.window.opacity = max(0.25, min(1.0, opacity))
            return p
        }
    }

    /// Update the background color of the specified panel. Set to nil for system default.
    public func updatingPanelBackgroundColor(id: String, hex: String?) -> AppConfig {
        return updatingPanel(id: id) { panel in
            var p = panel
            p.window.backgroundColor = hex
            return p
        }
    }

    /// Switch display preset for specified panel.
    public func settingPanelPreset(id: String, presetName: String) -> AppConfig {
        return updatingPanel(id: id) { panel in
            var p = panel
            p.presetName = presetName
            return p
        }
    }

    /// Update the visibility state of the designated panel (used when showing/hiding from the menu bar).
    public func settingPanelVisible(id: String, visible: Bool) -> AppConfig {
        return updatingPanel(id: id) { panel in
            var p = panel
            p.visible = visible
            return p
        }
    }

    /// Dock panel to specified edge.
    public func dockingPanel(id: String, edge: DockEdge) -> AppConfig {
        return updatingPanel(id: id) { panel in
            var p = panel
            p.dockedEdge = edge
            return p
        }
    }

    /// Expand the panel from the dock. Preserve dockBarPosition and restore it when redocked.
    public func undockingPanel(id: String) -> AppConfig {
        return updatingPanel(id: id) { panel in
            var p = panel
            p.dockedEdge = nil
            return p
        }
    }

    /// Save custom position of Dock bar.
    public func updatingDockBarPosition(id: String, x: Double, y: Double, edge: DockEdge? = nil) -> AppConfig {
        return updatingPanel(id: id) { panel in
            var p = panel
            p.dockBarPosition = DockBarPosition(x: x, y: y, edge: edge ?? p.dockedEdge)
            return p
        }
    }

    /// Clear the custom position of the Dock bar.
    public func clearingDockBarPosition(id: String) -> AppConfig {
        return updatingPanel(id: id) { panel in
            var p = panel
            p.dockBarPosition = nil
            return p
        }
    }

    /// Clear the custom position of all panels in the dock bar.
    public func clearingAllDockBarPositions() -> AppConfig {
        var copy = self
        copy.panels = panels.map { panel in
            var p = panel
            p.dockBarPosition = nil
            return p
        }
        return copy
    }

    /// Update the scroll position of the specified panel (`scrollY`). Clamp negative values to 0.
    /// Restored display position (after app restart) for `PanelScrollView`.
    public func updatingPanelScrollY(id: String, scrollY: Double) -> AppConfig {
        return updatingPanel(id: id) { panel in
            var p = panel
            p.scrollY = max(0, scrollY)
            return p
        }
    }

    /// Copy the value of `panels[0]` to the old `activePreset` / `window` field.
    /// During the transition period of Phase 3, to maintain compatibility with existing code that references old fields.
    /// Each op is called at the end. If `panels` is empty, it's a no-op (always on the decoder side).
    /// Should be normalized to more than one, but leave defensive null checks).
    public func withSyncedLegacyFields() -> AppConfig {
        guard let first = panels.first else { return self }
        var copy = self
        copy.activePreset = first.presetName
        copy.window = first.window
        return copy
    }
}
