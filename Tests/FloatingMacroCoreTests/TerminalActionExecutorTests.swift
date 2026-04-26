import XCTest
@testable import FloatingMacroCore

final class TerminalActionExecutorTests: XCTestCase {

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

    // MARK: - Terminal.app branch

    func testTerminalAppNewWindowDispatchesDoScript() throws {
        try TerminalActionExecutor.execute(
            app: "Terminal",
            command: "ls -la",
            newWindow: true
        )
        XCTAssertEqual(mocks.script.scripts.count, 1)
        let s = mocks.script.scripts[0]
        XCTAssertTrue(s.contains("tell application \"Terminal\""))
        XCTAssertTrue(s.contains("do script \"ls -la\""))
        XCTAssertFalse(s.contains("in front window"))
    }

    func testTerminalAppExistingWindowUsesFrontWindow() throws {
        try TerminalActionExecutor.execute(
            app: "Terminal",
            command: "pwd",
            newWindow: false
        )
        let s = mocks.script.scripts[0]
        XCTAssertTrue(s.contains("in front window"))
    }

    func testTerminalAppLowercaseAlias() throws {
        try TerminalActionExecutor.execute(
            app: "terminal.app",
            command: "ls"
        )
        XCTAssertTrue(mocks.script.scripts[0].contains("tell application \"Terminal\""))
    }

    // MARK: - iTerm branch

    func testITermNewWindowUsesCreateWindow() throws {
        try TerminalActionExecutor.execute(
            app: "iTerm",
            command: "echo hi",
            newWindow: true,
            execute: true,
            profile: nil
        )
        let s = mocks.script.scripts[0]
        XCTAssertTrue(s.contains("tell application \"iTerm\""))
        XCTAssertTrue(s.contains("create window with default profile"))
        XCTAssertTrue(s.contains("write text \"echo hi\""))
        XCTAssertFalse(s.contains("without newline"))
    }

    func testITermNewTabUsesCreateTab() throws {
        try TerminalActionExecutor.execute(
            app: "iTerm2",
            command: "echo tab",
            newWindow: false
        )
        let s = mocks.script.scripts[0]
        XCTAssertTrue(s.contains("create tab with default profile"))
        XCTAssertFalse(s.contains("create window with default profile"))
    }

    func testITermExecuteFalseUsesWithoutNewline() throws {
        try TerminalActionExecutor.execute(
            app: "iTerm",
            command: "rm -rf /",
            newWindow: true,
            execute: false
        )
        let s = mocks.script.scripts[0]
        XCTAssertTrue(s.contains("write text \"rm -rf /\" without newline"))
    }

    func testITermProfileClauseInjected() throws {
        try TerminalActionExecutor.execute(
            app: "iTerm",
            command: "ls",
            newWindow: true,
            profile: "DevProfile"
        )
        let s = mocks.script.scripts[0]
        XCTAssertTrue(s.contains("with profile \"DevProfile\""))
    }

    // MARK: - AppleScript escaping

    func testCommandWithDoubleQuotesIsEscaped() throws {
        try TerminalActionExecutor.execute(
            app: "Terminal",
            command: "echo \"hello\""
        )
        let s = mocks.script.scripts[0]
        // The quotes must be backslash-escaped in the generated script.
        XCTAssertTrue(s.contains(#"do script "echo \"hello\"""#),
                      "embedded quotes must be escaped; got:\n\(s)")
    }

    func testCommandWithBackslashesIsEscaped() throws {
        try TerminalActionExecutor.execute(
            app: "Terminal",
            command: #"C:\path\here"#
        )
        let s = mocks.script.scripts[0]
        XCTAssertTrue(s.contains(#"do script "C:\\path\\here""#),
                      "backslashes must be doubled; got:\n\(s)")
    }

    func testAppleScriptFailurePropagates() {
        mocks.script.errorToThrow = ActionError.appleScriptFailed(message: "nope")
        XCTAssertThrowsError(try TerminalActionExecutor.execute(
            app: "Terminal",
            command: "ls"
        )) { error in
            XCTAssertEqual(error as? ActionError, .appleScriptFailed(message: "nope"))
        }
    }

    // MARK: - Generic terminal branch (other apps via NSWorkspace + paste)

    func testGenericTerminalAbsolutePathOpensURLThenPastes() throws {
        // Use a real existing path; we won't really launch an app since
        // the launcher is mocked.
        try TerminalActionExecutor.execute(
            app: "/Applications/Xcode.app",
            command: "echo from-generic",
            execute: true
        )
        // Launcher received the app URL.
        XCTAssertEqual(mocks.launcher.openedURLs.count, 1)
        XCTAssertEqual(mocks.launcher.openedURLs[0].path, "/Applications/Xcode.app")
        // Clipboard got the command.
        XCTAssertEqual(mocks.clipboard.setStrings, ["echo from-generic"])
        // Cmd+V AND Enter dispatched.
        XCTAssertEqual(mocks.synth.calls.count, 2)
        XCTAssertEqual(mocks.synth.calls[0].keyCode, 0x09) // v
        XCTAssertEqual(mocks.synth.calls[1].keyCode, 0x24) // enter
    }

    func testGenericTerminalExecuteFalseSkipsEnter() throws {
        try TerminalActionExecutor.execute(
            app: "/Applications/Xcode.app",
            command: "echo no-enter",
            execute: false
        )
        XCTAssertEqual(mocks.synth.calls.count, 1)
        XCTAssertEqual(mocks.synth.calls[0].keyCode, 0x09) // v only
    }

    func testGenericTerminalClipboardSaveRestoreSymmetry() throws {
        try TerminalActionExecutor.execute(
            app: "/Applications/Xcode.app",
            command: "do something"
        )
        // save -> setString -> (paste) -> restore
        XCTAssertEqual(mocks.clipboard.ops.first, .save)
        XCTAssertEqual(mocks.clipboard.ops.last, .restore)
    }
}
