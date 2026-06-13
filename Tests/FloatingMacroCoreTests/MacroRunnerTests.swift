import XCTest
import CoreGraphics
@testable import FloatingMacroCore

final class MacroRunnerTests: XCTestCase {

    private var mocks: TestMocks!

    override func setUp() {
        super.setUp()
        mocks = TestMocks()
    }

    override func tearDown() {
        mocks.restore()
        mocks = nil
        super.tearDown()
    }

    // MARK: - Sequential execution

    func testSequentialKeyActions() async throws {
        try await MacroRunner.run(actions: [
            .key(combo: "cmd+a"),
            .key(combo: "cmd+c"),
        ])

        XCTAssertEqual(mocks.synth.calls.count, 2)
        XCTAssertEqual(mocks.synth.calls[0].keyCode, 0x00)
        XCTAssertEqual(mocks.synth.calls[1].keyCode, 0x08)
        XCTAssertTrue(mocks.synth.calls[0].flags.contains(.maskCommand))
        XCTAssertTrue(mocks.synth.calls[1].flags.contains(.maskCommand))
    }

    func testMixedActionsFlowInOrder() async throws {
        try await MacroRunner.run(actions: [
            .key(combo: "cmd+a"),
            .text(content: "x", pasteDelayMs: 0, restoreClipboard: true, appendMode: false),
            .key(combo: "enter"),
        ])

        // Two key actions + one cmd+v from text = 3 synthesizer calls.
        XCTAssertEqual(mocks.synth.calls.count, 3)
        XCTAssertEqual(mocks.synth.calls[0].keyCode, 0x00) // cmd+a
        XCTAssertEqual(mocks.synth.calls[1].keyCode, 0x09) // cmd+v (from text)
        XCTAssertEqual(mocks.synth.calls[2].keyCode, 0x24) // enter

        // Clipboard sequence: save -> setString -> restore
        XCTAssertEqual(mocks.clipboard.ops, [
            .save,
            .setString("x"),
            .restore,
        ])
    }

    // MARK: - Error handling

    func testStopOnErrorTrueAborts() async {
        mocks.synth.errorToThrow = ActionError.accessibilityDenied

        do {
            try await MacroRunner.run(actions: [
                .key(combo: "cmd+a"),
                .key(combo: "cmd+c"),
            ], stopOnError: true)
            XCTFail("Expected to throw on first action")
        } catch {
            XCTAssertEqual(error as? ActionError, .accessibilityDenied)
        }

        // Synth throws on EVERY call but stopOnError aborts after the first.
        XCTAssertEqual(mocks.synth.calls.count, 0)
    }

    func testStopOnErrorFalseContinues() async throws {
        // First key throws invalid combo; second succeeds.
        try await MacroRunner.run(actions: [
            .key(combo: "this-is-not-a-key"),
            .key(combo: "cmd+c"),
        ], stopOnError: false)

        // Only the valid combo was dispatched.
        XCTAssertEqual(mocks.synth.calls.count, 1)
        XCTAssertEqual(mocks.synth.calls[0].keyCode, 0x08)
    }

    // MARK: - Nested macro rejection

    func testNestedMacroRejectedByPreflight() async {
        let actions: [Action] = [
            .key(combo: "cmd+a"),
            .macro(actions: [.key(combo: "cmd+c")], stopOnError: true),
        ]
        do {
            try await MacroRunner.run(actions: actions)
            XCTFail("Nested macro must be rejected")
        } catch {
            XCTAssertEqual(error as? ActionError, .nestedMacroNotAllowed)
        }
        // Preflight rejects before any side-effect.
        XCTAssertEqual(mocks.synth.calls.count, 0)
    }

    // MARK: - Delay

    func testDelayActuallyWaits() async throws {
        let start = Date()
        try await MacroRunner.run(actions: [.delay(ms: 30)])
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertGreaterThanOrEqual(elapsed, 0.025,
                                    "delay must sleep at least approximately the requested ms")
    }

    func testEmptyActionsIsNoop() async throws {
        try await MacroRunner.run(actions: [])
        XCTAssertEqual(mocks.synth.calls.count, 0)
        XCTAssertEqual(mocks.clipboard.ops, [])
    }

    // MARK: - Invalid key propagates

    func testInvalidKeyComboThrows() async {
        do {
            try await MacroRunner.run(actions: [.key(combo: "foobar")])
            XCTFail("Expected invalidKeyCombo")
        } catch {
            guard case ActionError.invalidKeyCombo(let s) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(s, "foobar")
        }
    }

    // MARK: - Launch action through MacroRunner

