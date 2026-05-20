import SwiftUI
import AppKit
import FloatingMacroCore

// MARK: - MacroStepDraft

struct MacroStepDraft: Identifiable {
    var id = UUID()
    var type: String = "text"
    var text: String = ""
    var keyCombo: String = ""
    var launchTarget: String = ""
    var terminalCommand: String = ""
    var delayMs: String = "500"

    func toAction() -> Action? {
        switch type {
        case "text":
            // マクロ内の text ステップは現状 appendMode をサポートしない。
            // 必要になったら MacroStepDraft に appendMode を足して UI を増やす。
            return .text(content: text, pasteDelayMs: 120, restoreClipboard: true, appendMode: false)
        case "key":
            guard !keyCombo.isEmpty else { return nil }
            return .key(combo: keyCombo)
        case "launch":
            guard !launchTarget.isEmpty else { return nil }
            return .launch(target: launchTarget)
        case "terminal":
            guard !terminalCommand.isEmpty else { return nil }
            return .terminal(app: "Terminal", command: terminalCommand,
                             newWindow: true, execute: true, profile: nil)
        case "delay":
            guard let ms = Int(delayMs), ms > 0 else { return nil }
            return .delay(ms: ms)
        default:
            return nil
        }
    }

    static func from(_ action: Action) -> MacroStepDraft {
        var d = MacroStepDraft()
        switch action {
        case .text(let c, _, _, _):
            d.type = "text"; d.text = c
        case .key(let c):
            d.type = "key"; d.keyCombo = c
        case .launch(let t):
            d.type = "launch"; d.launchTarget = t
        case .terminal(_, let c, _, _, _):
            d.type = "terminal"; d.terminalCommand = c
        case .delay(let ms):
            d.type = "delay"; d.delayMs = String(ms)
        case .macro:
            break
        }
        return d
    }
}

// MARK: - MacroStepRow

struct MacroStepRow: View {
    @Binding var step: MacroStepDraft
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Picker("", selection: $step.type) {
                Text("text").tag("text")
                Text("key").tag("key")
                Text("launch").tag("launch")
                Text("terminal").tag("terminal")
                Text("delay").tag("delay")
            }
            .labelsHidden()
            .frame(width: 90)

            switch step.type {
            case "text":
                TextField(L("テキスト_fe9ebd"), text: $step.text)
                    .textFieldStyle(.roundedBorder)
            case "key":
                HStack(spacing: 4) {
                    TextField("cmd+shift+v / left / delete / f5", text: $step.keyCombo)
                        .textFieldStyle(.roundedBorder)
                    ComboKeyRecorderButton(combo: $step.keyCombo)
                    ComboSpecialKeyMenu(combo: $step.keyCombo)
                }
            case "launch":
                TextField(L("Applications_または_bundle_id_cb12d6"), text: $step.launchTarget)
                    .textFieldStyle(.roundedBorder)
            case "terminal":
                TextField(L("コマンド_4c2ea9"), text: $step.terminalCommand)
                    .textFieldStyle(.roundedBorder)
            case "delay":
                TextField("500", text: $step.delayMs)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                Text("ms")
                    .foregroundColor(.secondary)
            default:
                EmptyView()
            }

            Button(action: onMoveUp) {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(!canMoveUp)

            Button(action: onMoveDown) {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .disabled(!canMoveDown)

            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
        }
    }
}

