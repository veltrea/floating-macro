import AppKit
import ApplicationServices
import FloatingMacroCore

/// Programmatically presses a panel button by id by **synthesizing a real
/// mouse click at the button's screen position**. This is what makes the
/// Control API's `button_press` tool actually equivalent to a human click:
///
///   - Uses the macOS Accessibility tree to locate the button view (we set
///     `.accessibilityIdentifier("fm-button-<id>")` in `MacroButtonView`).
///   - Asks AX for the button's screen rect.
///   - Posts `leftMouseDown` + `leftMouseUp` CGEvents at the rect's center
///     via `.cghidEventTap`, which routes through the **same OS event
///     dispatch chain a real mouse click takes**: window manager → window
///     hit-test → SwiftUI gesture recognizer → Button.action.
///
/// What this catches that a direct `executeButton(button)` call cannot:
///   - Window obstruction (something on top of the panel)
///   - Disabled / .allowsHitTesting(false) buttons
///   - Broken hit-testing geometry (button drawn but not clickable)
///   - Panel not in the responder chain / not accepting mouse events
///   - SwiftUI Button gesture handler regressions
///
/// Side effects (intentional):
///   - The user sees the SwiftUI Button's native pressed visual state.
///   - The cursor is briefly moved to the button (so a human observer can
///     visually confirm the click). Original cursor position is restored.
enum ButtonClicker {
    /// Click the button identified by `id`. Returns nil on success, a
    /// human-readable error string on failure (button not found,
    /// AX disabled, etc.).
    static func click(buttonId id: String) -> String? {
        let pid = ProcessInfo.processInfo.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        let target = "fm-button-\(id)"

        guard let element = findElement(in: appElement, withIdentifier: target, depth: 0) else {
            return "AX lookup failed: button '\(id)' not found in panel (window hidden? collapsed group? id mismatch?)"
        }

        // Ask AX for the screen rect of the button.
        guard let rect = screenRect(of: element) else {
            return "AX did not return a position/size for button '\(id)'"
        }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        LoggerContext.shared.info("ButtonClicker", "click resolved", [
            "id":     id,
            "rect":   "\(Int(rect.origin.x)),\(Int(rect.origin.y)) \(Int(rect.size.width))x\(Int(rect.size.height))",
            "center": "\(Int(center.x)),\(Int(center.y))",
        ])

        // Save and (visibly) move the mouse so a human observer sees the
        // click happen. CGEvent.post would route the click correctly even
        // without moving the cursor, but the visible move is the whole
        // point of "GUI test that looks like a click".
        let originalLocation = NSEvent.mouseLocation     // bottom-left origin
        moveCursor(to: center)

        // Brief settle so the visible move registers before the click. 30ms
        // is below human flicker threshold but enough that screen capture
        // tools can record the cursor at the button.
        usleep(30_000)

        // Synthesize the click. .cghidEventTap goes through the full OS
        // event dispatch chain — same path a Magic Mouse click takes.
        guard let down = CGEvent(mouseEventSource: nil,
                                 mouseType: .leftMouseDown,
                                 mouseCursorPosition: center,
                                 mouseButton: .left),
              let up = CGEvent(mouseEventSource: nil,
                               mouseType: .leftMouseUp,
                               mouseCursorPosition: center,
                               mouseButton: .left) else {
            // Restore cursor before bailing.
            restoreCursor(originalLocation)
            return "CGEvent.mouseEvent allocation failed"
        }
        // Tag the events so any local event monitors can identify them as
        // synthetic if needed. 0x464D = ASCII "FM". Not strictly required
        // for SwiftUI to react — purely diagnostic.
        let fmTag: Int64 = 0x464D
        down.setIntegerValueField(.eventSourceUserData, value: fmTag)
        up.setIntegerValueField(.eventSourceUserData, value: fmTag)

        down.post(tap: .cghidEventTap)
        // SwiftUI's Button gesture recognizer wants a perceptible press
        // duration before treating the event as a tap. 20ms was below
        // threshold and the gesture was being rejected; 80ms reliably
        // registers as a click without feeling laggy to a human observer.
        usleep(80_000)
        up.post(tap: .cghidEventTap)
        LoggerContext.shared.info("ButtonClicker", "events posted",
                                  ["center": "\(Int(center.x)),\(Int(center.y))"])

        // Let the press visual state render before snapping the cursor back.
        usleep(120_000)
        restoreCursor(originalLocation)

        return nil
    }

    /// Recursive AX walk. Caps depth so a runaway tree doesn't hang the
    /// HTTP handler — panel hierarchy is shallow (Window → Group → Group
    /// → Button), so 12 is comfortably enough.
    private static func findElement(in element: AXUIElement,
                                    withIdentifier targetId: String,
                                    depth: Int) -> AXUIElement? {
        if depth > 12 { return nil }

        var idValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXIdentifierAttribute as CFString, &idValue) == .success,
           let s = idValue as? String, s == targetId {
            return element
        }

        var childrenValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
           let arr = childrenValue as? [AXUIElement] {
            for child in arr {
                if let found = findElement(in: child, withIdentifier: targetId, depth: depth + 1) {
                    return found
                }
            }
        }
        return nil
    }

    /// Read kAXPositionAttribute + kAXSizeAttribute and unpack into CGRect.
    /// Returns nil if either attribute is missing or unwrap fails.
    private static func screenRect(of element: AXUIElement) -> CGRect? {
        var posValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let posRef = posValue, let sizeRef = sizeValue,
              CFGetTypeID(posRef) == AXValueGetTypeID(),
              CFGetTypeID(sizeRef) == AXValueGetTypeID() else {
            return nil
        }
        var pos = CGPoint.zero
        var sz = CGSize.zero
        let posOK  = AXValueGetValue(posRef as! AXValue, .cgPoint, &pos)
        let sizeOK = AXValueGetValue(sizeRef as! AXValue, .cgSize, &sz)
        guard posOK, sizeOK else { return nil }
        return CGRect(origin: pos, size: sz)
    }

    /// `NSEvent.mouseLocation` returns bottom-left-origin; `CGWarpMouseCursorPosition`
    /// expects top-left-origin. We have to flip Y against the relevant screen.
    private static func moveCursor(to topLeftScreenPoint: CGPoint) {
        CGWarpMouseCursorPosition(topLeftScreenPoint)
        // Re-associate so subsequent events still flow normally.
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    private static func restoreCursor(_ bottomLeftOriginalLocation: NSPoint) {
        guard let mainScreen = NSScreen.screens.first else { return }
        let topLeftY = mainScreen.frame.height - bottomLeftOriginalLocation.y
        CGWarpMouseCursorPosition(CGPoint(x: bottomLeftOriginalLocation.x, y: topLeftY))
        CGAssociateMouseAndMouseCursorPosition(1)
    }
}