    func testLaunchActionRoutedThroughMacroRunner() async throws {
        try await MacroRunner.run(actions: [.launch(target: "https://example.com")])
        XCTAssertEqual(mocks.launcher.openedURLs.count, 1)
        XCTAssertEqual(mocks.launcher.openedURLs.first?.absoluteString, "https://example.com")
    }

    // MARK: - Cancellation (stop mechanism)

    func testCancellationStopsRemainingSteps() async {
        let task = Task {
            try await MacroRunner.run(actions: [
                .key(combo: "cmd+a"),
                .delay(ms: 5_000),
                .key(combo: "cmd+c"),   // Should not be executed because it is after the cancellation
            ])
        }
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms: delay in progress
        task.cancel()
        let result = await task.result
        if case .success = result {
            XCTFail("Expected CancellationError")
        }
        XCTAssertEqual(mocks.synth.calls.count, 1,
                       "steps after the cancelled delay must not run")
    }

    func testCancellationOverridesStopOnErrorFalse() async {
        // stopOnError=false means "continue even if there's an error", but user stop requests are
        // Since it's not a failure, the macro will always pass through and stop completely.
        let task = Task {
            try await MacroRunner.run(actions: [
                .delay(ms: 5_000),
                .key(combo: "cmd+c"),
            ], stopOnError: false)
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()
        _ = await task.result
        XCTAssertEqual(mocks.synth.calls.count, 0)
    }

    // MARK: - Blacklist integration

    private func blacklist(patterns: [String] = ["rm -rf"],
                           autopilot: Bool = false) -> CommandBlacklist {
        CommandBlacklist(enabled: true, patterns: patterns,
                         autopilotEnabled: autopilot, autopilotPasswordHash: nil)
    }

    func testBlacklistedTextBlockedWithoutHandler() async {
        // If there is no onBlocked handler, it will be executed immediately if matched.
        do {
            try await MacroRunner.run(actions: [
                .text(content: "rm -rf /", pasteDelayMs: 0,
                      restoreClipboard: true, appendMode: false),
            ], blacklist: blacklist())
            XCTFail("Expected commandBlocked")
        } catch {
            guard case ActionError.commandBlocked(let pattern) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(pattern, "rm -rf")
        }
        // Execution (clipboard operation) does not reach
        XCTAssertEqual(mocks.clipboard.ops, [])
    }

    func testBlacklistOnBlockedDeclineAborts() async {
        var asked: [(String, String)] = []
        do {
            try await MacroRunner.run(actions: [
                .text(content: "sudo rm -rf /tmp/x", pasteDelayMs: 0,
                      restoreClipboard: true, appendMode: false),
            ], blacklist: blacklist(), onBlocked: { pattern, text in
                asked.append((pattern, text))
                return false  // User cancels
            })
            XCTFail("Expected commandBlocked after decline")
        } catch {
            guard case ActionError.commandBlocked = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertEqual(asked.count, 1)
        XCTAssertEqual(asked.first?.0, "rm -rf")
        XCTAssertEqual(mocks.clipboard.ops, [])
    }

    func testBlacklistOnBlockedProceedExecutes() async throws {
        try await MacroRunner.run(actions: [
            .text(content: "rm -rf build/", pasteDelayMs: 0,
                  restoreClipboard: true, appendMode: false),
        ], blacklist: blacklist(), onBlocked: { _, _ in
            true  // User selects "Execute"
        })
        // Executed after confirmation
        XCTAssertEqual(mocks.clipboard.setStrings, ["rm -rf build/"])
    }

    func testAutopilotBypassesBlacklist() async throws {
        var handlerCalled = false
        try await MacroRunner.run(actions: [
            .text(content: "rm -rf /", pasteDelayMs: 0,
                  restoreClipboard: true, appendMode: false),
        ], blacklist: blacklist(autopilot: true), onBlocked: { _, _ in
            handlerCalled = true
            return false
        })
        XCTAssertFalse(handlerCalled, "autopilot must skip the check entirely")
        XCTAssertEqual(mocks.clipboard.setStrings, ["rm -rf /"])
    }

    func testNonMatchingTextRunsWithoutPrompt() async throws {
        var handlerCalled = false
        try await MacroRunner.run(actions: [
            .text(content: "echo hello", pasteDelayMs: 0,
                  restoreClipboard: true, appendMode: false),
        ], blacklist: blacklist(), onBlocked: { _, _ in
            handlerCalled = true
            return true
        })
        XCTAssertFalse(handlerCalled)
        XCTAssertEqual(mocks.clipboard.setStrings, ["echo hello"])
    }
}
