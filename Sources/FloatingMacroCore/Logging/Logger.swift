import Foundation

/// Abstract sink for structured log events.
///
/// Implementations are expected to be **thread-safe** — `log(_:)` may be called
/// from any queue or task.
///
/// Level filtering is expressed via `minimumLevel`: events strictly lower than
/// the minimum are dropped before any expensive serialization happens.
public protocol FMLogger: AnyObject {
    var minimumLevel: LogLevel { get }
    func log(_ event: LogEvent)
    /// Optional: flush buffered output. No-op by default.
    func flush()
}

public extension FMLogger {
    func flush() { /* no-op */ }

    /// Convenience: emit an event only if its level passes the minimum filter.
    /// Callers should prefer the `debug/info/warn/error` helpers below.
    func emit(_ level: LogLevel,
              _ category: String,
              _ message: String,
              _ metadata: [String: String] = [:]) {
        guard level >= minimumLevel else { return }
        log(LogEvent(
            timestamp: Date(),
            level: level,
            category: category,
            message: message,
            metadata: metadata.isEmpty ? nil : metadata
        ))
    }

    func debug(_ category: String, _ message: String, _ metadata: [String: String] = [:]) {
        emit(.debug, category, message, metadata)
    }
    func info(_ category: String, _ message: String, _ metadata: [String: String] = [:]) {
        emit(.info, category, message, metadata)
    }
    func warn(_ category: String, _ message: String, _ metadata: [String: String] = [:]) {
        emit(.warn, category, message, metadata)
    }
    func error(_ category: String, _ message: String, _ metadata: [String: String] = [:]) {
        emit(.error, category, message, metadata)
    }
}

// MARK: - Null Logger

/// Drops every event. Used as the process-wide default so normal unit tests
/// and CLI invocations don't accidentally write to disk.
public final class NullLogger: FMLogger {
    public let minimumLevel: LogLevel = .error
    public init() {}
    public func log(_ event: LogEvent) { /* drop */ }
}

// MARK: - In-Memory Logger (tests)

/// Buffers events in memory. Useful for assertions in tests:
/// ```
/// let log = InMemoryLogger()
/// LoggerContext.shared = log
/// // ... exercise code ...
/// XCTAssertTrue(log.contains(category: "MacroRunner", message: "Starting"))
/// ```
public final class InMemoryLogger: FMLogger {
    public var minimumLevel: LogLevel
    private let queue = DispatchQueue(label: "fm.memlog", attributes: .concurrent)
    private var _events: [LogEvent] = []

    public init(minimumLevel: LogLevel = .debug) {
        self.minimumLevel = minimumLevel
    }

    public func log(_ event: LogEvent) {
        queue.async(flags: .barrier) { [weak self] in
            self?._events.append(event)
        }
    }

    public func flush() {
        // Block until writer queue drains.
        queue.sync(flags: .barrier) {}
    }

    /// Snapshot of recorded events (thread-safe).
    public var events: [LogEvent] {
        queue.sync { _events }
    }

    /// Convenience: does any event match the given category + substring?
    public func contains(category: String, messageContains: String) -> Bool {
        events.contains { $0.category == category && $0.message.contains(messageContains) }
    }

    public func clear() {
        queue.async(flags: .barrier) { [weak self] in
            self?._events.removeAll()
        }
    }
}

// MARK: - Composed Logger

/// Fans a single `log(_:)` call out to multiple downstream loggers.
/// Each downstream applies its OWN minimumLevel; this composite never drops.
public final class ComposedLogger: FMLogger {
    public let minimumLevel: LogLevel = .debug
    private let children: [FMLogger]

    public init(_ children: [FMLogger]) {
        self.children = children
    }

    public func log(_ event: LogEvent) {
        for child in children {
            guard event.level >= child.minimumLevel else { continue }
            child.log(event)
        }
    }

    public func flush() {
        for child in children {
            child.flush()
        }
    }
}

// MARK: - Global context

/// Process-wide logger handle. Tests swap this out with an `InMemoryLogger`;
/// production code sets it to a `FileLogWriter` (or a ComposedLogger that
/// combines file + stderr).
///
/// All defaults point at `NullLogger` so code that accidentally emits before
/// setup is harmless.
public enum LoggerContext {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _shared: FMLogger = NullLogger()

    public static var shared: FMLogger {
        get {
            lock.lock(); defer { lock.unlock() }
            return _shared
        }
        set {
            lock.lock(); defer { lock.unlock() }
            _shared = newValue
        }
    }
}
