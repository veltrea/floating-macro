import XCTest
@testable import FloatingMacroCore

/// End-to-end log assertions: run real Executors and MacroRunner with an
/// `InMemoryLogger` installed, and verify the expected log records appear.
///
/// These tests guarantee that the log contract stays intact — each action
/// path must emit at least one info/warn/error line so downstream AI
/// observation can reconstruct what happened.
final class LoggingIntegrationTests: XCTestCase {

    private var mocks: TestMocks!
    private var logBuffer: InMemoryLogger!
    private var previousLogger: FMLogger!

    override func setUp() {
        super.setUp()
        mocks = TestMocks()
        logBuffer = InMemoryLogger(minimumLevel: .debug)
        previousLogger = LoggerContext.shared
        LoggerContext.shared = logBuffer
    }

    override func tearDown() {
        LoggerContext.shared = previousLogger
        mocks.restore()
        mocks = nil
        logBuffer = nil
        super.tearDown()
    }

    // MARK: - KeyActionExecutor

    func testKeyActionLogsDispatchOnSuccess() throws {
        let combo = try KeyCombo.parse("cmd+v")
        try KeyActionExecutor.execute(combo)
        logBuffer.flush()

        XCTAssertTrue(logBuffer.contains(category: "KeyAction",
                                         messageContains: "Dispatching"))
        XCTAssertFalse(logBuffer.events.contains(where: { $0.level == .error }),
                       "successful dispatch must not log errors")
    }

    func testKeyActionLogsErrorOnFailure() {
        mocks.synth.errorToThrow = ActionError.accessibilityDenied
        let combo = try! KeyCombo.parse("cmd+v")
        XCTAssertThrowsError(try KeyActionExecutor.execute(combo))
        logBuffer.flush()

        let errors = logBuffer.events.filter { $0.level == .error }
        XCTAssertFalse(errors.isEmpty, "failure path must emit an error log")
        XCTAssertTrue(errors.contains { $0.message.contains("Key dispatch failed") })
    }

    // MARK: - TextActionExecutor

    func testTextActionLogsInjectedOnSuccess() throws {
        try TextActionExecutor.execute(content: "hi", pasteDelayMs: 0, restoreClipboard: false)
        logBuffer.flush()

        XCTAssertTrue(logBuffer.contains(category: "TextAction",
                                         messageContains: "Text injected"))
    }

    func testTextActionLogsErrorOnPasteFailure() {
        mocks.synth.errorToThrow = ActionError.accessibilityDenied
        XCTAssertThrowsError(try TextActionExecutor.execute(
            content: "x", pasteDelayMs: 0, restoreClipboard: false
        ))
        logBuffer.flush()

        let errors = logBuffer.events.filter { $0.level == .error }
        XCTAssertTrue(errors.contains { $0.message.contains("Cmd+V dispatch failed") })
    }

    // MARK: - LaunchActionExecutor

    func testLaunchURLLogsOpening() throws {
        try LaunchActionExecutor.execute(target: "https://example.com")
        logBuffer.flush()

        let infos = logBuffer.events.filter { $0.level == .info }
        XCTAssertTrue(infos.contains { $0.message.contains("Opening URL") })
    }

    func testLaunchShellLogsFailureWithStderr() {
        XCTAssertThrowsError(try LaunchActionExecutor.execute(
            target: "shell:echo boom 1>&2; exit 7"
        ))
        logBuffer.flush()
        let errors = logBuffer.events.filter { $0.level == .error }
        XCTAssertTrue(errors.contains { ev in
            ev.message.contains("Shell command failed") &&
            (ev.metadata?["exitCode"] == "7")
        })
    }

    func testLaunchNonExistingPathLogsError() {
        XCTAssertThrowsError(try LaunchActionExecutor.execute(
            target: "/definitely/does/not/exist-\(UUID().uuidString)"
        ))
        logBuffer.flush()
        XCTAssertTrue(logBuffer.events.contains {
            $0.level == .error && $0.message.contains("Path does not exist")
        })
    }

    // MARK: - TerminalActionExecutor

    func testTerminalActionLogsDispatch() throws {
        try TerminalActionExecutor.execute(app: "Terminal", command: "ls")
        logBuffer.flush()

        XCTAssertTrue(logBuffer.contains(category: "TerminalAction",
                                         messageContains: "Dispatching"))
    }

    func testTerminalActionLogsErrorOnAppleScriptFailure() {
        mocks.script.errorToThrow = ActionError.appleScriptFailed(message: "nope")
        XCTAssertThrowsError(try TerminalActionExecutor.execute(
            app: "Terminal", command: "ls"
        ))
        logBuffer.flush()

        XCTAssertTrue(logBuffer.events.contains {
            $0.level == .error && $0.message.contains("Terminal action failed")
        })
    }

    // MARK: - MacroRunner

    func testMacroRunnerLogsStartAndCompletion() async throws {
        try await MacroRunner.run(actions: [
            .key(combo: "cmd+a"),
            .key(combo: "cmd+c"),
        ])
        logBuffer.flush()

        XCTAssertTrue(logBuffer.contains(category: "MacroRunner",
                                         messageContains: "Starting macro"))
        XCTAssertTrue(logBuffer.contains(category: "MacroRunner",
                                         messageContains: "Completed macro"))

        let completion = logBuffer.events.first { $0.message.contains("Completed") }
        XCTAssertEqual(completion?.metadata?["success"], "2")
        XCTAssertEqual(completion?.metadata?["failed"], "0")
    }

    func testMacroRunnerLogsAbortOnStopOnError() async {
        mocks.synth.errorToThrow = ActionError.accessibilityDenied
        do {
            try await MacroRunner.run(actions: [
                .key(combo: "cmd+a"),
                .key(combo: "cmd+c"),
            ], stopOnError: true)
            XCTFail("Expected to throw")
        } catch {
            // expected
        }
        logBuffer.flush()

        let aborts = logBuffer.events.filter {
            $0.level == .error && $0.message.contains("Macro aborted")
        }
        XCTAssertFalse(aborts.isEmpty)
        XCTAssertEqual(aborts.first?.metadata?["completed"], "0")
        XCTAssertEqual(aborts.first?.metadata?["remaining"], "1")
    }

    func testMacroRunnerLogsContinuationWhenStopOnErrorFalse() async throws {
        try await MacroRunner.run(actions: [
            .key(combo: "invalid-key"),
            .key(combo: "cmd+c"),
        ], stopOnError: false)
        logBuffer.flush()

        let warns = logBuffer.events.filter {
            $0.level == .warn && $0.message.contains("Action failed")
        }
        XCTAssertEqual(warns.count, 1)

        let completion = logBuffer.events.first { $0.message.contains("Completed") }
        XCTAssertEqual(completion?.metadata?["success"], "1")
        XCTAssertEqual(completion?.metadata?["failed"], "1")
    }

    // MARK: - ConfigLoader

    func testConfigLoaderLogsFailureOnMissingFile() {
        let loader = ConfigLoader(baseURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("nope-\(UUID().uuidString)"))
        XCTAssertThrowsError(try loader.loadAppConfig())
        logBuffer.flush()

        XCTAssertTrue(logBuffer.events.contains {
            $0.category == "ConfigLoader"
                && $0.level == .error
                && $0.message.contains("Failed to load app config")
        })
    }
}
