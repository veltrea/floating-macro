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

    /// v0.11 で追加した「MidJourney プロンプトギャラリー」 seed が、
    /// Phase 2 の表現力拡張サンプルとして以下の条件を満たすことを保証する。
    /// このサンプルが壊れると、card displayType + appendMode の組合せを
    /// 新規ユーザーが目で確認する経路が消えるので、CI で守る。
    func testMidjourneyGallerySeedDemonstratesCardAndAppendMode() throws {
        let seeds = SeedPresetInstaller.bundledSeedPresets()
        guard let preset = seeds.first(where: { $0.name == "midjourney-gallery" }) else {
            XCTFail("midjourney-gallery seed not found")
            return
        }
        // 画風・ポーズ・服装・背景の 4 つは必ず card で並んでいる
        let cardGroupIds = ["g-mj-style", "g-mj-pose", "g-mj-outfit", "g-mj-background"]
        for id in cardGroupIds {
            guard let group = preset.groups.first(where: { $0.id == id }) else {
                XCTFail("group '\(id)' missing from gallery seed")
                continue
            }
            XCTAssertEqual(group.displayType, .card,
                           "group '\(id)' must use displayType=.card")
            XCTAssertFalse(group.buttons.isEmpty,
                           "group '\(id)' should ship at least one card")
            // 各カードの text アクションは appendMode=true でなければ
            // ギャラリーとしての意義 (断片を積み上げる) が成立しない。
            for button in group.buttons {
                guard case .text(_, _, _, let appendMode) = button.action else {
                    XCTFail("'\(button.id)' should be a text action")
                    continue
                }
                XCTAssertTrue(appendMode,
                              "'\(button.id)' must use appendMode=true")
            }
        }
    }
}
