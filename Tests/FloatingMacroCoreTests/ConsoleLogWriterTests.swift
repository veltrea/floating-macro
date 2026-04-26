import XCTest
@testable import FloatingMacroCore

final class ConsoleLogWriterTests: XCTestCase {

    func testFormatLineBasic() {
        let event = LogEvent(
            timestamp: Date(timeIntervalSince1970: 1_765_000_000),
            level: .info,
            category: "MacroRunner",
            message: "Starting"
        )
        let line = ConsoleLogWriter.formatLine(event)
        XCTAssertTrue(line.contains("INFO"))
        XCTAssertTrue(line.contains("MacroRunner"))
        XCTAssertTrue(line.contains("Starting"))
        XCTAssertTrue(line.contains("2025") || line.contains("2026"),
                      "timestamp year should appear")
    }

    func testFormatLineLevelIsPaddedTo5Chars() {
        let eventInfo = LogEvent(level: .info,  category: "c", message: "m")
        let eventErr  = LogEvent(level: .error, category: "c", message: "m")
        let lineInfo = ConsoleLogWriter.formatLine(eventInfo)
        let lineErr  = ConsoleLogWriter.formatLine(eventErr)
        XCTAssertTrue(lineInfo.contains("INFO "))
        XCTAssertTrue(lineErr.contains("ERROR"))
    }

    func testFormatLineMetadataAppendedSorted() {
        let event = LogEvent(
            level: .warn,
            category: "A",
            message: "B",
            metadata: ["b": "2", "a": "1", "c": "3"]
        )
        let line = ConsoleLogWriter.formatLine(event)
        let aPos = line.range(of: "a=1")!.lowerBound
        let bPos = line.range(of: "b=2")!.lowerBound
        let cPos = line.range(of: "c=3")!.lowerBound
        XCTAssertLessThan(aPos, bPos)
        XCTAssertLessThan(bPos, cPos)
    }

    func testFormatLineOmitsMetadataWhenAbsent() {
        let event = LogEvent(level: .info, category: "c", message: "m")
        let line = ConsoleLogWriter.formatLine(event)
        XCTAssertFalse(line.contains("="),
                       "no metadata should yield no key=value pairs; got:\n\(line)")
    }

    // MARK: - Writing to a pipe (stand-in for stderr)

    func testWritesToGivenFileHandle() throws {
        let pipe = Pipe()
        let writer = ConsoleLogWriter(minimumLevel: .debug,
                                      stream: pipe.fileHandleForWriting)
        writer.info("X", "hello")
        writer.flush()

        // Close write end so read doesn't block forever.
        try pipe.fileHandleForWriting.close()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let str = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(str.contains("INFO"))
        XCTAssertTrue(str.contains("hello"))
        XCTAssertTrue(str.contains("X"))
    }

    func testDropsEventsBelowMinimumLevel() throws {
        let pipe = Pipe()
        let writer = ConsoleLogWriter(minimumLevel: .warn,
                                      stream: pipe.fileHandleForWriting)
        writer.info("A", "dropped")
        writer.warn("B", "kept")
        writer.flush()
        try pipe.fileHandleForWriting.close()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let str = String(data: data, encoding: .utf8) ?? ""
        XCTAssertFalse(str.contains("dropped"))
        XCTAssertTrue(str.contains("kept"))
    }
}
