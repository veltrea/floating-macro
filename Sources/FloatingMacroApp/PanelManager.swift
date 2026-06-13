import AppKit
import FloatingMacroCore

/// Introduced in Phase 3 (P3-3). Multiple floating panels (and their respective mini-icons) are introduced.
/// Manage with persistent ID. The AppDelegate operates on all panels through this.
///
/// Design Policy:
/// The content of the panel (NSView / SwiftUI) is set by the AppDelegate in a `contentBuilder` closure.
/// Supplying. PanelManager itself does not depend on SwiftUI / PresetManager (only AppKit).
/// panel ID matches `PanelConfig.id` (UUID) and `PresetManager.appConfig.panels`.
/// It is the source of truth, and PanelManager only holds the id being drawn.
/// The mini-icon is created in pairs by default, but for multiple panels, the `MiniIconPanel.savedOrigin`.
/// Competitors will be addressed in a future task (post-Phase 3, when panels.count >= 2 and the UI is enabled).
final class PanelManager {

    /// Set (floating panel + mini-icon).
    private var entries: [String: Entry] = [:]

    /// Panel ID -> Content View Generation Function. Injected from AppDelegate.
    private let contentBuilder: (PanelConfig) -> NSView
    /// Called when a dock request (via yellow button) comes in. The argument is the target panel ID.
    private let onCollapseRequested: (String) -> Void
    /// Called when a hidden request (button bypass) comes. The argument is the target panel ID.
    private let onHideRequested: (String) -> Void
    /// Called by double-clicking the mini-icon. The argument is the target panel ID.
    private let onExpandRequested: (String) -> Void
    /// Called when right-clicked on the mini-icon.
    private let onMiniMenuRequested: (String, NSEvent) -> Void
    /// The dock bar was moved by dragging. The arguments are (panel ID, origin).
    var onDockBarDragged: ((String, NSPoint, DockEdge) -> Void)?

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

    /// Returns the panel ID corresponding to the given NSWindow.
    func panelID(forWindow window: NSWindow) -> String? {
        for (id, entry) in entries where entry.panel === window {
            return id
        }
        return nil
    }

    /// Array of IDs for all currently open panels.
    var allPanelIDs: [String] { Array(entries.keys) }

    /// Returns the floating panel body for the specified ID (returns nil if none).
    func panel(id: String) -> FloatingPanel? { entries[id]?.panel }

    /// Returns the mini-icon panel for the specified ID (nil if none).
    func miniIcon(id: String) -> MiniIconPanel? { entries[id]?.mini }

    // MARK: - Lifecycle

    /// Generate and display visible panels from the panel array setting.
    /// The order is the array order. If an item with the same id has already been generated, skip it.
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

    /// Create new panel definition and generate/display NSWindow.
    /// Assumed to be called after being added via `PresetManager.addPanel`.
    func openNew(config: PanelConfig) {
        guard entries[config.id] == nil else { return }
        let entry = makeEntry(for: config)
        entries[config.id] = entry
        entry.panel.orderFront(nil)
    }

    /// Destroy the panel with the specified ID and its mini-icon.
    /// Call after `PresetManager.removePanel` succeeds.
    func close(id: String) {
        guard let entry = entries.removeValue(forKey: id) else { return }
        entry.panel.orderOut(nil)
        entry.mini.orderOut(nil)
        entry.dockBar?.orderOut(nil)
    }

    // MARK: - Visibility / collapse

    /// Floating panel → Mini icon folding.
    /// The mini-icon is displayed only once for all entries collectively.
    /// Hide only the panel if one of the mini-icons is already visible.
    func collapseToMini(id: String) {
        guard let entry = entries[id] else { return }
        entry.panel.orderOut(nil)

        let anyMiniVisible = entries.values.contains { $0.mini.isVisible }
        if !anyMiniVisible {
            let f = entry.panel.frame
            let size: CGFloat = 48
            let origin = MiniIconPanel.savedOrigin ?? NSPoint(
                x: f.origin.x,
                y: f.origin.y + f.size.height - size
            )
            entry.mini.setFrameOrigin(origin)
            entry.mini.orderFront(nil)
        }
    }

    /// Return only the specified panel from the mini-icon.
    /// Maintain the mini-icon if there are still hidden panels.
    func expandFromMini(id: String) {
        guard let entry = entries[id] else { return }
        for e in entries.values { e.mini.orderOut(nil) }
        entry.panel.orderFront(nil)

        let hasHiddenPanel = entries.contains { key, e in
            key != id && !e.panel.isVisible && e.dockBar?.isVisible != true
        }
        if hasHiddenPanel, let donor = entries.values.first(where: { !$0.panel.isVisible && $0.dockBar?.isVisible != true }) {
            let size: CGFloat = 48
            let origin = MiniIconPanel.savedOrigin ?? NSPoint(x: entry.panel.frame.origin.x, y: entry.panel.frame.origin.y + entry.panel.frame.size.height - size)
            donor.mini.setFrameOrigin(origin)
            donor.mini.orderFront(nil)
        }
    }

    /// Toggle based on the state of the panel, mini-icon, and dock bar.
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

