import XCTest
@testable import FloatingMacroCore

final class LogLevelTests: XCTestCase {

    func testSeverityOrdering() {
        XCTAssertLessThan(LogLevel.debug, LogLevel.info)
        XCTAssertLessThan(LogLevel.info,  LogLevel.warn)
        XCTAssertLessThan(LogLevel.warn,  LogLevel.error)

        XCTAssertGreaterThan(LogLevel.error, LogLevel.debug)
        XCTAssertEqual(LogLevel.info, LogLevel.info)
    }

    func testSeverityNumeric() {
        XCTAssertEqual(LogLevel.debug.severity, 0)
        XCTAssertEqual(LogLevel.info.severity,  1)
        XCTAssertEqual(LogLevel.warn.severity,  2)
        XCTAssertEqual(LogLevel.error.severity, 3)
    }

    func testCaseIterableIsSortedBySeverity() {
        let sorted = LogLevel.allCases.sorted()
        XCTAssertEqual(sorted, [.debug, .info, .warn, .error])
    }

    func testRawValuesAreCanonicalLowercase() {
        XCTAssertEqual(LogLevel.debug.rawValue, "debug")
        XCTAssertEqual(LogLevel.info.rawValue,  "info")
        XCTAssertEqual(LogLevel.warn.rawValue,  "warn")
        XCTAssertEqual(LogLevel.error.rawValue, "error")
    }

    func testParseExactMatches() {
        XCTAssertEqual(LogLevel.parse("debug"), .debug)
        XCTAssertEqual(LogLevel.parse("info"),  .info)
        XCTAssertEqual(LogLevel.parse("warn"),  .warn)
        XCTAssertEqual(LogLevel.parse("error"), .error)
    }

    func testParseCaseInsensitive() {
        XCTAssertEqual(LogLevel.parse("DEBUG"), .debug)
        XCTAssertEqual(LogLevel.parse("Info"),  .info)
        XCTAssertEqual(LogLevel.parse("WaRn"),  .warn)
    }

    func testParseAliases() {
        XCTAssertEqual(LogLevel.parse("dbg"),      .debug)
        XCTAssertEqual(LogLevel.parse("warning"),  .warn)
        XCTAssertEqual(LogLevel.parse("err"),      .error)
    }

    func testParseUnknownReturnsNil() {
        XCTAssertNil(LogLevel.parse(""))
        XCTAssertNil(LogLevel.parse("trace"))
        XCTAssertNil(LogLevel.parse("fatal"))
    }

    // MARK: - Codable via JSON

    func testCodableRoundTrip() throws {
        for level in LogLevel.allCases {
            let data = try JSONEncoder().encode(level)
            let decoded = try JSONDecoder().decode(LogLevel.self, from: data)
            XCTAssertEqual(decoded, level)
        }
    }
}
