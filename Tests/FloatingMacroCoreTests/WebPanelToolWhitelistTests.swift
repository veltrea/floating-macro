import XCTest
@testable import FloatingMacroCore

/// Verification of the web panel tool whitelist.
/// The security boundary of only reading and pressing the button should not be compromised.
/// Fix that a destructive tool is not accidentally mixed in using CI.
final class WebPanelToolWhitelistTests: XCTestCase {

    // MARK: - Included tool

    func testCoreReadOnlyToolsAllowed() {
        XCTAssertTrue(WebPanelToolWhitelist.isAllowed("ping"))
        XCTAssertTrue(WebPanelToolWhitelist.isAllowed("get_state"))
        XCTAssertTrue(WebPanelToolWhitelist.isAllowed("manifest"))
    }

    func testButtonPressIsAllowed() {
        // Main purpose of Web Panel. If this fails, the UI cannot be established.
        XCTAssertTrue(WebPanelToolWhitelist.isAllowed("button_press"))
    }

    func testPresetSwitchingIsAllowed() {
        XCTAssertTrue(WebPanelToolWhitelist.isAllowed("preset_list"))
        XCTAssertTrue(WebPanelToolWhitelist.isAllowed("preset_current"))
        XCTAssertTrue(WebPanelToolWhitelist.isAllowed("preset_get"))
        XCTAssertTrue(WebPanelToolWhitelist.isAllowed("preset_switch"))
    }

    // MARK: - Tool to be excluded (destructive / configuration change type)

    func testMutationToolsAreBlocked() {
        let mutating = [
            "group_add", "group_update", "group_delete",
            "button_add", "button_update", "button_delete",
            "preset_create", "preset_rename", "preset_delete",
            "preset_import", "preset_install_seeds",
            "panel_create", "panel_close",
        ]
        for name in mutating {
            XCTAssertFalse(WebPanelToolWhitelist.isAllowed(name),
                           "破壊的 tool '\(name)' は Web Panel から呼べないはず")
        }
    }

    func testRunActionIsBlocked() {
        // run_action is a powerful tool that can execute any key/command.
        // Do not allow calling from Web Panel.
        XCTAssertFalse(WebPanelToolWhitelist.isAllowed("run_action"))
    }

    func testSettingsAndAIToolsAreBlocked() {
        let blocked = [
            "settings_open", "settings_close",
            "settings_open_sf_picker", "settings_select_button",
            "settings_select_group",
            "ai_integration_open", "ai_integration_close",
        ]
        for name in blocked {
            XCTAssertFalse(WebPanelToolWhitelist.isAllowed(name),
                           "Mac 側 UI 操作 tool '\(name)' は Web Panel から呼べないはず")
        }
    }

    func testUnknownToolsAreBlocked() {
        XCTAssertFalse(WebPanelToolWhitelist.isAllowed(""))
        XCTAssertFalse(WebPanelToolWhitelist.isAllowed("nonexistent_tool"))
        XCTAssertFalse(WebPanelToolWhitelist.isAllowed("BUTTON_PRESS"),
                       "ケース感度を保つ (大文字を許可しない)")
    }

    // MARK: - All tools exist in the ToolCatalog

    func testAllWhitelistedToolsExistInCatalog() {
        for name in WebPanelToolWhitelist.allowed {
            XCTAssertNotNil(ToolCatalog.find(name),
                            "ホワイトリストの '\(name)' が ToolCatalog に存在すること")
        }
    }
}
