import Foundation

/// A single structured log record.
///
/// Serialized as a one-line JSON object. Example:
/// ```json
/// {"timestamp":"2026-04-16T00:30:00.123Z","level":"info","category":"MacroRunner","message":"Starting macro","metadata":{"count":"3"}}
/// ```
public struct LogEvent: Codable, Equatable {
    /// Wall-clock time the event was generated.
    public let timestamp: Date

    /// Severity.
    public let level: LogLevel

    /// Short subsystem name — e.g. "MacroRunner", "TextAction", "ConfigLoader".
    public let category: String

    /// Human-readable English description of the event.
    public let message: String

    /// Optional structured key/value fields. Values are stringified upstream
    /// so the on-disk representation is stable even if the caller passes in
    /// heterogeneous types. An empty dictionary is encoded as `null` to keep
    /// lines compact.
    public let metadata: [String: String]?

    public init(timestamp: Date = Date(),
                level: LogLevel,
                category: String,
                message: String,
                metadata: [String: String]? = nil) {
        self.timestamp = timestamp
        self.level = level
        self.category = category
        self.message = message
        // Normalize empty dicts to nil so the JSON stays compact.
        if let m = metadata, m.isEmpty {
            self.metadata = nil
        } else {
            self.metadata = metadata
        }
    }
}

extension JSONEncoder {
    /// Shared encoder used for on-disk log lines.
    /// ISO 8601 timestamps with fractional seconds; sorted keys for stable diffs.
    public static let fmLogEncoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        enc.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(LogEvent.isoFormatter.string(from: date))
        }
        return enc
    }()
}

extension JSONDecoder {
    /// Shared decoder for reading log lines back (useful in tests).
    public static let fmLogDecoder: JSONDecoder = {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
            if let d = LogEvent.isoFormatter.date(from: str) {
                return d
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "invalid ISO8601 timestamp: \(str)"
            )
        }
        return dec
    }()
}

extension LogEvent {
    /// Shared ISO 8601 formatter with fractional seconds and UTC.
    fileprivate static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
