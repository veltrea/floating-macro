import Foundation

public enum KeyActionExecutor {
    private static let category = "KeyAction"
    public static var synthesizer: EventSynthesizerProtocol = CGEventSynthesizer.shared

    public static func execute(_ combo: KeyCombo) throws {
        let log = LoggerContext.shared
        log.debug(category, "Dispatching key event", [
            "keyCode": String(combo.keyCode),
            "flags":   String(combo.modifiers.rawValue),
        ])
        do {
            try synthesizer.postKeyEvent(keyCode: combo.keyCode, flags: combo.modifiers)
        } catch {
            log.error(category, "Key dispatch failed", [
                "keyCode": String(combo.keyCode),
                "error":   String(describing: error),
            ])
            throw error
        }
    }
}
