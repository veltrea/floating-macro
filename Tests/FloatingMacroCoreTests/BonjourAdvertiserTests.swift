import XCTest
@testable import FloatingMacroCore

/// `NetService.publish` は実際に DNS-SD を叩く副作用が大きいので、ここでは
/// API 形状 (start/stop/state 遷移) と冪等性だけを検証する。実機広報の確認は
/// 実機 E2E スクリプトで行う。
final class BonjourAdvertiserTests: XCTestCase {

    func testInitialStateIsIdle() {
        let adv = BonjourAdvertiser()
        XCTAssertEqual(adv.state, .idle)
    }

    func testStartTransitionsToPublishing() {
        let adv = BonjourAdvertiser()
        adv.start(port: 65535) // 実際には publish が走るがテスト中に "published" になるとは限らない
        XCTAssertTrue(adv.state == .publishing || adv.state == .published)
        adv.stop()
        XCTAssertEqual(adv.state, .idle)
    }

    func testStopWhileIdleIsSafe() {
        let adv = BonjourAdvertiser()
        adv.stop() // 何もせず終わる
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
        adv.start(port: 65531) // 無視される
        XCTAssertEqual(adv.state, stateAfterFirst,
                       "二度目の start は no-op")
        adv.stop()
    }

    func testServiceTypeFollowsConvention() {
        XCTAssertEqual(BonjourAdvertiser.serviceType, "_floatingmacro._tcp.")
    }
}
