import XCTest
@testable import FloatingMacroCore

/// Validate pure functions in the extension of `AppConfig+Panels` (follow-up for P3-1 to P3-2).
final class AppConfigPanelOpsTests: XCTestCase {

    // MARK: - addingPanel

    func testAddingPanelAppendsAndReturnsID() {
        let initial = AppConfig(activePreset: "default", window: WindowConfig())
        // The initial should have one panel entry in the decoder logic
        XCTAssertEqual(initial.panels.count, 1)

        let (after, newID) = initial.addingPanel(
            presetName: "midjourney",
            window: WindowConfig(x: 600, y: 60, width: 320, height: 480)
        )

        XCTAssertEqual(after.panels.count, 2)
        XCTAssertEqual(after.panels[1].id, newID)
        XCTAssertEqual(after.panels[1].presetName, "midjourney")
        XCTAssertEqual(after.panels[1].window.x, 600)
        XCTAssertTrue(after.panels[1].visible)
    }

    func testAddingPanelDoesNotMutateLegacyFieldsWhenNotFirst() {
        // Appending to the end does not move panels[0], so legacy fields remain unchanged.
        let initial = AppConfig(activePreset: "default",
                                window: WindowConfig(x: 100, y: 100))
        let (after, _) = initial.addingPanel(
            presetName: "midjourney",
            window: WindowConfig(x: 600, y: 60)
        )
        XCTAssertEqual(after.activePreset, "default")
        XCTAssertEqual(after.window.x, 100)
        XCTAssertEqual(after.panels[0].window.x, 100)
        XCTAssertEqual(after.panels[1].window.x, 600)
    }

    // MARK: - removingPanel

    func testRemovingPanelRemovesByID() {
        var cfg = AppConfig(activePreset: "default", window: WindowConfig())
        let (cfg1, idA) = cfg.addingPanel(presetName: "alpha")
        let (cfg2, idB) = cfg1.addingPanel(presetName: "beta")
        cfg = cfg2
        XCTAssertEqual(cfg.panels.count, 3)

        let after = cfg.removingPanel(id: idA)
        XCTAssertEqual(after.panels.count, 2)
        XCTAssertFalse(after.panels.contains { $0.id == idA })
        XCTAssertTrue(after.panels.contains { $0.id == idB })
    }

    func testRemovingLastPanelRefuses() {
        // Do not delete the last one (empty is not allowed).
        let cfg = AppConfig(activePreset: "default", window: WindowConfig())
        XCTAssertEqual(cfg.panels.count, 1)
        let lastID = cfg.panels[0].id

        let after = cfg.removingPanel(id: lastID)
        XCTAssertEqual(after.panels.count, 1, "最後の 1 件は削除されないべき")
        XCTAssertEqual(after.panels[0].id, lastID)
    }

    func testRemovingNonexistentPanelIsNoOp() {
        let cfg = AppConfig(activePreset: "default", window: WindowConfig())
        let (cfg2, _) = cfg.addingPanel(presetName: "alpha")

        let after = cfg2.removingPanel(id: "does-not-exist")
        XCTAssertEqual(after.panels.count, 2)
        XCTAssertEqual(after, cfg2)
    }

    func testRemovingFirstPanelSyncsLegacyFieldsToNewFirst() {
        // Removing panels[0] causes panels[1] to shift up, so the legacy field also follows.
        let initial = AppConfig(activePreset: "default",
                                window: WindowConfig(x: 100, y: 100))
        let (cfg2, _) = initial.addingPanel(
            presetName: "midjourney",
            window: WindowConfig(x: 600, y: 60)
        )
        let firstID = cfg2.panels[0].id

        let after = cfg2.removingPanel(id: firstID)
        XCTAssertEqual(after.panels.count, 1)
        XCTAssertEqual(after.panels[0].presetName, "midjourney")
        XCTAssertEqual(after.activePreset, "midjourney")
        XCTAssertEqual(after.window.x, 600)
    }

    // MARK: - updatingPanelFrame / updatingPanelOpacity

    func testUpdatingPanelFrameUpdatesOnlyMatchingPanel() {
        let cfg = AppConfig(activePreset: "default", window: WindowConfig())
        let (cfg2, idB) = cfg.addingPanel(presetName: "beta")
        let firstID = cfg2.panels[0].id

        let after = cfg2.updatingPanelFrame(id: idB, x: 800, y: 200, width: 400, height: 300)
        XCTAssertEqual(after.panels[0].id, firstID)
        XCTAssertEqual(after.panels[0].window.x, 100, "panels[0] は変わらない")
        XCTAssertEqual(after.panels[1].window.x, 800)
        XCTAssertEqual(after.panels[1].window.height, 300)
    }

    func testUpdatingPanelFrameClampsMinimums() {
        let cfg = AppConfig(activePreset: "default", window: WindowConfig())
        let id = cfg.panels[0].id
        let after = cfg.updatingPanelFrame(id: id, x: 0, y: 0, width: 50, height: 30)
        XCTAssertEqual(after.panels[0].window.width, 120)
        XCTAssertEqual(after.panels[0].window.height, 80)
    }

