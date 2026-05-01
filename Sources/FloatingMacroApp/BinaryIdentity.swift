import Foundation
import CryptoKit
import FloatingMacroCore

/// Detects "this is a different binary than last time we ran" and
/// auto-resets the TCC Accessibility entry so macOS treats the new
/// build as a fresh app.
///
/// Why this exists:
///   - macOS auto-applies `com.apple.provenance` xattr to every app it
///     opens. There is no way to prevent it (verified: stripping it via
///     `xattr -d` results in immediate re-application by LaunchServices).
///   - With provenance + ad-hoc signature (no TeamIdentifier), macOS's
///     TCC daemon revalidates the app's identity periodically and after
///     hash changes. When validation fails, the previously-granted
///     Accessibility permission is **silently revoked** while still
///     visually present in the System Settings list.
///   - The recorded TCC entry is keyed on the old hash, so even toggling
///     the visible switch ON/OFF doesn't fix it — the entry is "stuck"
///     until removed via `tccutil reset` (or the manual `−` button).
///
/// What this does:
///   - On every launch, compute SHA-256 of our executable.
///   - Compare against the hash recorded in
///     `~/Library/Application Support/FloatingMacro/last_binary_hash.txt`.
///   - If they differ AND we have a recorded prior hash (i.e. not the
///     very first run on this Mac), invoke `tccutil reset Accessibility`
///     for our bundle id. The next AX call will then trigger a clean
///     "app has not been granted permission" state, the panel badge
///     appears, and one click + drag re-grants permission cleanly.
///   - Persist the new hash so we only do this once per binary change.
enum BinaryIdentity {
    private static let category = "BinaryIdentity"
    private static var stateURL: URL {
        ConfigLoader.defaultBaseURL
            .appendingPathComponent("last_binary_hash.txt")
    }

    /// Returns SHA-256 of this process's executable as lowercase hex.
    /// Returns nil only if the executable can't be located/read — which
    /// would mean something is so wrong startup is doomed anyway.
    static func currentExecutableHash() -> String? {
        guard let url = Bundle.main.executableURL,
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Returns the hash recorded on the previous successful run, or nil
    /// if no record exists (first run on this user's machine, or the
    /// state file was deleted).
    static func lastKnownHash() -> String? {
        guard let s = try? String(contentsOf: stateURL, encoding: .utf8) else {
            return nil
        }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Persists `hash` for next-launch comparison. Best-effort — failing
    /// to write just means we'll redundantly reset next time, which is
    /// harmless.
    static func recordCurrent(hash: String) {
        // Ensure the directory exists; ConfigLoader normally takes care
        // of this but we run BEFORE PresetManager initializes.
        try? FileManager.default.createDirectory(
            at: ConfigLoader.defaultBaseURL,
            withIntermediateDirectories: true
        )
        try? hash.write(to: stateURL, atomically: true, encoding: .utf8)
    }

    /// Run the full check + (conditional) reset. Call this very early in
    /// `applicationDidFinishLaunching` — before any AX-gated code path,
    /// so the reset (if needed) happens before AccessibilityChecker
    /// caches a "trusted" state.
    static func handleStartupCheck(bundleId: String) {
        let log = LoggerContext.shared
        guard let current = currentExecutableHash() else {
            log.warn(category, "could not hash executable — skipping check")
            return
        }
        let last = lastKnownHash()

        // Always record the current hash, even on first run, so we have
        // a baseline for the next launch.
        defer { recordCurrent(hash: current) }

        guard let last = last else {
            log.info(category, "first run on this machine", ["hash": String(current.prefix(12))])
            return
        }

        if last == current {
            log.debug(category, "binary unchanged since last run")
            return
        }

        log.info(category, "binary changed — resetting TCC entry to avoid stale-trust silent revoke", [
            "from":     String(last.prefix(12)),
            "to":       String(current.prefix(12)),
            "bundleId": bundleId,
        ])
        TCCResetter.resetAccessibility(bundleId: bundleId)
    }
}

/// Wraps `tccutil reset` for use from the app process. tccutil requires
/// no special privilege (no sudo) for resetting our own bundle id's
/// permissions, and only touches THIS bundle id's TCC records — other
/// apps' permissions are untouched.
enum TCCResetter {
    private static let category = "TCCResetter"

    /// Synchronously runs `tccutil reset Accessibility <bundleId>`.
    /// Returns true on tccutil exit code 0, false otherwise.
    @discardableResult
    static func resetAccessibility(bundleId: String) -> Bool {
        let log = LoggerContext.shared
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "Accessibility", bundleId]
        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = outPipe
        do {
            try process.run()
            process.waitUntilExit()
            let outputData = outPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8) ?? ""
            let ok = process.terminationStatus == 0
            log.info(category, ok ? "reset succeeded" : "reset failed", [
                "bundleId":  bundleId,
                "exit":      String(process.terminationStatus),
                "output":    output.trimmingCharacters(in: .whitespacesAndNewlines),
            ])
            return ok
        } catch {
            log.error(category, "tccutil failed to launch", [
                "bundleId": bundleId,
                "error":    String(describing: error),
            ])
            return false
        }
    }
}
