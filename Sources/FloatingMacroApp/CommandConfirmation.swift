import AppKit
import CryptoKit
import Foundation

/// Presents a confirmation sheet when a command matches a blacklist pattern,
/// and provides password-hashing utilities for the autopilot guard.
enum CommandConfirmation {

    // MARK: - Execution confirmation dialog

    /// Shows a modal warning dialog asking the user whether to proceed.
    ///
    /// Must be called on the main actor. Returns `true` if the user chose to
    /// proceed, `false` if they cancelled.
    @MainActor
    static func askProceed(pattern: String, text: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = L("Dangerous command detected: fabe0f")
        let preview = text.count > 150
            ? String(text.prefix(150)).appending("…")
            : text
        alert.informativeText = """
            Disallowed pattern 「\(pattern)」includes.

            \(preview)

            Are you sure?？
            """
        alert.alertStyle = .warning
        // First button is the default (Return key), so make it the safe action.
        alert.addButton(withTitle: L("Cancel 6ef349"))
        alert.addButton(withTitle: L("Running 484791"))
        return alert.runModal() == .alertSecondButtonReturn
    }

    // MARK: - Password utilities

    /// Returns the SHA-256 hex digest of the given passphrase.
    static func hash(_ passphrase: String) -> String {
        let data = Data(passphrase.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Returns `true` when the passphrase matches the stored hash.
    static func verify(passphrase: String, against storedHash: String) -> Bool {
        hash(passphrase) == storedHash
    }

    // MARK: - Autopilot password prompt

    /// Shows a modal dialog with a secure text field so the user can enter
    /// the autopilot passphrase. Returns the entered string, or `nil` if the
    /// user cancelled.
    @MainActor
    static func promptPassphrase(title: String, message: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: L("Confirm 30749e"))
        alert.addButton(withTitle: L("Cancel 6ef349"))

        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.placeholderString = L("Password_4bdfe7")
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return nil }
        return field.stringValue
    }
}
