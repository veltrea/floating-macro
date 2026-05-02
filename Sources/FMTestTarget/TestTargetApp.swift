import AppKit
import Foundation
import FloatingMacroCore

/// Recorded keyboard event. Stored in the order received so tests can
/// reason about modifiers and timing of Cmd+V (or any other combo).
struct RecordedKeyEvent: Codable {
    let timestampMs: Int       // ms since process launch
    let keyCode: Int
    let characters: String     // empty if none
    let charactersIgnoringModifiers: String
    let modifierFlags: UInt    // raw NSEvent.ModifierFlags rawValue
    let isARepeat: Bool
}

@MainActor
final class TestTargetDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var textView: NSTextView!
    private var server: ControlServer!
    private var keyMonitor: Any?
    private let launchDate = Date()
    private var events: [RecordedKeyEvent] = []
    private let port: UInt16

    override init() {
        // Allow override via FM_TEST_TARGET_PORT for parallel runs.
        if let v = ProcessInfo.processInfo.environment["FM_TEST_TARGET_PORT"],
           let n = UInt16(v) {
            self.port = n
        } else {
            self.port = 17431
        }
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenuBar()
        buildWindow()
        startKeyMonitor()
        startServer()
        // Bring ourselves forward immediately so the first request after
        // launch doesn't race with focus acquisition.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(textView)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    // MARK: - UI

    private func buildWindow() {
        let frame = NSRect(x: 200, y: 200, width: 520, height: 320)
        let style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
        window = NSWindow(contentRect: frame, styleMask: style, backing: .buffered, defer: false)
        window.title = "fm-test-target :\(port)"
        window.isReleasedWhenClosed = false

        let scroll = NSScrollView(frame: frame)
        scroll.hasVerticalScroller = true
        scroll.autoresizingMask = [.width, .height]

        let tv = NSTextView(frame: frame)
        tv.isEditable = true
        tv.isRichText = false                  // CRITICAL: plain text only
        tv.usesFontPanel = false
        tv.allowsUndo = true
        // Disable every "smart" substitution that would mutate pasted text
        // and cause false diff failures.
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled  = false
        tv.isAutomaticTextReplacementEnabled   = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isAutomaticLinkDetectionEnabled     = false
        tv.isAutomaticDataDetectionEnabled     = false
        tv.smartInsertDeleteEnabled            = false
        tv.font = NSFont.userFixedPitchFont(ofSize: 13) ?? NSFont.systemFont(ofSize: 13)
        tv.autoresizingMask = [.width]
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                            height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.textContainer?.containerSize = NSSize(
            width: scroll.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        tv.textContainer?.widthTracksTextView = true

        scroll.documentView = tv
        window.contentView = scroll
        textView = tv
    }

    /// NSTextView's `paste:` is wired through the responder chain, which
    /// requires a menu bar with an Edit > Paste item that has Cmd+V as its
    /// key equivalent. Without this, NSApp swallows Cmd+V before it ever
    /// reaches the text view, and the harness silently records no paste.
    private func installMenuBar() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit fm-test-target",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut",   action: #selector(NSText.cut(_:)),   keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy",  action: #selector(NSText.copy(_:)),  keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }

    private func startKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] ev in
            guard let self else { return ev }
            let elapsed = Int(Date().timeIntervalSince(self.launchDate) * 1000)
            self.events.append(RecordedKeyEvent(
                timestampMs: elapsed,
                keyCode: Int(ev.keyCode),
                characters: ev.characters ?? "",
                charactersIgnoringModifiers: ev.charactersIgnoringModifiers ?? "",
                modifierFlags: ev.modifierFlags.rawValue,
                isARepeat: ev.isARepeat
            ))
            return ev
        }
    }

    // MARK: - HTTP server

    private func startServer() {
        // We capture `self` weakly through a wrapper closure so that
        // ControlServer's background queue can call into MainActor for
        // every request without retain cycles.
        let handlers = TestTargetHandlers(
            getText:    { [weak self] in self?.currentText() ?? "" },
            clearText:  { [weak self] in self?.clearText() },
            focus:      { [weak self] in self?.focusWindow() },
            getEvents:  { [weak self] in self?.snapshotEvents() ?? [] },
            clearEvents:{ [weak self] in self?.clearEvents() },
            quit:       { NSApp.terminate(nil) }
        )

        server = ControlServer(preferredPort: port, maxPortProbes: 1) { req in
            handlers.dispatch(req)
        }
        switch server.start(timeout: 2.0) {
        case .success(let p):
            LoggerContext.shared.info("TestTarget", "HTTP listening", ["port": String(p)])
        case .failure(let err):
            LoggerContext.shared.error("TestTarget", "HTTP bind failed",
                                       ["port": String(port),
                                        "error": String(describing: err)])
            // Hard fail — without the API the harness is useless.
            fputs("fm-test-target: failed to bind \(port): \(err)\n", stderr)
            exit(2)
        }
    }

    // MARK: - State accessors used by handlers (always main-actor)

    fileprivate func currentText() -> String {
        var result = ""
        DispatchQueue.main.sync {
            result = self.textView.string
        }
        return result
    }

    fileprivate func clearText() {
        DispatchQueue.main.sync {
            self.textView.string = ""
        }
    }

    fileprivate func focusWindow() {
        DispatchQueue.main.sync {
            NSApp.activate(ignoringOtherApps: true)
            self.window.makeKeyAndOrderFront(nil)
            self.window.makeFirstResponder(self.textView)
        }
    }

    fileprivate func snapshotEvents() -> [RecordedKeyEvent] {
        var out: [RecordedKeyEvent] = []
        DispatchQueue.main.sync {
            out = self.events
        }
        return out
    }

    fileprivate func clearEvents() {
        DispatchQueue.main.sync {
            self.events.removeAll()
        }
    }
}
