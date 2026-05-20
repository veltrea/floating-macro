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

/// NSTextView subclass that draws a fat, vivid insertion point. The
/// default 1-pixel system caret is essentially invisible in scaled-down
/// PNG screenshots — a 4-pixel red bar shows up clearly even at half
/// resolution, so screenshot reviews can confirm cursor position by eye
/// (the script already verifies it numerically via /selection, but a
/// human-readable PNG is invaluable when something behaves unexpectedly).
@MainActor
final class VisibleCaretTextView: NSTextView {
    override func drawInsertionPoint(in rect: NSRect,
                                     color: NSColor,
                                     turnedOn flag: Bool) {
        guard flag else {
            super.drawInsertionPoint(in: rect, color: color, turnedOn: flag)
            return
        }
        let fat = NSRect(x: rect.origin.x, y: rect.origin.y,
                         width: max(4, rect.size.width),
                         height: rect.size.height)
        NSColor.systemRed.setFill()
        fat.fill()
    }
}

@MainActor
final class TestTargetDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var textView: VisibleCaretTextView!
    private var keyLogView: NSTextView!     // visible feed of every keyDown
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
        // Window is taller now to accommodate a visible key-event log
        // beneath the paste-target text view. The split lets a human eye
        // confirm "the F5 / arrow / Cmd+A keystroke arrived" without
        // having to read /events JSON in a second terminal.
        let frame = NSRect(x: 200, y: 200, width: 560, height: 480)
        let style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
        window = NSWindow(contentRect: frame, styleMask: style, backing: .buffered, defer: false)
        window.title = "fm-test-target :\(port)"
        window.isReleasedWhenClosed = false

        let container = NSView(frame: NSRect(origin: .zero, size: frame.size))
        container.autoresizingMask = [.width, .height]

        // ── Top half: paste target (editable text view) ──────────────
        let topHeight: CGFloat = 280
        let topFrame  = NSRect(x: 0, y: frame.height - topHeight, width: frame.width, height: topHeight)
        let topScroll = NSScrollView(frame: topFrame)
        topScroll.hasVerticalScroller = true
        topScroll.autoresizingMask = [.width, .minYMargin]
        topScroll.borderType = .lineBorder

        let tv = VisibleCaretTextView(frame: topFrame)
        tv.insertionPointColor = .systemRed
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
            width: topScroll.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        tv.textContainer?.widthTracksTextView = true
        topScroll.documentView = tv
        textView = tv

        // ── Header label between the two panes ──────────────────────
        let labelHeight: CGFloat = 22
        let labelFrame = NSRect(x: 8, y: frame.height - topHeight - labelHeight,
                                width: frame.width - 16, height: labelHeight)
        let label = NSTextField(labelWithString: "Key events  (keyCode  mods  chars)")
        label.frame = labelFrame
        label.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.autoresizingMask = [.width, .minYMargin]

        // ── Bottom half: key-event log (read-only) ───────────────────
        let bottomFrame = NSRect(x: 0, y: 0, width: frame.width,
                                 height: frame.height - topHeight - labelHeight)
        let bottomScroll = NSScrollView(frame: bottomFrame)
        bottomScroll.hasVerticalScroller = true
        bottomScroll.autoresizingMask = [.width, .height]
        bottomScroll.borderType = .lineBorder

        let kv = NSTextView(frame: bottomFrame)
        kv.isEditable = false
        kv.isSelectable = true
        kv.isRichText = false
        kv.font = NSFont.userFixedPitchFont(ofSize: 11) ?? NSFont.systemFont(ofSize: 11)
        kv.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.6)
        kv.autoresizingMask = [.width]
        kv.minSize = NSSize(width: 0, height: 0)
        kv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                            height: CGFloat.greatestFiniteMagnitude)
        kv.isVerticallyResizable = true
        kv.isHorizontallyResizable = false
        kv.textContainer?.containerSize = NSSize(
            width: bottomScroll.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        kv.textContainer?.widthTracksTextView = true
        bottomScroll.documentView = kv
        keyLogView = kv

        container.addSubview(topScroll)
        container.addSubview(label)
        container.addSubview(bottomScroll)
        window.contentView = container
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
            let rec = RecordedKeyEvent(
                timestampMs: elapsed,
                keyCode: Int(ev.keyCode),
                characters: ev.characters ?? "",
                charactersIgnoringModifiers: ev.charactersIgnoringModifiers ?? "",
                modifierFlags: ev.modifierFlags.rawValue,
                isARepeat: ev.isARepeat
            )
            self.events.append(rec)
            self.appendKeyLogLine(rec)
            return ev
        }
    }

    /// Render one keyDown into the visible event log. The format is fixed
    /// width so a human can scan it: e.g.
    ///   `[ 1234 ms]  kc=96    mods=----  chars="" name=F5`
    /// Modifier flags use the standard mask bits:
    ///   shift 0x20000 / ctrl 0x40000 / option 0x80000 / cmd 0x100000.
    private func appendKeyLogLine(_ e: RecordedKeyEvent) {
        let mods = e.modifierFlags
        let modStr =
            ((mods & 0x100000) != 0 ? "⌘" : "-") +
            ((mods & 0x80000)  != 0 ? "⌥" : "-") +
            ((mods & 0x40000)  != 0 ? "⌃" : "-") +
            ((mods & 0x20000)  != 0 ? "⇧" : "-")
        let name = friendlyKeyName(keyCode: e.keyCode,
                                   chars: e.charactersIgnoringModifiers)
        let line = String(
            format: "[%6d ms]  kc=%-3d  mods=%@  chars=%@  name=%@\n",
            e.timestampMs, e.keyCode, modStr,
            quotedASCII(e.characters), name
        )
        guard let storage = keyLogView.textStorage else { return }
        let attr = NSAttributedString(
            string: line,
            attributes: [
                .font: keyLogView.font ?? NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.labelColor
            ]
        )
        storage.append(attr)
        keyLogView.scrollRangeToVisible(NSRange(location: storage.length, length: 0))
    }

    /// Quote a string so non-printables don't garble the log line.
    private func quotedASCII(_ s: String) -> String {
        if s.isEmpty { return "\"\"" }
        var out = "\""
        for ch in s.unicodeScalars {
            if ch.value < 0x20 || ch.value == 0x7f {
                out += String(format: "\\x%02x", ch.value)
            } else {
                out += String(ch)
            }
        }
        out += "\""
        return out
    }

    /// Map common virtual keyCodes to human-readable names. Anything not
    /// in this table falls back to charactersIgnoringModifiers, so letter
    /// keys still display as "a", "b" etc.
    private func friendlyKeyName(keyCode: Int, chars: String) -> String {
        switch keyCode {
        case 0x7A: return "F1"
        case 0x78: return "F2"
        case 0x63: return "F3"
        case 0x76: return "F4"
        case 0x60: return "F5"
        case 0x61: return "F6"
        case 0x62: return "F7"
        case 0x64: return "F8"
        case 0x65: return "F9"
        case 0x6D: return "F10"
        case 0x67: return "F11"
        case 0x6F: return "F12"
        case 0x69: return "F13"
        case 0x6B: return "F14"
        case 0x71: return "F15"
        case 0x7B: return "Left"
        case 0x7C: return "Right"
        case 0x7D: return "Down"
        case 0x7E: return "Up"
        case 0x33: return "Delete"
        case 0x75: return "ForwardDelete"
        case 0x35: return "Escape"
        case 0x24: return "Return"
        case 0x4C: return "Enter"
        case 0x30: return "Tab"
        case 0x31: return "Space"
        case 0x73: return "Home"
        case 0x77: return "End"
        case 0x74: return "PageUp"
        case 0x79: return "PageDown"
        default:
            return chars.isEmpty ? "?" : chars
        }
    }

    // MARK: - HTTP server

    private func startServer() {
        // We capture `self` weakly through a wrapper closure so that
        // ControlServer's background queue can call into MainActor for
        // every request without retain cycles.
        let handlers = TestTargetHandlers(
            getText:      { [weak self] in self?.currentText() ?? "" },
            clearText:    { [weak self] in self?.clearText() },
            focus:        { [weak self] in self?.focusWindow() },
            getEvents:    { [weak self] in self?.snapshotEvents() ?? [] },
            clearEvents:  { [weak self] in self?.clearEvents() },
            getSelection: { [weak self] in self?.currentSelection() ?? (0, 0) },
            quit:         { NSApp.terminate(nil) }
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
            self.keyLogView.textStorage?.mutableString.setString("")
        }
    }

    /// Snapshot the text view's selection range. NSTextView always has a
    /// selection — it's a zero-length range when only the caret is shown.
    /// Useful for tests that check cursor movement (arrow keys) and
    /// selection state (cmd+A).
    fileprivate func currentSelection() -> (location: Int, length: Int) {
        var loc = 0
        var len = 0
        DispatchQueue.main.sync {
            let r = self.textView.selectedRange()
            loc = r.location
            len = r.length
        }
        return (loc, len)
    }
}
