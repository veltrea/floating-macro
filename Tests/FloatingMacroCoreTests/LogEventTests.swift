import XCTest
@testable import FloatingMacroCore

final class LogEventTests: XCTestCase {

    func testInitNormalizesEmptyMetadataToNil() {
        let event = LogEvent(level: .info, category: "X", message: "y", metadata: [:])
        XCTAssertNil(event.metadata)
    }

    func testInitKeepsNonEmptyMetadata() {
        let event = LogEvent(level: .info, category: "X", message: "y",
                             metadata: ["k": "v"])
        XCTAssertEqual(event.metadata, ["k": "v"])
    }

    func testNilMetadataStaysNil() {
        let event = LogEvent(level: .info, category: "X", message: "y", metadata: nil)
        XCTAssertNil(event.metadata)
    }

    // MARK: - JSON round-trip

    func testJSONRoundTrip() throws {
        let event = LogEvent(
            timestamp: Date(timeIntervalSince1970: 1_765_000_000),
            level: .warn,
            category: "MacroRunner",
            message: "Something",
            metadata: ["count": "3", "type": "key"]
        )
        let data = try JSONEncoder.fmLogEncoder.encode(event)
        let decoded = try JSONDecoder.fmLogDecoder.decode(LogEvent.self, from: data)
        XCTAssertEqual(decoded, event)
    }

    func testJSONContainsISOTimestampWithFractionalSeconds() throws {
        let event = LogEvent(
            timestamp: Date(timeIntervalSince1970: 1_765_000_000.123),
            level: .info, category: "c", message: "m"
        )
        let data = try JSONEncoder.fmLogEncoder.encode(event)
        let str = String(data: data, encoding: .utf8) ?? ""
        // Fractional-second ISO 8601 ends in e.g. "123Z"
        XCTAssertTrue(str.contains("\"timestamp\""))
        XCTAssertTrue(str.contains("Z\""))
        XCTAssertTrue(str.contains(".") || str.contains(","),
                      "timestamp must include a fractional-seconds component")
    }

    func testJSONFieldNamesAndSortedKeys() throws {
        let event = LogEvent(level: .info, category: "A", message: "B")
        let str = try JSONEncoder.fmLogEncoder.encode(event)
            .reduce(into: "") { $0 += String(UnicodeScalar($1)) }
        // Sorted keys → category appears before level appears before message.
        let posCategory = str.range(of: "\"category\"")!.lowerBound
        let posLevel    = str.range(of: "\"level\"")!.lowerBound
        let posMessage  = str.range(of: "\"message\"")!.lowerBound
        XCTAssertLessThan(posCategory, posLevel)
        XCTAssertLessThan(posLevel, posMessage)
    }

    func testSerializedLineIsSingleLineFriendly() throws {
        // Log files are one-JSON-per-line, so the encoded output must not
        // contain a bare newline inside the value.
        let event = LogEvent(level: .info, category: "c", message: "no\nnewline",
                             metadata: ["x": "y"])
        let data = try JSONEncoder.fmLogEncoder.encode(event)
        let str = String(data: data, encoding: .utf8) ?? ""
        // The newline in "message" should be escaped.
        XCTAssertFalse(str.contains("\nnewline"))
        XCTAssertTrue(str.contains("\\n"))
    }

    func testNilMetadataRoundTripsAsNil() throws {
        // Swift's JSONEncoder omits nil Optional keys by default, which is
        // fine for our log format (keeps lines compact). What matters is
        // that decoding the line back restores metadata = nil.
        let event = LogEvent(level: .debug, category: "c", message: "m", metadata: nil)
        let data = try JSONEncoder.fmLogEncoder.encode(event)
        let decoded = try JSONDecoder.fmLogDecoder.decode(LogEvent.self, from: data)
        XCTAssertNil(decoded.metadata)
    }
}
