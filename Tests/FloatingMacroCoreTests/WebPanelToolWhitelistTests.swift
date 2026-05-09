import XCTest
@testable import FloatingMacroCore

/// Phase 5 (P5-12 / P5-13): Web Panel ツールホワイトリストの検証。
/// 「読み取り + button_press のみ」のセキュリティ境界が崩れていないこと、
/// 破壊的 tool が誤って混入していないことを CI で固定する。
final class WebPanelToolWhitelistTests: XCTestCase {

    // MARK: - 含まれるべき tool

    func testCoreReadOnlyToolsAllowed() {
        XCTAssertTrue(WebPanelToolWhitelist.isAllowed("ping"))
        XCTAssertTrue(WebPanelToolWhitelist.isAllowed("get_state"))
        XCTAssertTrue(WebPanelToolWhitelist.isAllowed("manifest"))
    }

    func testButtonPressIsAllowed() {
        // Web Panel のメイン用途。これが落ちたら UI が成立しない。
        XCTAssertTrue(WebPanelToolWhitelist.isAllowed("button_press"))
    }

    func testPresetSwitchingIsAllowed() {
        XCTAssertTrue(WebPanelToolWhitelist.isAllowed("preset_list"))
        XCTAssertTrue(WebPanelToolWhitelist.isAllowed("preset_current"))
        XCTAssertTrue(WebPanelToolWhitelist.isAllowed("preset_get"))
        XCTAssertTrue(WebPanelToolWhitelist.isAllowed("preset_switch"))
    }

    // MARK: - 含まれてはいけない tool (破壊的 / 構成変更系)

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
        // run_action は任意のキー / コマンドを実行できる強力な tool。
        // Web Panel から呼ばせない。
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

    // MARK: - 全 tool が ToolCatalog に存在する

    func testAllWhitelistedToolsExistInCatalog() {
        for name in WebPanelToolWhitelist.allowed {
            XCTAssertNotNil(ToolCatalog.find(name),
                            "ホワイトリストの '\(name)' が ToolCatalog に存在すること")
        }
    }
}
