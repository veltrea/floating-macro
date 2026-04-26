import Foundation

/// Checks a command string or pasted text against a `CommandBlacklist` before
/// execution. Used by both `MacroRunner` and direct action dispatch paths.
public enum CommandGuard {

    /// Returns the first matching forbidden pattern if the text should be
    /// blocked, or `nil` if execution is permitted.
    ///
    /// Matching is case-insensitive substring search so that both
    /// `rm -rf /` and `RM -RF /` are caught.
    public static func check(_ text: String, against blacklist: CommandBlacklist) -> String? {
        guard blacklist.enabled else { return nil }
        let lower = text.lowercased()
        for pattern in blacklist.patterns where !pattern.isEmpty {
            if lower.contains(pattern.lowercased()) {
                return pattern
            }
        }
        return nil
    }
}