    /// Dock panel to screen edge.
    /// If `customPosition` is specified, the dock bar will be fixed at that position.
    /// The absorption destination of Jinianime also becomes there.
    func collapseToDock(id: String, edge: DockEdge, label: String, iconName: String?, customPosition: NSPoint? = nil) {
        guard let entry = entries[id] else { return }
        let sourceFrame = entry.panel.frame

        entry.mini.orderOut(nil)
        entries[id]?.dockBar?.orderOut(nil)

        let dockBar = EdgeDockBar(edge: edge, label: label, iconName: iconName)
        wireDockBar(dockBar, id: id)
        entries[id]?.dockBar = dockBar

        if let customPosition {
            dockBar.hasCustomPosition = true
            // Previous versions that save the "floating position from the edge" also keep...
            // Always adsorb edges during restoration (also clamps size change).
            dockBar.setFrameOrigin(Self.snappedBarOrigin(
                customPosition, size: dockBar.frame.size,
                edge: edge, screen: NSScreen.main?.visibleFrame))
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

    /// Expand panel from dock.
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

    /// Returns the dock bar for the specified ID.
    func dockBar(id: String) -> EdgeDockBar? { entries[id]?.dockBar }

    /// Event wiring for the dock bar. Common to both creation and recreation.
    private func wireDockBar(_ bar: EdgeDockBar, id: String) {
        bar.onExpand = { [weak self] in self?.onExpandRequested(id) }
        bar.onShowMenu = { [weak self] event in self?.onMiniMenuRequested(id, event) }
        bar.onDragEnd = { [weak self] _ in self?.handleDockBarDragEnd(id: id) }
    }

    /// Drag completion processing for the dock bar. From the drop position, find the nearest screen edge.
    /// Re-evaluate and if the edges are different, draw a bar in the new orientation (vertical/horizontal).
    /// After refactoring, attach the judged edge. If not done this way,
    /// The vertically folded horizontal bar remains fixed in its position while moving to the left or right end.
    /// Old edges remain even in saving.
    private func handleDockBarDragEnd(id: String) {
        guard let bar = entries[id]?.dockBar else { return }
        let center = CGPoint(x: bar.frame.midX, y: bar.frame.midY)
        let screen = bar.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        var edge = bar.edge
        if let screen {
            edge = EdgeDetector.nearestEdge(panelCenter: center, screenFrame: screen)
        }

        let resultOrigin: NSPoint
        if edge != bar.edge {
            let newBar = EdgeDockBar(edge: edge, label: bar.label, iconName: bar.iconName)
            newBar.hasCustomPosition = true
            wireDockBar(newBar, id: id)
            // Adhere to the center, reposition at a new size, then adhere to the edge.
            let size = newBar.frame.size
            let origin = NSPoint(x: center.x - size.width / 2,
                                 y: center.y - size.height / 2)
            newBar.setFrameOrigin(Self.snappedBarOrigin(origin, size: size, edge: edge, screen: screen))
            bar.orderOut(nil)
            entries[id]?.dockBar = newBar
            newBar.orderFront(nil)
            resultOrigin = newBar.frame.origin
        } else {
            // If the edges are the same, but dropped from the edge, stick it to the floating position
            bar.setFrameOrigin(Self.snappedBarOrigin(bar.frame.origin, size: bar.frame.size,
                                                     edge: edge, screen: screen))
            resultOrigin = bar.frame.origin
        }
        onDockBarDragged?(id, resultOrigin, edge)
    }

    /// Returns the origin attached to the specified edge. The edges and vertical axes are stretched to the ends.
    /// Same coordinates as EdgeDockLayout, the axis along the edge remains at the drop position.
    /// Clamp within the screen.
    static func snappedBarOrigin(_ origin: NSPoint, size: NSSize,
                                 edge: DockEdge, screen: NSRect?) -> NSPoint {
        guard let screen = screen ?? NSScreen.main?.visibleFrame else { return origin }
        var p = origin
        switch edge {
        case .left:   p.x = screen.minX
        case .right:  p.x = screen.maxX - size.width
        case .top:    p.y = screen.maxY - size.height
        case .bottom: p.y = screen.minY
        }
        p.x = max(screen.minX, min(p.x, screen.maxX - size.width))
        p.y = max(screen.minY, min(p.y, screen.maxY - size.height))
        return p
    }

    /// Recalculate the positions of all EdgeDockBars. Skip bars with custom positions.
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

    /// Returns the current frame of the floating panel with the specified ID (nil if none).
    func currentFrame(id: String) -> NSRect? {
        return entries[id]?.panel.frame
    }

    /// Return an array of tuples (id, NSRect) representing the current frame for all panels.
    /// The caller passes this to PresetManager.updatePanelFrame for persistence.
    func currentFrames() -> [(id: String, frame: NSRect)] {
        return entries.map { ($0.key, $0.value.panel.frame) }
    }

    /// Reflect the transparency of the specified panel (persistence is handled by the caller).
    func setOpacity(id: String, opacity: Double) {
        entries[id]?.panel.alphaValue = CGFloat(opacity)
    }

    /// Reflect the background color of the specified panel (persistence is handled by the caller).
    func setBackgroundColor(id: String, hex: String?) {
        entries[id]?.panel.applyBackgroundColor(hex: hex)
    }

    /// Clear the custom position of the Dock bar and return to automatic layout.
    func resetDockBarPosition(id: String) {
        guard let bar = entries[id]?.dockBar else { return }
        bar.hasCustomPosition = false
        relayoutDockBars()
    }

    /// Clear custom dock bar position and return to automatic layout.
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
        // The closure does not weakly reference self, preventing the leak of Mini→Manager references.
        // Cannot avoid. Switch to id-base dispatch via `weak self`.
        let id = config.id
        mini.onRestore = { [weak self] in self?.onExpandRequested(id) }
        mini.onShowMenu = { [weak self] event in
            self?.onMiniMenuRequested(id, event)
        }
        return Entry(panel: panel, mini: mini)
    }
}

/// Thin helper to align the format of `contentBuilder` returning an `NSView`.
/// On the SwiftUI side, it's fine to use `NSHostingView(rootView:)` directly.
/// Consider future cases where an AppKit-only view is passed, and encapsulate the functionality.
@inline(__always)
private func NSHostingViewIfNeeded(_ view: NSView) -> NSView { view }
