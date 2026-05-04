import XCTest
@testable import FloatingMacroCore

/// バンドル同梱の seed JSON 群が Preset として decode できることと、
/// アクセシビリティ seed の destructive 操作 (再起動 / シャットダウン /
/// ログアウト) が confirm ガード付きであることを保証する。
///
/// なぜテストにするか:
///   - confirm が外れたまま release されると、視線入力 / Switch Control
///     ユーザーが誤発火で電源を落とすリスクがある。スキーマ変更や JSON
///     編集ミスで confirm が抜け落ちないことを CI 時点で必ず検知する。
final class SeedPresetInstallerTests: XCTestCase {

    func testAllBundledSeedsDecodeSuccessfully() {
        let seeds = SeedPresetInstaller.bundledSeedPresets()
        XCTAssertFalse(seeds.isEmpty,
                       "bundle should ship at least one seed JSON")
        let names = Set(seeds.map { $0.name })
        // 既知の seed が全部読めているかを抜き打ちでチェック。新シードが
        // 追加されてもテストは通る (subset 比較)。
        let expected: Set<String> = ["accessibility", "logic-pro", "midjourney"]
        XCTAssertTrue(expected.isSubset(of: names),
                      "expected seeds \(expected) missing — got \(names)")
    }

    func testAccessibilitySeedHasConfirmGuardsOnDestructiveButtons() throws {
        let seeds = SeedPresetInstaller.bundledSeedPresets()
        guard let preset = seeds.first(where: { $0.name == "accessibility" }) else {
            XCTFail("accessibility seed not found")
            return
        }
        let allButtons = preset.groups.flatMap { $0.buttons }
        let mustConfirm = ["b-a11y-restart", "b-a11y-shutdown", "b-a11y-logout"]
        for id in mustConfirm {
            guard let button = allButtons.first(where: { $0.id == id }) else {
                XCTFail("button '\(id)' not found in accessibility seed")
                continue
            }
            XCTAssertTrue(button.confirm,
                          "'\(id)' must have confirm=true")
            XCTAssertTrue(button.confirmDestructive,
                          "'\(id)' must have confirmDestructive=true (red dialog button)")
            XCTAssertNotNil(button.confirmMessage,
                            "'\(id)' must ship a confirmMessage")
        }
    }

    /// 押し間違えても被害が小さいボタン (画面ロック / スリープ / 強制終了
    /// ダイアログ) は逆に confirm を要求しない: 視線入力ユーザーが頻繁に
    /// 押す想定で、毎回ダイアログを介在させると操作負荷が高すぎる。
    func testAccessibilitySeedHasNoConfirmOnLowImpactButtons() throws {
        let seeds = SeedPresetInstaller.bundledSeedPresets()
        guard let preset = seeds.first(where: { $0.name == "accessibility" }) else {
            XCTFail("accessibility seed not found")
            return
        }
        let allButtons = preset.groups.flatMap { $0.buttons }
        let shouldNotConfirm = ["b-a11y-lock", "b-a11y-sleep",
                                "b-a11y-display-sleep", "b-a11y-force-quit-dialog"]
        for id in shouldNotConfirm {
            guard let button = allButtons.first(where: { $0.id == id }) else {
                XCTFail("button '\(id)' not found in accessibility seed")
                continue
            }
            XCTAssertFalse(button.confirm,
                           "'\(id)' should NOT have confirm (frequent / low-impact)")
        }
    }
}
