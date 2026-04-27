import AppKit
import SwiftUI
import FloatingMacroCore

/// "AI 連携" ウィンドウのライフタイム管理。.accessory アプリは標準の
/// Window メニューを持たないため、ウィンドウは自前で保持して再利用する。
/// 設計は SettingsWindowController と同じパターン。
///
/// なぜ Settings と分けたか：
/// Settings は「ボタン編集」というオブジェクト単位の操作。一方、AI 連携は
/// アプリ全体に対する初期セットアップ。UI の粒度が違うものを同じウィンドウの
/// タブで並べるとメンタルモデルが分裂する（per-button vs app-wide の混在）。
final class AIIntegrationWindowController: NSWindowController {

    static let shared = AIIntegrationWindowController()

    func show(presetManager: PresetManager) {
        if window == nil {
            let hosting = NSHostingView(
                rootView: AIIntegrationView(presetManager: presetManager)
            )
            // Settings と同じ SettingsWindow サブクラスを再利用する。
            // × ボタンや ⌘W が performClose() に流れて、ウィンドウは閉じずに
            // 隠す挙動になる（.accessory アプリで close = release はまずい）。
            let w = SettingsWindow(
                contentRect: NSRect(x: 0, y: 0, width: 720, height: 800),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            w.title = "FloatingMacro AI 連携"
            w.contentView = hosting
            w.setFrameAutosaveName("AIIntegrationWindow")
            if !w.setFrameUsingName("AIIntegrationWindow") {
                w.center()
            }
            w.isReleasedWhenClosed = false
            w.hidesOnDeactivate = false
            self.window = w
        }

        // 一度 runloop を譲ってから activate する。コンテキストメニューや
        // 他のシートが完全に dismiss された後でないと activate が無視される。
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
