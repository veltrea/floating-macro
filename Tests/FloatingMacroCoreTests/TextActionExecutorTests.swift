import XCTest
import CoreGraphics
@testable import FloatingMacroCore

final class TextActionExecutorTests: XCTestCase {

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

    // MARK: - Flow order (SPEC §7.2)

    func testExecuteFollowsSaveSetPasteRestoreOrder() throws {
        try TextActionExecutor.execute(content: "hello", pasteDelayMs: 0, restoreClipboard: true)

        XCTAssertEqual(mocks.clipboard.ops, [
            .save,
            .setString("hello"),
            .restore,
        ])

        XCTAssertEqual(mocks.synth.calls.count, 1)
        XCTAssertEqual(mocks.synth.calls[0].keyCode, 0x09) // v
        XCTAssertTrue(mocks.synth.calls[0].flags.contains(.maskCommand))
    }

    func testRestoreClipboardFalseSkipsRestore() throws {
        try TextActionExecutor.execute(content: "hi", pasteDelayMs: 0, restoreClipboard: false)

        // No .restore op
        XCTAssertEqual(mocks.clipboard.ops, [
            .save,
            .setString("hi"),
        ])
        // Still pastes.
        XCTAssertEqual(mocks.synth.calls.count, 1)
    }

    func testMultilineContentPreserved() throws {
        let content = "line1\nline2\nline3"
        try TextActionExecutor.execute(content: content, pasteDelayMs: 0, restoreClipboard: true)
        XCTAssertEqual(mocks.clipboard.setStrings, [content])
    }

    func testUnicodeContentPreserved() throws {
        let content = "ultrathink で考えて 🧠 日本語 العربية"
        try TextActionExecutor.execute(content: content, pasteDelayMs: 0, restoreClipboard: true)
        XCTAssertEqual(mocks.clipboard.setStrings, [content])
    }

    func testEmptyContentStillPastes() throws {
        try TextActionExecutor.execute(content: "", pasteDelayMs: 0, restoreClipboard: true)
        XCTAssertEqual(mocks.clipboard.setStrings, [""])
        XCTAssertEqual(mocks.synth.calls.count, 1)
    }

    // MARK: - Timing contract

    func testPasteDelayActuallySleeps() throws {
        let start = Date()
        try TextActionExecutor.execute(content: "x", pasteDelayMs: 40, restoreClipboard: false)
        let elapsed = Date().timeIntervalSince(start)
        // 10 ms pre-sleep + 40 ms paste delay = expect at least ~45 ms.
        XCTAssertGreaterThanOrEqual(elapsed, 0.040,
                                    "paste delay should sleep approximately the requested ms")
    }

    // MARK: - Failure path

    /// If the keyboard synthesizer fails (e.g. Accessibility denied), the
    /// user's clipboard must still be restored — otherwise we leak the paste
    /// content (which may be sensitive: passwords, API keys, etc.) into the
    /// system clipboard.
    func testSynthesizerFailureStillRestoresClipboard() throws {
        mocks.synth.errorToThrow = ActionError.accessibilityDenied

        XCTAssertThrowsError(try TextActionExecutor.execute(
            content: "oops",
            pasteDelayMs: 0,
            restoreClipboard: true
        )) { error in
            XCTAssertEqual(error as? ActionError, .accessibilityDenied)
        }

        // Full sequence completes: save -> setString -> (cmd+v fails) -> restore.
        XCTAssertEqual(mocks.clipboard.ops, [
            .save,
            .setString("oops"),
            .restore,
        ])
    }

    /// When restoreClipboard=false the user explicitly opted out of restore
    /// even on failure, so we must NOT perform it.
    func testSynthesizerFailureWithRestoreDisabledDoesNotRestore() throws {
        mocks.synth.errorToThrow = ActionError.accessibilityDenied

        XCTAssertThrowsError(try TextActionExecutor.execute(
            content: "keep",
            pasteDelayMs: 0,
            restoreClipboard: false
        ))

        XCTAssertEqual(mocks.clipboard.ops, [
            .save,
            .setString("keep"),
        ])
    }
}
