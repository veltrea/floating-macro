import Foundation

/// Human-readable logger that prints to stderr. Intended for the CLI
/// (`fmcli`) so that structured on-disk logs coexist with a readable
/// tail in the terminal.
///
/// Output format:
/// ```
/// 2026-04-16T00:30:00.123Z INFO  MacroRunner  Starting macro  count=3
/// ```
public final class ConsoleLogWriter: FMLogger {
    public let minimumLevel: LogLevel
    private let queue = DispatchQueue(label: "fm.consolelog")
    private let stream: FileHandle

    public init(minimumLevel: LogLevel = .info,
                stream: FileHandle = .standardError) {
        self.minimumLevel = minimumLevel
        self.stream = stream
    }

    public func log(_ event: LogEvent) {
        guard event.level >= minimumLevel else { return }
        queue.async { [weak self] in
            guard let self else { return }
            let line = Self.formatLine(event)
            if let data = (line + "\n").data(using: .utf8) {
                try? self.stream.write(contentsOf: data)
            }
        }
    }

    public func flush() {
        queue.sync {}
    }

    /// Exposed for testing.
    public static func formatLine(_ event: LogEvent) -> String {
        let ts = isoFormatter.string(from: event.timestamp)
        let level = event.level.rawValue.uppercased().padding(toLength: 5, withPad: " ", startingAt: 0)
        var line = "\(ts) \(level) \(event.category)  \(event.message)"
        if let metadata = event.metadata, !metadata.isEmpty {
            let kvs = metadata
                .sorted(by: { $0.key < $1.key })
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: " ")
            line += "  " + kvs
        }
        return line
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
