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
            .text(content: "x", pasteDelayMs: 0, restoreClipboard: true),
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
}
