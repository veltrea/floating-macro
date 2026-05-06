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

    // MARK: - appendMode (prompt builder)

    /// appendMode=true: read current clipboard, concatenate fragment, write
    /// back, do NOT paste, do NOT save/restore.
    func testAppendModeAppendsToExistingClipboardWithoutPasting() throws {
        mocks.clipboard.currentString = "anime style, "

        try TextActionExecutor.execute(
            content: "running pose, ",
            pasteDelayMs: 0,
            restoreClipboard: true,    // ignored under appendMode
            appendMode: true
        )

        // No save / no restore / no paste — only getString + setString.
        XCTAssertEqual(mocks.clipboard.ops, [
            .getString,
            .setString("anime style, running pose, "),
        ])
        XCTAssertEqual(mocks.synth.calls.count, 0,
                       "appendMode must not synthesize Cmd+V")
        XCTAssertEqual(mocks.clipboard.currentString,
                       "anime style, running pose, ")
    }

    /// Empty clipboard: appendMode behaves as a plain set (no separator added
    /// by the executor — caller controls separators in the fragment text).
    func testAppendModeOnEmptyClipboardWritesContentVerbatim() throws {
        mocks.clipboard.currentString = nil

        try TextActionExecutor.execute(
            content: "first fragment",
            pasteDelayMs: 0,
            restoreClipboard: false,
            appendMode: true
        )

        XCTAssertEqual(mocks.clipboard.ops, [
            .getString,
            .setString("first fragment"),
        ])
    }

    /// Multiple successive append calls accumulate. Mirrors the prompt-builder
    /// usage where the user clicks several fragment buttons in sequence.
    func testAppendModeAccumulatesAcrossMultipleCalls() throws {
        mocks.clipboard.currentString = nil

        try TextActionExecutor.execute(content: "anime, ",  pasteDelayMs: 0,
                                       restoreClipboard: false, appendMode: true)
        try TextActionExecutor.execute(content: "running, ", pasteDelayMs: 0,
                                       restoreClipboard: false, appendMode: true)
        try TextActionExecutor.execute(content: "office",   pasteDelayMs: 0,
                                       restoreClipboard: false, appendMode: true)

        XCTAssertEqual(mocks.clipboard.currentString, "anime, running, office")
        XCTAssertEqual(mocks.synth.calls.count, 0)
    }

    /// appendMode=false (default) preserves the legacy paste-and-restore flow.
    func testAppendModeFalseFollowsLegacyPasteFlow() throws {
        try TextActionExecutor.execute(
            content: "hello",
            pasteDelayMs: 0,
            restoreClipboard: true,
            appendMode: false
        )

        XCTAssertEqual(mocks.clipboard.ops, [
            .save,
            .setString("hello"),
            .restore,
        ])
        XCTAssertEqual(mocks.synth.calls.count, 1)
    }
}
