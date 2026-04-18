import Foundation

/// Log severity, ordered least-to-most severe.
/// Used for filtering: a logger with `minimumLevel: .warn` drops `.debug` and `.info`.
public enum LogLevel: String, Codable, CaseIterable, Comparable {
    case debug
    case info
    case warn
    case error

    /// Numeric severity. Higher = more severe.
    public var severity: Int {
        switch self {
        case .debug: return 0
        case .info:  return 1
        case .warn:  return 2
        case .error: return 3
        }
    }

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.severity < rhs.severity
    }

    /// Case-insensitive parse with a couple of common aliases.
    /// - "warn"/"warning" → .warn
    /// - "err"/"error"    → .error
    /// - unknown input    → nil
    public static func parse(_ raw: String) -> LogLevel? {
        switch raw.lowercased() {
        case "debug", "dbg":              return .debug
        case "info":                      return .info
        case "warn", "warning":           return .warn
        case "error", "err":              return .error
        default:                          return nil
        }
    }
}
