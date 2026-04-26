import Foundation

public enum ActionError: Error, Equatable {
    case invalidKeyCombo(String)
    case accessibilityDenied
    case automationDenied(app: String)
    case launchTargetNotFound(String)
    case urlSchemeUnhandled(String)
    case clipboardAccessFailed
    case appleScriptFailed(message: String)
    case shellCommandFailed(exitCode: Int32, stderr: String)
    case nestedMacroNotAllowed
    /// Fired when a command or pasted text matches a pattern in `CommandBlacklist`.
    case commandBlocked(pattern: String)
}
