import XCTest
@testable import FloatingMacroCore

/// `AutomationChecker` relies on real Apple Event machinery, so we only test
/// behaviors that don't depend on the user's current automation permissions.
/// These tests verify:
/// - Well-known bundle id constants are correct.
/// - Calls with `askUserIfNeeded: false` never prompt and return a value.
/// - Unknown bundle ids don't crash.
final class AutomationCheckerTests: XCTestCase {

    func testKnownTargetConstants() {
        XCTAssertEqual(AutomationChecker.KnownTarget.terminalApp, "com.apple.Terminal")
        XCTAssertEqual(AutomationChecker.KnownTarget.iTerm,       "com.googlecode.iterm2")
    }

    func testCheckWithoutPromptReturnsAValidStatus() {
        // Must not prompt the user, must not crash, must return SOMETHING.
        let status = AutomationChecker.check(bundleIdentifier: "com.apple.Terminal",
                                             askUserIfNeeded: false)
        // Any of these four is valid — we don't know the CI machine's state.
        let validStates: Set<AutomationChecker.PermissionStatus> = [
            .authorized, .denied, .notDetermined, .targetUnavailable,
        ]
        XCTAssertTrue(validStates.contains(status), "unexpected status: \(status)")
    }

    func testCheckNonExistentBundleIdDoesNotCrash() {
        // A definitely-not-installed bundle id should yield targetUnavailable
        // or notDetermined, never crash.
        let status = AutomationChecker.check(
            bundleIdentifier: "com.fake.nonexistent.\(UUID().uuidString)",
            askUserIfNeeded: false
        )
        XCTAssertNotEqual(status, .authorized,
                          "never-installed app must not report .authorized")
    }

    func testIsAuthorizedConvenience() {
        // Just ensure the convenience returns a Bool without crashing.
        _ = AutomationChecker.isAuthorized(bundleIdentifier: "com.apple.Terminal")
    }

    // MARK: - PermissionStatus Equatable

    func testPermissionStatusEquatable() {
        XCTAssertEqual(AutomationChecker.PermissionStatus.authorized, .authorized)
        XCTAssertNotEqual(AutomationChecker.PermissionStatus.authorized, .denied)
    }
}
