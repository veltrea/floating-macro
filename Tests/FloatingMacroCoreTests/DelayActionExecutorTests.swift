import XCTest
@testable import FloatingMacroCore

final class DelayActionExecutorTests: XCTestCase {

    func testNegativeMsDoesNotTrap() async throws {
        // Before, conversion from UInt64(ms) caused runtime crashes when the value was negative.
        // Confirm that it immediately returns to 0 clamped.
        let start = Date()
        try await DelayActionExecutor.execute(ms: -5000)
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.5)
    }

    func testShortDelayActuallyWaits() async throws {
        let start = Date()
        try await DelayActionExecutor.execute(ms: 30)
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(start), 0.025)
    }

    func testAllowedRangeIsOneMsToOneHour() {
        XCTAssertEqual(DelayActionExecutor.allowedMs.lowerBound, 1)
        XCTAssertEqual(DelayActionExecutor.allowedMs.upperBound, 3_600_000)
    }

    func testCancellationInterruptsSleep() async {
        // Stop mechanism based on Task.sleep: Cancellation takes effect immediately.
        let start = Date()
        let task = Task {
            try await DelayActionExecutor.execute(ms: 10_000)
        }
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        task.cancel()
        let result = await task.result
        XCTAssertLessThan(Date().timeIntervalSince(start), 5.0,
                          "cancel must interrupt the sleep long before 10s")
        if case .success = result {
            XCTFail("Expected CancellationError")
        }
    }
}
