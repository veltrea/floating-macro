import AppKit

/// NSWindow subclass that refuses to actually close. The red ×, ⌘W, the
/// Window menu's Close item, and AppleScript's "AXCloseButton" press all
/// funnel through `performClose(_:)`, so overriding this single method
/// catches them all.
///
/// Why not just `windowShouldClose`? For an accessory app (`LSUIElement`)
/// hosting SwiftUI in `NSHostingView`, the `NSWindowDelegate` channel is
/// unreliable — experimentally, `windowShouldClose` is never fired for
/// this window (likely because `NSHostingView` owns the delegate). A
/// concrete subclass method cannot be intercepted the same way.
final class SettingsWindow: NSWindow {

    /// Called when the close button is clicked / ⌘W is pressed / etc.
    override func performClose(_ sender: Any?) {
        // Just hide. Don't go through the full close lifecycle, which in
        // an accessory app tends to take the floating panel with it.
        orderOut(nil)
        DispatchQueue.main.async {
            (NSApp.delegate as? AppDelegate)?.restoreFloatingPanel()
        }
    }
}
