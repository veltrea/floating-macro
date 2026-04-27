import AppKit

// SwiftUI @main App struct を使わず AppDelegate で直接起動することで、
// SwiftUI のウィンドウ自動復元（Settings シーンの再表示など）を防ぐ。
let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApp.run()
