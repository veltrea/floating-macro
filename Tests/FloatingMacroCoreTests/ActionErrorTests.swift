import XCTest
@testable import FloatingMacroCore

final class ActionErrorTests: XCTestCase {

    // MARK: - Equatable semantics

    func testSameCaseSameAssociatedEqual() {
        XCTAssertEqual(
            ActionError.invalidKeyCombo("cmd+xyz"),
            ActionError.invalidKeyCombo("cmd+xyz")
        )
        XCTAssertEqual(ActionError.accessibilityDenied, .accessibilityDenied)
        XCTAssertEqual(
            ActionError.automationDenied(app: "Terminal"),
            ActionError.automationDenied(app: "Terminal")
        )
        XCTAssertEqual(
            ActionError.shellCommandFailed(exitCode: 1, stderr: "x"),
            ActionError.shellCommandFailed(exitCode: 1, stderr: "x")
        )
    }

    func testDifferentAssociatedNotEqual() {
        XCTAssertNotEqual(
            ActionError.invalidKeyCombo("a"),
            ActionError.invalidKeyCombo("b")
        )
        XCTAssertNotEqual(
            ActionError.automationDenied(app: "Terminal"),
            ActionError.automationDenied(app: "iTerm")
        )
        XCTAssertNotEqual(
            ActionError.shellCommandFailed(exitCode: 1, stderr: "x"),
            ActionError.shellCommandFailed(exitCode: 2, stderr: "x")
        )
    }

    func testDifferentCasesNotEqual() {
        XCTAssertNotEqual(ActionError.accessibilityDenied, .clipboardAccessFailed)
        XCTAssertNotEqual(
            ActionError.launchTargetNotFound("x"),
            ActionError.urlSchemeUnhandled("x")
        )
    }

    // MARK: - All cases are covered (compile-time reminder)

    /// If a new case is added to ActionError, this test will fail to compile
    /// — prompting the author to consider if tests need updating too.
    func testExhaustiveSwitch() {
        let allSamples: [ActionError] = [
            .invalidKeyCombo("x"),
            .accessibilityDenied,
            .automationDenied(app: "x"),
            .launchTargetNotFound("x"),
            .urlSchemeUnhandled("x"),
            .clipboardAccessFailed,
            .appleScriptFailed(message: "x"),
            .shellCommandFailed(exitCode: 1, stderr: "x"),
            .nestedMacroNotAllowed,
        ]
        for err in allSamples {
            switch err {
            case .invalidKeyCombo,
                 .accessibilityDenied,
                 .automationDenied,
                 .launchTargetNotFound,
                 .urlSchemeUnhandled,
                 .clipboardAccessFailed,
                 .appleScriptFailed,
                 .shellCommandFailed,
                 .nestedMacroNotAllowed:
                break
            }
        }
        XCTAssertEqual(allSamples.count, 9, "update this count when adding new ActionError cases")
    }
}
