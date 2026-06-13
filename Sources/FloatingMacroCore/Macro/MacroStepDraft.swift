import Foundation

/// Button Editor macro step: one line edit buffer.
///
/// Parameters not exposed by UI (set via Control API)
/// retain all fields including pasteDelayMs and app specification for terminal, etc.)
/// Load → Edit → Save Round Trip to Default
/// Guarantee not to return unless the conversion logic is separated from the UI.
/// To make it possible to test, placed in Core.
public struct MacroStepDraft: Identifiable, Equatable {
    public var id = UUID()
    public var type: String = "text"

    // text
    public var text: String = ""
    public var pasteDelayMs: Int = 120
    public var restoreClipboard: Bool = true
    public var appendMode: Bool = false

    // key
    public var keyCombo: String = ""

    // launch
    public var launchTarget: String = ""

    // terminal
    public var terminalApp: String = "Terminal"
    public var terminalCommand: String = ""
    public var terminalNewWindow: Bool = true
    public var terminalExecute: Bool = true
    public var terminalProfile: String? = nil

    // Delay (maintained as a string for direct association with text fields)
    public var delayMs: String = "500"

    public init() {}

    /// This step cannot be converted to an Action because it is nil.
    public enum Issue: Equatable {
        case emptyKeyCombo
        case emptyLaunchTarget
        case emptyTerminalCommand
        case invalidDelay
        case unknownType
    }

    public var issue: Issue? {
        switch type {
        case "text":
            return nil
        case "key":
            return keyCombo.trimmingCharacters(in: .whitespaces).isEmpty ? .emptyKeyCombo : nil
        case "launch":
            return launchTarget.trimmingCharacters(in: .whitespaces).isEmpty ? .emptyLaunchTarget : nil
        case "terminal":
            return terminalCommand.trimmingCharacters(in: .whitespaces).isEmpty ? .emptyTerminalCommand : nil
        case "delay":
            guard let ms = Int(delayMs), DelayActionExecutor.allowedMs.contains(ms) else {
                return .invalidDelay
            }
            return nil
        default:
            return .unknownType
        }
    }

    /// Return the corresponding `Action` if valid; otherwise, return nil.
    /// The caller retrieves the reason via `issue` and presents it to the user.
    /// (If nil is silently discarded, it will cause a step disappearance accident).
    public func toAction() -> Action? {
        guard issue == nil else { return nil }
        switch type {
        case "text":
            return .text(content: text, pasteDelayMs: pasteDelayMs,
                         restoreClipboard: restoreClipboard, appendMode: appendMode)
        case "key":
            return .key(combo: keyCombo)
        case "launch":
            return .launch(target: launchTarget)
        case "terminal":
            return .terminal(app: terminalApp, command: terminalCommand,
                             newWindow: terminalNewWindow, execute: terminalExecute,
                             profile: terminalProfile)
        case "delay":
            guard let ms = Int(delayMs) else { return nil }
            return .delay(ms: ms)
        default:
            return nil
        }
    }

    public static func from(_ action: Action) -> MacroStepDraft {
        var d = MacroStepDraft()
        switch action {
        case .text(let content, let pasteDelay, let restore, let append):
            d.type = "text"
            d.text = content
            d.pasteDelayMs = pasteDelay
            d.restoreClipboard = restore
            d.appendMode = append
        case .key(let combo):
            d.type = "key"
            d.keyCombo = combo
        case .launch(let target):
            d.type = "launch"
            d.launchTarget = target
        case .terminal(let app, let command, let newWindow, let execute, let profile):
            d.type = "terminal"
            d.terminalApp = app
            d.terminalCommand = command
            d.terminalNewWindow = newWindow
            d.terminalExecute = execute
            d.terminalProfile = profile
        case .delay(let ms):
            d.type = "delay"
            d.delayMs = String(ms)
        case .macro:
            // Nested macros are rejected at the time of decoding Action, so they are not reached.
            break
        }
        return d
    }
}
