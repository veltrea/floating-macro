import AppKit
import Foundation
import FloatingMacroCore

// fm-test-target — small native macOS harness used to verify that
// FloatingMacro's TextAction / KeyAction actually deliver characters and
// keystrokes to a real focused app. Exposes a tiny loopback HTTP API so
// shell scripts can drive the test (focus, clear, read).
//
// Why a dedicated app instead of TextEdit:
//   - TextEdit silently rewrites quotes / ellipses / dashes, producing
//     false negatives in diffs.
//   - TextEdit has no read API, so verification must go through AppleScript
//     which is itself a flake source.
//   - Here we own the responder chain and can also record raw NSEvents to
//     measure the paste-completion latency that defeats `pasteDelayMs`.

// `NSApplicationDelegate` is main-actor isolated under Swift 5.9 strict
// concurrency, so the `init()` itself crosses into MainActor. We hop
// onto the main queue once to construct everything, then call run().
let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { TestTargetDelegate() }
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
