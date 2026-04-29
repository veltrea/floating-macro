import CoreGraphics

public protocol EventSynthesizerProtocol {
    func postKeyEvent(keyCode: UInt16, flags: CGEventFlags) throws
}

public final class CGEventSynthesizer: EventSynthesizerProtocol {
    public static let shared = CGEventSynthesizer()

    public func postKeyEvent(keyCode: UInt16, flags: CGEventFlags) throws {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw ActionError.accessibilityDenied
        }

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            throw ActionError.accessibilityDenied
        }

        keyDown.flags = flags
        keyUp.flags = flags

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
