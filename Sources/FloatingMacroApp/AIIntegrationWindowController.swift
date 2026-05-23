import AppKit
import SwiftUI
import FloatingMacroCore

/// Window lifetime management for AI-assisted windows. The accessory app is standard.
/// Since the window menu is not provided, windows are self-managed and reused.
/// The design follows the same pattern as SettingsWindowController.
///
/// Why separate Settings:
/// Settings operates on object-level operations with the term "button editing." On the other hand, AI collaboration is...
/// Initial setup for the entire application. Different granularity of UI elements within the same window.
/// Tabbing causes mental models to split (mixing per-button vs. app-wide).
final class AIIntegrationWindowController: NSWindowController {

    static let shared = AIIntegrationWindowController()

    func show(presetManager: PresetManager) {
        if window == nil {
            let hosting = NSHostingView(
                rootView: AIIntegrationView(presetManager: presetManager)
            )
            // Reuse the same SettingsWindow subclass as Settings.
            // Button and ⌘W flow to performClose(), window does not close
            // The behavior will be hidden (close = release is dangerous in .accessory apps).
            let w = SettingsWindow(
                contentRect: NSRect(x: 0, y: 0, width: 720, height: 800),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            w.title = L("FloatingMacro_AI_Integration_330972")
            w.contentView = hosting
            w.setFrameAutosaveName("AIIntegrationWindow")
            if !w.setFrameUsingName("AIIntegrationWindow") {
                w.center()
            }
            w.isReleasedWhenClosed = false
            w.hidesOnDeactivate = false
            self.window = w
        }

        // Run the loop once and then activate it. Context menus, etc.
        // The activation is ignored unless the other sheets are completely dismissed.
        let win = window
        DispatchQueue.main.async {
            if #available(macOS 14.0, *) {
                NSApp.activate()
            } else {
                NSApp.activate(ignoringOtherApps: true)
            }
            win?.makeKeyAndOrderFront(nil)
        }
    }
}
