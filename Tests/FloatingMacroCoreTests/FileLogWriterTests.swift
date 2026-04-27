import XCTest
@testable import FloatingMacroCore

final class FileLogWriterTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("fmlog-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func url(_ name: String = "floatingmacro.log") -> URL {
        tempDir.appendingPathComponent(name)
    }

    private func readLines(_ u: URL) throws -> [String] {
        let data = try String(contentsOf: u, encoding: .utf8)
        return data.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }

    // MARK: - Basic write

    func testCreatesFileAndAppendsLine() throws {
        let writer = try FileLogWriter(url: url(), minimumLevel: .debug)
        writer.info("X", "hello")
        writer.flush()

        let lines = try readLines(url())
        XCTAssertEqual(lines.count, 1)
        let decoded = try JSONDecoder.fmLogDecoder.decode(LogEvent.self,
                                                          from: lines[0].data(using: .utf8)!)
        XCTAssertEqual(decoded.category, "X")
        XCTAssertEqual(decoded.message, "hello")
        XCTAssertEqual(decoded.level, .info)
    }

    func testAppendsMultipleLines() throws {
        let writer = try FileLogWriter(url: url(), minimumLevel: .debug)
        writer.info("A", "one")
        writer.warn("B", "two")
        writer.error("C", "three", ["k": "v"])
        writer.flush()

        let lines = try readLines(url())
        XCTAssertEqual(lines.count, 3)
        // Every line should independently decode.
        for line in lines {
            _ = try JSONDecoder.fmLogDecoder.decode(LogEvent.self, from: line.data(using: .utf8)!)
        }
    }

    // MARK: - Level filtering

    func testDropsEventsBelowMinimumLevel() throws {
        let writer = try FileLogWriter(url: url(), minimumLevel: .warn)
        writer.debug("A", "skipped")
        writer.info("B", "skipped")
        writer.warn("C", "kept")
        writer.error("D", "kept")
        writer.flush()

        let lines = try readLines(url())
        XCTAssertEqual(lines.count, 2)
        let cats = try lines.map {
            try JSONDecoder.fmLogDecoder.decode(LogEvent.self, from: $0.data(using: .utf8)!).category
        }
        XCTAssertEqual(cats, ["C", "D"])
    }

    // MARK: - Rotation at maxBytes

    func testRotatesWhenMaxBytesExceeded() throws {
        // Small threshold so a few lines trigger rotation.
        let writer = try FileLogWriter(url: url(), minimumLevel: .debug, maxBytes: 400)
        for i in 0..<50 {
            writer.info("bulk", "line \(i)", ["n": String(i)])
        }
        writer.flush()

        let current = url()
        let rotated = url().appendingPathExtension("old")
        XCTAssertTrue(FileManager.default.fileExists(atPath: current.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: rotated.path),
                      "rotation must create a .old file")

        // The current file should be smaller than total data written.
        let currentSize = (try FileManager.default.attributesOfItem(atPath: current.path)[.size] as? Int) ?? 0
        XCTAssertLessThan(currentSize, 4_000, "rotation should keep current file small")

        // Lines in both files together must decode cleanly.
        let l1 = try readLines(current)
        let l2 = try readLines(rotated)
        for line in l1 + l2 {
            _ = try JSONDecoder.fmLogDecoder.decode(LogEvent.self, from: line.data(using: .utf8)!)
        }
    }

    func testSecondRotationOverwritesPreviousOld() throws {
        let writer = try FileLogWriter(url: url(), minimumLevel: .debug, maxBytes: 300)
        for i in 0..<30 {
            writer.info("r1", "first round \(i)")
        }
        writer.flush()
        let rotated = url().appendingPathExtension("old")
        let firstOldData = try String(contentsOf: rotated, encoding: .utf8)

        for i in 0..<30 {
            writer.info("r2", "second round \(i)")
        }
        writer.flush()

        let afterOld = try String(contentsOf: rotated, encoding: .utf8)
        XCTAssertNotEqual(firstOldData, afterOld,
                          "second rotation must replace the previous .old file")
    }

    // MARK: - Concurrent writes

    func testConcurrentWritesAreSerialized() throws {
        let writer = try FileLogWriter(url: url(), minimumLevel: .debug)
        let group = DispatchGroup()
        for i in 0..<100 {
            DispatchQueue.global().async(group: group) {
                writer.info("t", "msg \(i)")
            }
        }
        group.wait()
        writer.flush()

        let lines = try readLines(url())
        XCTAssertEqual(lines.count, 100)
        // Each line must be complete JSON — this would fail if two writes
        // interleaved mid-line.
        for line in lines {
            _ = try JSONDecoder.fmLogDecoder.decode(LogEvent.self, from: line.data(using: .utf8)!)
        }
    }

    // MARK: - Directory creation

    func testCreatesParentDirectoryIfMissing() throws {
        let nested = tempDir.appendingPathComponent("a/b/c/out.log")
        _ = try FileLogWriter(url: nested, minimumLevel: .debug)
        XCTAssertTrue(FileManager.default.fileExists(atPath: nested.deletingLastPathComponent().path))
    }
}
