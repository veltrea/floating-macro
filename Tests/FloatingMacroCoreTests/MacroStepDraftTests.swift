import XCTest
@testable import FloatingMacroCore

/// Conversion test for the macro step edit buffer.
///
/// Prevent bug regression:
/// Parameters that are not exposed by the UI (pasteDelayMs / app of terminal, etc.)
/// Load to save round trip back to default values
/// 2. Invalid steps were silently disappearing during saving with compactMap
final class MacroStepDraftTests: XCTestCase {

    // MARK: - Hidden parameters are preserved in round trip (bug 1 regression)

    func testTextRoundTripPreservesHiddenParams() {
        let original = Action.text(content: "hello", pasteDelayMs: 350,
                                   restoreClipboard: false, appendMode: true)
        XCTAssertEqual(MacroStepDraft.from(original).toAction(), original)
    }

    func testTerminalRoundTripPreservesHiddenParams() {
        let original = Action.terminal(app: "iTerm", command: "make build",
                                       newWindow: false, execute: false, profile: "dev")
        XCTAssertEqual(MacroStepDraft.from(original).toAction(), original)
    }

    func testKeyRoundTrip() {
        let original = Action.key(combo: "cmd+shift+v")
        XCTAssertEqual(MacroStepDraft.from(original).toAction(), original)
    }

    func testLaunchRoundTrip() {
        let original = Action.launch(target: "/Applications/Slack.app")
        XCTAssertEqual(MacroStepDraft.from(original).toAction(), original)
    }

    func testDelayRoundTrip() {
        let original = Action.delay(ms: 1500)
        XCTAssertEqual(MacroStepDraft.from(original).toAction(), original)
    }

    // MARK: - Bug regression detection

    func testEmptyKeyComboIsInvalid() {
        var d = MacroStepDraft()
        d.type = "key"
        d.keyCombo = ""
        XCTAssertEqual(d.issue, .emptyKeyCombo)
        XCTAssertNil(d.toAction())
    }

    func testWhitespaceOnlyKeyComboIsInvalid() {
        var d = MacroStepDraft()
        d.type = "key"
        d.keyCombo = "   "
        XCTAssertEqual(d.issue, .emptyKeyCombo)
    }

    func testEmptyLaunchTargetIsInvalid() {
        var d = MacroStepDraft()
        d.type = "launch"
        d.launchTarget = ""
        XCTAssertEqual(d.issue, .emptyLaunchTarget)
        XCTAssertNil(d.toAction())
    }

    func testEmptyTerminalCommandIsInvalid() {
        var d = MacroStepDraft()
        d.type = "terminal"
        d.terminalCommand = ""
        XCTAssertEqual(d.issue, .emptyTerminalCommand)
        XCTAssertNil(d.toAction())
    }

    func testNonNumericDelayIsInvalid() {
        var d = MacroStepDraft()
        d.type = "delay"
        d.delayMs = "abc"
        XCTAssertEqual(d.issue, .invalidDelay)
        XCTAssertNil(d.toAction())
    }

    func testZeroDelayIsInvalid() {
        var d = MacroStepDraft()
        d.type = "delay"
        d.delayMs = "0"
        XCTAssertEqual(d.issue, .invalidDelay)
    }

    func testNegativeDelayIsInvalid() {
        var d = MacroStepDraft()
        d.type = "delay"
        d.delayMs = "-100"
        XCTAssertEqual(d.issue, .invalidDelay)
    }

    func testDelayOverOneHourIsInvalid() {
        var d = MacroStepDraft()
        d.type = "delay"
        d.delayMs = "3600001"
        XCTAssertEqual(d.issue, .invalidDelay)
    }

    func testValidDelayHasNoIssue() {
        var d = MacroStepDraft()
        d.type = "delay"
        d.delayMs = "500"
        XCTAssertNil(d.issue)
        XCTAssertEqual(d.toAction(), .delay(ms: 500))
    }

    func testEmptyTextIsStillValid() {
        // Pasting empty text is meaningless but not an operation that causes data loss, so it's acceptable.
        var d = MacroStepDraft()
        d.type = "text"
        d.text = ""
        XCTAssertNil(d.issue)
        XCTAssertNotNil(d.toAction())
    }

    func testDefaultDraftIsValidTextStep() {
        let d = MacroStepDraft()
        XCTAssertEqual(d.type, "text")
        XCTAssertNil(d.issue)
    }
}
