import AppKit
import SwiftUI
import FloatingMacroCore

/// Manages the lifetime of the single Settings window. A .accessory app has
/// no standard window menu, so we keep the window ourselves and reuse it
/// across shows.
///
/// Rather than relying on `NSWindowDelegate`, which in practice gets
/// reset/hijacked by `NSWindowController` and SwiftUI's `NSHostingView`
/// (we verified via logs that `windowShouldClose` was never called), we
/// listen for `NSWindow.willCloseNotification` on NotificationCenter. That
/// channel can't be lost to delegate swaps. When it fires for OUR window,
/// we re-surface the floating panel so the accessory-app stays visible in
/// the menu bar + panel, Google Drive style.
final class SettingsWindowController: NSWindowController {

    static let shared = SettingsWindowController()

    private var willCloseObserver: NSObjectProtocol?

    func show(presetManager: PresetManager, selectButtonId: String? = nil, selectGroupId: String? = nil) {
        if window == nil {
            let hosting = NSHostingView(
                rootView: SettingsView(presetManager: presetManager)
            )
            // Use the SettingsWindow subclass so the red ×, ⌘W, and
            // AppleScript AXCloseButton presses all route through our
            // overridden performClose(_:) and hide the window instead of
            // closing it.
            let w = SettingsWindow(
                contentRect: NSRect(x: 0, y: 0, width: 820, height: 680),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            w.title = "FloatingMacro ボタン編集"
            w.contentView = hosting
            w.setFrameAutosaveName("SettingsWindow")
            // setFrameAutosaveName restores the last saved frame if one
            // exists; only center the window on the very first launch.
            if !w.setFrameUsingName("SettingsWindow") {
                w.center()
            }
            w.isReleasedWhenClosed = false
            self.window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)

        // Ask SettingsView to jump to this button/group after the window mounts.
        if let id = selectButtonId {
            DispatchQueue.main.async {
                presetManager.externalSelectButtonRequest = id
            }
        }
        if let id = selectGroupId {
            DispatchQueue.main.async {
                presetManager.externalSelectGroupRequest = id
            }
        }
    }

    deinit {
        if let o = willCloseObserver {
            NotificationCenter.default.removeObserver(o)
        }
    }
}
