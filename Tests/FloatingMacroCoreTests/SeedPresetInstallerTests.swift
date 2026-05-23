import XCTest
@testable import FloatingMacroCore

/// The bundled seed JSON group can be decoded as a preset.
/// Accessibility seed for destructive operations (restart / shutdown /
/// Guarantee that the logout is confirmed with a guard.
///
/// Why test?
/// If the `confirm` is left out and released, visual input / Switch Control
/// The user may risk turning off the power due to a false trigger. Schema changes or JSON...
/// Ensure that the missing "confirm" is always detected by CI.
final class SeedPresetInstallerTests: XCTestCase {

    func testAllBundledSeedsDecodeSuccessfully() {
        let seeds = SeedPresetInstaller.bundledSeedPresets()
        XCTAssertFalse(seeds.isEmpty,
                       "bundle should ship at least one seed JSON")
        let names = Set(seeds.map { $0.name })
        // Check if all known seeds can be read randomly. New seeds are
        // Added tests still pass (subset comparison).
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

    /// Button that causes minimal damage even if pressed by mistake (screen lock / sleep / force quit)
    /// The dialog does not require confirmation; the user frequently requests confirm.
    /// Assuming the user will press repeatedly, having a dialog box each time would impose too much operational burden.
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

    /// The 'MidJourney Prompt Gallery' seed added in v0.11 is:
    /// Ensures that the following conditions are satisfied as an expressive extension sample of Phase 2.
    /// If this sample breaks, the combination of card displayType and appendMode is
    /// New users need to verify visually, so protect it with CI.
    func testMidjourneyGallerySeedDemonstratesCardAndAppendMode() throws {
        let seeds = SeedPresetInstaller.bundledSeedPresets()
        guard let preset = seeds.first(where: { $0.name == "midjourney-gallery" }) else {
            XCTFail("midjourney-gallery seed not found")
            return
        }
        // Four: style, pose, clothing, background must be always arranged in a card.
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
            // Each card's text action must be appendMode=true.
            // The significance as a gallery (accumulating fragments) cannot be established.
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
