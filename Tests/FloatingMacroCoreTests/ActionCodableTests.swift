import XCTest
@testable import FloatingMacroCore

/// Codable symmetry test for `Action`.
///
/// Both the preset file and Control API payload use this encoding.
/// For the round-trip from encode to decode, the value should remain unchanged.
/// Foundation for data preservation.
final class ActionCodableTests: XCTestCase {

    private func roundTrip(_ action: Action) throws -> Action {
        let data = try JSONEncoder().encode(action)
        return try JSONDecoder().decode(Action.self, from: data)
    }

    private func decode(_ json: String) throws -> Action {
        try JSONDecoder().decode(Action.self, from: Data(json.utf8))
    }

    // MARK: - Round trip (all cases)

    func testKeyRoundTrip() throws {
        let a = Action.key(combo: "cmd+shift+v")
        XCTAssertEqual(try roundTrip(a), a)
    }

    func testTextRoundTripPreservesAllFields() throws {
        // Using non-default values to detect field misuses
        let a = Action.text(content: "hello\nJapanese", pasteDelayMs: 350,
                            restoreClipboard: false, appendMode: true)
        XCTAssertEqual(try roundTrip(a), a)
    }

    func testTextRoundTripWithDefaults() throws {
        let a = Action.text(content: "x", pasteDelayMs: 120,
                            restoreClipboard: true, appendMode: false)
        XCTAssertEqual(try roundTrip(a), a)
    }

    func testLaunchRoundTrip() throws {
        let a = Action.launch(target: "com.tinyspeck.slackmacgap")
        XCTAssertEqual(try roundTrip(a), a)
    }

    func testTerminalRoundTripPreservesAllFields() throws {
        let a = Action.terminal(app: "iTerm", command: "make test",
                                newWindow: false, execute: false, profile: "dev")
        XCTAssertEqual(try roundTrip(a), a)
    }

    func testTerminalRoundTripNilProfile() throws {
        let a = Action.terminal(app: "Terminal", command: "ls",
                                newWindow: true, execute: true, profile: nil)
        XCTAssertEqual(try roundTrip(a), a)
    }

    func testDelayRoundTrip() throws {
        let a = Action.delay(ms: 500)
        XCTAssertEqual(try roundTrip(a), a)
    }

    func testMacroRoundTripPreservesSteps() throws {
        let a = Action.macro(actions: [
            .key(combo: "cmd+a"),
            .delay(ms: 200),
            .text(content: "x", pasteDelayMs: 50, restoreClipboard: false, appendMode: true),
            .terminal(app: "iTerm", command: "ls", newWindow: false, execute: true, profile: "p"),
            .launch(target: "/Applications/Slack.app"),
        ], stopOnError: false)
        XCTAssertEqual(try roundTrip(a), a)
    }

    // MARK: - Decode defaults

    func testTextDecodeAppliesDefaults() throws {
        let a = try decode(#"{"type":"text","content":"x"}"#)
        XCTAssertEqual(a, .text(content: "x", pasteDelayMs: 120,
                                restoreClipboard: true, appendMode: false))
    }

    func testTerminalDecodeAppliesDefaults() throws {
        let a = try decode(#"{"type":"terminal","command":"ls"}"#)
        XCTAssertEqual(a, .terminal(app: "Terminal", command: "ls",
                                    newWindow: true, execute: true, profile: nil))
    }

    func testMacroDecodeDefaultsStopOnErrorTrue() throws {
        let a = try decode(#"{"type":"macro","actions":[{"type":"delay","ms":100}]}"#)
        XCTAssertEqual(a, .macro(actions: [.delay(ms: 100)], stopOnError: true))
    }

    // MARK: - Delay range validation (negative ms used to crash at runtime)

    func testDelayDecodeRejectsNegative() {
        XCTAssertThrowsError(try decode(#"{"type":"delay","ms":-1}"#))
    }

    func testDelayDecodeRejectsZero() {
        XCTAssertThrowsError(try decode(#"{"type":"delay","ms":0}"#))
    }

    func testDelayDecodeRejectsOverOneHour() {
        XCTAssertThrowsError(try decode(#"{"type":"delay","ms":3600001}"#))
    }

    func testDelayDecodeAcceptsBounds() throws {
        XCTAssertEqual(try decode(#"{"type":"delay","ms":1}"#), .delay(ms: 1))
        XCTAssertEqual(try decode(#"{"type":"delay","ms":3600000}"#), .delay(ms: 3_600_000))
    }

    func testMacroDecodeRejectsOutOfRangeDelayStep() {
        let json = #"{"type":"macro","actions":[{"type":"delay","ms":-5}]}"#
        XCTAssertThrowsError(try decode(json))
    }

    // MARK: - Structural rejection

    func testNestedMacroDecodeRejected() {
        let json = """
        {"type":"macro","actions":[
            {"type":"macro","actions":[{"type":"key","combo":"cmd+a"}]}
        ]}
        """
        XCTAssertThrowsError(try decode(json))
    }

    func testUnknownTypeRejected() {
        XCTAssertThrowsError(try decode(#"{"type":"explode"}"#))
    }
}
