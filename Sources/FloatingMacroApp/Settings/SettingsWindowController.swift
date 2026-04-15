import AppKit
import SwiftUI

/// Manages the lifetime of the single Settings window. A .accessory app has
/// no standard window menu, so we keep the window ourselves and reuse it
/// across shows.
final class SettingsWindowController: NSWindowController {

    static let shared = SettingsWindowController()

    func show(presetManager: PresetManager, selectButtonId: String? = nil) {
        if window == nil {
            let hosting = NSHostingView(
                rootView: SettingsView(presetManager: presetManager)
            )
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 820, height: 540),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            w.title = "FloatingMacro ボタン編集"
            w.contentView = hosting
            w.center()
            w.isReleasedWhenClosed = false
            self.window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)

        // Ask SettingsView to jump to this button after the window mounts.
        if let id = selectButtonId {
            DispatchQueue.main.async {
                presetManager.externalSelectButtonRequest = id
            }
        }
    }
}
