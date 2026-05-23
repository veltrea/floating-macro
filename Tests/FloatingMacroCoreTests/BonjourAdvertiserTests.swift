import XCTest
@testable import FloatingMacroCore

/// The `NetService.publish` method actually involves significant interaction with DNS-SD, so here we will...
/// Verify only the shape of the API (start/stop/state transitions) and idempotence. Confirmation on actual devices is not required.
/// Run on actual devices in end-to-end scripts.
final class BonjourAdvertiserTests: XCTestCase {

    func testInitialStateIsIdle() {
        let adv = BonjourAdvertiser()
        XCTAssertEqual(adv.state, .idle)
    }

    func testStartTransitionsToPublishing() {
        let adv = BonjourAdvertiser()
        adv.start(port: 65535) // In practice, publish runs, but it is not necessarily set to "published" during testing.
        XCTAssertTrue(adv.state == .publishing || adv.state == .published)
        adv.stop()
        XCTAssertEqual(adv.state, .idle)
    }

    func testStopWhileIdleIsSafe() {
        let adv = BonjourAdvertiser()
        adv.stop() // End without doing anything
        XCTAssertEqual(adv.state, .idle)
    }

    func testInvalidPortIsRejected() {
        let adv = BonjourAdvertiser()
        adv.start(port: 0)
        XCTAssertEqual(adv.state, .idle)
        adv.start(port: 70000)
        XCTAssertEqual(adv.state, .idle)
    }

    func testDoubleStartIsIdempotent() {
        let adv = BonjourAdvertiser()
        adv.start(port: 65530)
        let stateAfterFirst = adv.state
        adv.start(port: 65531) // ignored
        XCTAssertEqual(adv.state, stateAfterFirst,
                       "二度目の start は no-op")
        adv.stop()
    }

    func testServiceTypeFollowsConvention() {
        XCTAssertEqual(BonjourAdvertiser.serviceType, "_floatingmacro._tcp.")
    }
}
