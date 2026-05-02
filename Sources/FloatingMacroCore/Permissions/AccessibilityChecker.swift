import ApplicationServices
import AppKit

public enum AccessibilityChecker {
    /// True iff this process is currently allowed to use the Accessibility
    /// API (which is what gates `CGEvent.post`).
    ///
    /// Detection is layered to avoid both directions of false positive:
    ///
    ///   1. **AXIsProcessTrusted()** — the system's official check. Reliable
    ///      when it returns false (no caching issue in that direction). Has
    ///      a known issue of returning a stale TRUE for some time after a
    ///      silent revocation, so we cannot trust true-results blindly.
    ///
    ///   2. **AX probe** — try to read kAXFocusedApplicationAttribute from
    ///      the system-wide element. If THIS specifically returns
    ///      `.apiDisabled`, the AX API is genuinely off for our process —
    ///      this is the only signal that overrides the cache.
    ///
    ///      Other AX error codes (`.noValue`, `.attributeUnsupported`,
    ///      `.cannotComplete`, etc.) do NOT mean we lack permission — they
    ///      just mean the currently-focused app can't be queried (which
    ///      happens routinely with sandboxed apps, login window, screen
    ///      saver, Spotlight, etc.). Earlier this probe treated all
    ///      non-success values as "untrusted" and produced ~3 sec of
    ///      false-positive flicker every time the focused app changed.
    ///
    /// Decision matrix:
    ///
    ///   AXIsProcessTrusted | AX probe        | result
    ///   -------------------|-----------------|-------
    ///   false              | (skipped)       | false
    ///   true               | success         | true
    ///   true               | apiDisabled     | false  ← real revoke
    ///   true               | other error     | true   ← transient, ignore
    public static func isTrusted(prompt: Bool = false) -> Bool {
        if prompt {
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(opts)
        }

        if !AXIsProcessTrusted() {
            return false
        }

        let systemWide = AXUIElementCreateSystemWide()
        var value: AnyObject?
        let err = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedApplicationAttribute as CFString,
            &value
        )
        return err != .apiDisabled
    }

    public static func openSystemPreferences() {
        let log = LoggerContext.shared
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

        // NSWorkspace.shared.open(url) は System Settings が未起動だと
        // Sequoia 上で silent fail することがある (URL イベントを受ける
        // プロセスが居ないとイベントがドロップされる挙動が観測されている)。
        // /usr/bin/open は LaunchServices 経由で確実に起動 + URL 配送を
        // 行うため、こちらを使う。
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = [url.absoluteString]
        do {
            try task.run()
            log.info("Accessibility", "openSystemPreferences invoked", ["url": url.absoluteString])
        } catch {
            log.error("Accessibility", "openSystemPreferences failed", [
                "url": url.absoluteString,
                "error": String(describing: error),
            ])
            // 最終手段として NSWorkspace 経由
            NSWorkspace.shared.open(url)
        }
    }
}
