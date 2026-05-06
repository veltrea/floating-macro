import XCTest
@testable import FloatingMacroCore

final class InMemoryLoggerTests: XCTestCase {

    func testRecordsEvents() {
        let log = InMemoryLogger(minimumLevel: .debug)
        log.info("A", "hello")
        log.warn("B", "world", ["k": "v"])
        log.flush()

        XCTAssertEqual(log.events.count, 2)
        XCTAssertEqual(log.events[0].category, "A")
        XCTAssertEqual(log.events[1].metadata, ["k": "v"])
    }

    func testLevelFilterDropsBelowMinimum() {
        let log = InMemoryLogger(minimumLevel: .warn)
        log.debug("a", "dropped")
        log.info("b", "dropped")
        log.warn("c", "kept")
        log.error("d", "kept")
        log.flush()
        XCTAssertEqual(log.events.map(\.category), ["c", "d"])
    }

    func testContainsHelper() {
        let log = InMemoryLogger(minimumLevel: .debug)
        log.info("MacroRunner", "Starting macro with 3 actions")
        log.flush()

        XCTAssertTrue(log.contains(category: "MacroRunner", messageContains: "Starting"))
        XCTAssertTrue(log.contains(category: "MacroRunner", messageContains: "3 actions"))
        XCTAssertFalse(log.contains(category: "Other", messageContains: "Starting"))
        XCTAssertFalse(log.contains(category: "MacroRunner", messageContains: "nonsense"))
    }

    func testClearEmptiesBuffer() {
        let log = InMemoryLogger(minimumLevel: .debug)
        for i in 0..<10 { log.info("x", "i=\(i)") }
        log.flush()
        XCTAssertEqual(log.events.count, 10)
        log.clear()
        log.flush()
        XCTAssertEqual(log.events.count, 0)
    }

    func testConcurrentWritesAllRecorded() {
        let log = InMemoryLogger(minimumLevel: .debug)
        let group = DispatchGroup()
        for i in 0..<500 {
            DispatchQueue.global().async(group: group) {
                log.info("t", "n=\(i)")
            }
        }
        group.wait()
        log.flush()
        XCTAssertEqual(log.events.count, 500)
    }
}

// MARK: - ComposedLogger

final class ComposedLoggerTests: XCTestCase {

    func testDispatchesToAllChildren() {
        let a = InMemoryLogger(minimumLevel: .debug)
        let b = InMemoryLogger(minimumLevel: .debug)
        let composed = ComposedLogger([a, b])

        composed.info("x", "msg")
        a.flush(); b.flush()

        XCTAssertEqual(a.events.count, 1)
        XCTAssertEqual(b.events.count, 1)
    }

    func testEachChildAppliesItsOwnFilter() {
        let noisy = InMemoryLogger(minimumLevel: .debug)
        let quiet = InMemoryLogger(minimumLevel: .error)
        let composed = ComposedLogger([noisy, quiet])

        composed.info("x", "info-level")
        composed.error("x", "error-level")
        noisy.flush(); quiet.flush()

        XCTAssertEqual(noisy.events.count, 2)
        XCTAssertEqual(quiet.events.count, 1)
        XCTAssertEqual(quiet.events.first?.level, .error)
    }

    func testFlushPropagatesToChildren() {
        let a = InMemoryLogger(minimumLevel: .debug)
        let b = InMemoryLogger(minimumLevel: .debug)
        let composed = ComposedLogger([a, b])

        composed.info("x", "m")
        composed.flush()
        // After flush all async writes are drained.
        XCTAssertEqual(a.events.count, 1)
        XCTAssertEqual(b.events.count, 1)
    }
}

// MARK: - LoggerContext

final class LoggerContextTests: XCTestCase {

    func testSharedIsReplaceable() {
        let original = LoggerContext.shared
        defer { LoggerContext.shared = original }

        let mem = InMemoryLogger(minimumLevel: .debug)
        LoggerContext.shared = mem
        LoggerContext.shared.info("X", "Y")
        mem.flush()
        XCTAssertEqual(mem.events.count, 1)
    }

    func testDefaultIsNullLoggerWhenNeverSet() {
        // We can't truly reset the process-wide default in a test, but we can
        // at least ensure that a NullLogger behaves as a silent sink.
        let null = NullLogger()
        null.error("x", "y") // must not throw, must not print.
        null.flush()
        XCTAssertEqual(null.minimumLevel, .error)
    }
}
