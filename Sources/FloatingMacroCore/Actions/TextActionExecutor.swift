import Foundation

public enum TextActionExecutor {
    private static let category = "TextAction"
    public static var clipboard: ClipboardProtocol = SystemClipboard.shared
    public static var synthesizer: EventSynthesizerProtocol = CGEventSynthesizer.shared

    public static func execute(content: String, pasteDelayMs: Int = 120, restoreClipboard: Bool = true) throws {
        let log = LoggerContext.shared
        log.debug(category, "Injecting text", [
            "length":           String(content.count),
            "pasteDelayMs":     String(pasteDelayMs),
            "restoreClipboard": String(restoreClipboard),
        ])
        // 1. Save clipboard
        let snapshot = clipboard.save()

        // Ensure we always restore on any exit path — including when the
        // synthesizer throws (Accessibility denied, keyCombo invalid, etc).
        // This prevents the user's clipboard from being left overwritten
        // with possibly-sensitive paste content.
        defer {
            if restoreClipboard {
                clipboard.restore(snapshot)
            }
        }

        // 2-3. Set text
        clipboard.setString(content)

        // 4. Brief wait for pasteboard to settle
        Thread.sleep(forTimeInterval: 0.01)

        // 5. Send Cmd+V
        let cmdV = try KeyCombo.parse("cmd+v")
        do {
            try synthesizer.postKeyEvent(keyCode: cmdV.keyCode, flags: cmdV.modifiers)
        } catch {
            log.error(category, "Cmd+V dispatch failed", [
                "error": String(describing: error),
            ])
            throw error
        }

        // 6. Wait for paste to complete
        Thread.sleep(forTimeInterval: Double(pasteDelayMs) / 1000.0)
        log.info(category, "Text injected", ["length": String(content.count)])
    }
}
