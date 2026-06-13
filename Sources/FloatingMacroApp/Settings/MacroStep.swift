import SwiftUI
import AppKit
import FloatingMacroCore

// MacroStepDraft (editing buffer body) is in FloatingMacroCore/Macro/MacroStepDraft.swift.
// Here place only SwiftUI views.

/// Display warning messages within the steps for users.
/// Use for both save-time validation messages.
func macroStepIssueText(_ issue: MacroStepDraft.Issue) -> String {
    switch issue {
    case .emptyKeyCombo:
        return L("macro_issue_empty_key")
    case .emptyLaunchTarget:
        return L("macro_issue_empty_launch")
    case .emptyTerminalCommand:
        return L("macro_issue_empty_terminal")
    case .invalidDelay:
        return L("macro_issue_invalid_delay")
    case .unknownType:
        return L("macro_issue_unknown_type")
    }
}

// MARK: - DelayQuickPicker

/// Quick selection menu for frequently used values placed next to the wait time field.
struct DelayQuickPicker: View {
    @Binding var delayMs: String

    private static let choices: [(label: String, ms: String)] = [
        ("0.2 s", "200"), ("0.5 s", "500"), ("1 s", "1000"),
        ("2 s", "2000"), ("5 s", "5000"),
    ]

    var body: some View {
        Menu {
            ForEach(Self.choices, id: \.ms) { c in
                Button(c.label) { delayMs = c.ms }
            }
        } label: {
            Image(systemName: "clock")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(L("delay_quick_pick_help"))
    }
}

// MARK: - MacroStepRow

struct MacroStepRow: View {
    @Binding var step: MacroStepDraft
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Picker("", selection: $step.type) {
                Text(L("Step Type Text 4c21aa")).tag("text")
                Text(L("Step type key 8eb301")).tag("key")
                Text(L("Launch Step Type_5f0e22")).tag("launch")
                Text(L("Step Type: Terminal c30d11")).tag("terminal")
                Text(L("Waiting Step Type_a47f90")).tag("delay")
            }
            .labelsHidden()
            .frame(width: 110)

            switch step.type {
            case "text":
                TextField(L("text_fe9ebd"), text: $step.text)
                    .textFieldStyle(.roundedBorder)
            case "key":
                HStack(spacing: 4) {
                    TextField("cmd+shift+v / left / delete / f5", text: $step.keyCombo)
                        .textFieldStyle(.roundedBorder)
                    ComboKeyRecorderButton(combo: $step.keyCombo)
                    ComboSpecialKeyMenu(combo: $step.keyCombo)
                }
            case "launch":
                TextField(L("Applications_or _bundle_id_cb12d6"), text: $step.launchTarget)
                    .textFieldStyle(.roundedBorder)
            case "terminal":
                TextField(L("Command_4c2ea9"), text: $step.terminalCommand)
                    .textFieldStyle(.roundedBorder)
            case "delay":
                TextField("500", text: $step.delayMs)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                Text("ms")
                    .foregroundColor(.secondary)
                DelayQuickPicker(delayMs: $step.delayMs)
            default:
                EmptyView()
            }

            // Suppress silently without discarding invalid steps and issue a warning within the scope.
            // Saving time, the validation on the ButtonEditor side blocks saving itself.
            if let issue = step.issue {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .help(macroStepIssueText(issue))
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

            Button(action: onDuplicate) {
                Image(systemName: "plus.square.on.square")
            }
            .buttonStyle(.borderless)
            .help(L("Duplicate step 71c8d2"))

            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
        }
    }
}