    func testUpdatingFirstPanelFrameSyncsLegacyWindow() {
        let cfg = AppConfig(activePreset: "default", window: WindowConfig())
        let id = cfg.panels[0].id
        let after = cfg.updatingPanelFrame(id: id, x: 250, y: 350, width: 280, height: 420)
        XCTAssertEqual(after.window.x, 250)
        XCTAssertEqual(after.window.y, 350)
        XCTAssertEqual(after.window.width, 280)
        XCTAssertEqual(after.window.height, 420)
    }

    func testUpdatingPanelOpacityClamps() {
        let cfg = AppConfig(activePreset: "default", window: WindowConfig())
        let id = cfg.panels[0].id
        let high = cfg.updatingPanelOpacity(id: id, opacity: 1.5)
        let low  = cfg.updatingPanelOpacity(id: id, opacity: 0.0)
        XCTAssertEqual(high.panels[0].window.opacity, 1.0)
        XCTAssertEqual(low.panels[0].window.opacity, 0.25)
    }

    // MARK: - settingPanelPreset / Visible / docking / undocking

    func testSettingPanelPresetSwitchesAndSyncs() {
        let cfg = AppConfig(activePreset: "default", window: WindowConfig())
        let id = cfg.panels[0].id
        let after = cfg.settingPanelPreset(id: id, presetName: "midjourney")
        XCTAssertEqual(after.panels[0].presetName, "midjourney")
        XCTAssertEqual(after.activePreset, "midjourney", "panels[0] 変更時は legacy も同期")
    }

    func testSettingPanelVisibleTogglesFlag() {
        let cfg = AppConfig(activePreset: "default", window: WindowConfig())
        let id = cfg.panels[0].id
        XCTAssertTrue(cfg.panels[0].visible)
        let hidden = cfg.settingPanelVisible(id: id, visible: false)
        XCTAssertFalse(hidden.panels[0].visible)
    }

    func testDockingPanelSetsEdge() {
        let cfg = AppConfig(activePreset: "default", window: WindowConfig())
        let id = cfg.panels[0].id
        XCTAssertNil(cfg.panels[0].dockedEdge)
        let docked = cfg.dockingPanel(id: id, edge: .right)
        XCTAssertEqual(docked.panels[0].dockedEdge, .right)
    }

    func testUndockingPanelClearsEdge() {
        let cfg = AppConfig(activePreset: "default", window: WindowConfig())
        let id = cfg.panels[0].id
        let docked = cfg.dockingPanel(id: id, edge: .left)
        XCTAssertEqual(docked.panels[0].dockedEdge, .left)
        let undocked = docked.undockingPanel(id: id)
        XCTAssertNil(undocked.panels[0].dockedEdge)
    }

    func testDockingPanelChangesEdge() {
        let cfg = AppConfig(activePreset: "default", window: WindowConfig())
        let id = cfg.panels[0].id
        let docked = cfg.dockingPanel(id: id, edge: .top)
        let moved = docked.dockingPanel(id: id, edge: .bottom)
        XCTAssertEqual(moved.panels[0].dockedEdge, .bottom)
    }

    // MARK: - updatingPanelScrollY

    func testUpdatingPanelScrollYStoresValue() {
        let cfg = AppConfig(activePreset: "default", window: WindowConfig())
        let id = cfg.panels[0].id
        XCTAssertEqual(cfg.panels[0].scrollY, 0, "default")
        let scrolled = cfg.updatingPanelScrollY(id: id, scrollY: 240)
        XCTAssertEqual(scrolled.panels[0].scrollY, 240)
    }

    func testUpdatingPanelScrollYClampsNegative() {
        // Clamp negative values (bounce region) of NSScrollView to 0.
        let cfg = AppConfig(activePreset: "default", window: WindowConfig())
        let id = cfg.panels[0].id
        let clamped = cfg.updatingPanelScrollY(id: id, scrollY: -50)
        XCTAssertEqual(clamped.panels[0].scrollY, 0)
    }

    func testPanelConfigScrollYRoundTrip() throws {
        let panel = PanelConfig(
            id: "panel-with-scroll",
            presetName: "default",
            scrollY: 480
        )
        let data = try JSONEncoder().encode(panel)
        let decoded = try JSONDecoder().decode(PanelConfig.self, from: data)
        XCTAssertEqual(decoded.scrollY, 480)
    }

    func testPanelConfigDecodesLegacyJSONWithoutScrollY() throws {
        // The old JSON without the scrollY field is defaulted to 0.
        let json = #"""
        { "id": "p1", "presetName": "default" }
        """#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(PanelConfig.self, from: json)
        XCTAssertEqual(decoded.scrollY, 0)
    }

    // MARK: - withSyncedLegacyFields

    func testWithSyncedLegacyFieldsCopiesPanelZero() {
        var cfg = AppConfig(activePreset: "default", window: WindowConfig())
        // Create a state identical to the legacy synchronization before by directly rewriting panels[0].
        cfg.panels[0].presetName = "midjourney"
        cfg.panels[0].window.x = 999
        XCTAssertEqual(cfg.activePreset, "default", "同期前は legacy フィールドはそのまま")

        let synced = cfg.withSyncedLegacyFields()
        XCTAssertEqual(synced.activePreset, "midjourney")
        XCTAssertEqual(synced.window.x, 999)
    }
}
