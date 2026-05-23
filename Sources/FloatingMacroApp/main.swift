import AppKit

// Without using the @main App struct, launching directly from AppDelegate by making it a direct entry point.
// Prevent SwiftUI window auto-restoration (such as redisplaying scenes in Settings).
let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApp.run()
