import Foundation
import AppKit

/// Utilities for checking the macOS Automation permission required for sending
/// Apple Events (AppleScript) to other applications — most importantly
/// Terminal and iTerm.
///
/// Unlike Accessibility, there is no user-facing opt-in UI: macOS prompts the
/// user the first time an app tries to send an Apple Event to a given target.
/// Once denied, the only recovery is the "Privacy & Security → Automation"
/// pane in System Settings, which this type helps to open.
public enum AutomationChecker {

    /// Result of a permission probe.
    public enum PermissionStatus: Equatable {
        /// User has granted permission for this target.
        case authorized
        /// User has denied permission. Must be fixed in System Settings.
        case denied
        /// OS hasn't asked yet — the first real Apple Event will prompt.
        case notDetermined
        /// Target app isn't installed / not reachable.
        case targetUnavailable
    }

    /// Check whether this process is authorized to send Apple Events to the
    /// application identified by `bundleIdentifier` (e.g. "com.apple.Terminal",
    /// "com.googlecode.iterm2").
    ///
    /// - Parameters:
    ///   - bundleIdentifier: target app's bundle id.
    ///   - askUserIfNeeded: when true, triggers the system permission dialog
    ///     on the first call (subsequent calls return cached decision).
    ///     When false, returns `.notDetermined` instead of prompting.
    /// - Returns: current permission status.
    @available(macOS 10.14, *)
    public static func check(bundleIdentifier: String,
                             askUserIfNeeded: Bool = false) -> PermissionStatus {
        // Build an Apple Event descriptor addressed by bundle id.
        let target = NSAppleEventDescriptor(
            bundleIdentifier: bundleIdentifier
        )

        let status = AEDeterminePermissionToAutomateTarget(
            target.aeDesc,
            typeWildCard,
            typeWildCard,
            askUserIfNeeded
        )

        switch status {
        case noErr:
            return .authorized
        case OSStatus(errAEEventNotPermitted):
            return .denied
        case OSStatus(errAEEventWouldRequireUserConsent), -1744 /* procNotFound legacy */:
            return .notDetermined
        case OSStatus(procNotFound):
            return .targetUnavailable
        default:
            // Any other error (app not running, event descriptor malformed,
            // etc.) is reported as "not determined" so callers can retry.
            return .notDetermined
        }
    }

    /// Convenience: check if the given target is authorized WITHOUT prompting.
    @available(macOS 10.14, *)
    public static func isAuthorized(bundleIdentifier: String) -> Bool {
        check(bundleIdentifier: bundleIdentifier, askUserIfNeeded: false) == .authorized
    }

    /// Open the "Privacy & Security → Automation" pane of System Settings so
    /// the user can grant / revoke permissions.
    public static func openSystemPreferences() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!
        NSWorkspace.shared.open(url)
    }

    /// Well-known terminal bundle identifiers used across the project.
    public enum KnownTarget {
        public static let terminalApp = "com.apple.Terminal"
        public static let iTerm       = "com.googlecode.iterm2"
    }
}
