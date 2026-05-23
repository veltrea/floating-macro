import SwiftUI
import AppKit
import FloatingMacroCore

// MARK: - Key recorder & special key catalog

/// Virtual key codes understood by KeyCombo parser in macOS.
/// Reverse lookup for `KeyCombo.keyCodeMap` in canonical names.
enum KeyNameLookup {
    static func name(forKeyCode code: UInt16) -> String? {
        switch code {
        case 0x00: return "a"; case 0x01: return "s"; case 0x02: return "d"; case 0x03: return "f"
        case 0x04: return "h"; case 0x05: return "g"; case 0x06: return "z"; case 0x07: return "x"
        case 0x08: return "c"; case 0x09: return "v"; case 0x0B: return "b"; case 0x0C: return "q"
        case 0x0D: return "w"; case 0x0E: return "e"; case 0x0F: return "r"; case 0x10: return "y"
        case 0x11: return "t"; case 0x12: return "1"; case 0x13: return "2"; case 0x14: return "3"
        case 0x15: return "4"; case 0x16: return "6"; case 0x17: return "5"; case 0x18: return "="
        case 0x19: return "9"; case 0x1A: return "7"; case 0x1B: return "-"; case 0x1C: return "8"
        case 0x1D: return "0"; case 0x1E: return "]"; case 0x1F: return "o"; case 0x20: return "u"
        case 0x21: return "["; case 0x22: return "i"; case 0x23: return "p"; case 0x25: return "l"
        case 0x26: return "j"; case 0x27: return "'"; case 0x28: return "k"; case 0x29: return ";"
        case 0x2A: return "\\"; case 0x2B: return ","; case 0x2C: return "/"; case 0x2D: return "n"
        case 0x2E: return "m"; case 0x2F: return "."; case 0x32: return "`"
        case 0x24: return "return"
        case 0x30: return "tab"
        case 0x31: return "space"
        case 0x33: return "delete"
        case 0x35: return "escape"
        case 0x75: return "forwarddelete"
        case 0x7B: return "left"; case 0x7C: return "right"
        case 0x7D: return "down"; case 0x7E: return "up"
        case 0x73: return "home"; case 0x77: return "end"
        case 0x74: return "pageup"; case 0x79: return "pagedown"
        case 0x7A: return "f1"; case 0x78: return "f2"; case 0x63: return "f3"; case 0x76: return "f4"
        case 0x60: return "f5"; case 0x61: return "f6"; case 0x62: return "f7"; case 0x64: return "f8"
        case 0x65: return "f9"; case 0x6D: return "f10"; case 0x67: return "f11"; case 0x6F: return "f12"
        case 0x69: return "f13"; case 0x6B: return "f14"; case 0x71: return "f15"; case 0x6A: return "f16"
        case 0x40: return "f17"; case 0x4F: return "f18"; case 0x50: return "f19"; case 0x5A: return "f20"
        default: return nil
        }
    }

    /// List for special keys dropdown (label = display name, value = KeyCombo name).
    /// The true source is `KeyCombo.specialKeys` + `KeyCombo.functionKeys`.
    static var specialKeys: [(label: String, value: String)] {
        (KeyCombo.specialKeys + KeyCombo.functionKeys).map { ($0.label, $0.name) }
    }
}

/// Clicking will absorb the next key input and restore the modified key plus base key.
/// Cancel recording with Esc.
struct KeyRecorderButton: View {
    @Binding var modCmd: Bool
    @Binding var modShift: Bool
    @Binding var modOption: Bool
    @Binding var modCtrl: Bool
    @Binding var baseKey: String

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 4) {
                Image(systemName: isRecording ? "record.circle.fill" : "keyboard")
                    .foregroundColor(isRecording ? .red : .accentColor)
                Text(isRecording ? L("Press to cancel _Esc_ 1ccbec") : L("Press key to record _e8d275"))
            }
        }
        .onDisappear { stopRecording() }
    }

    private func toggle() {
        if isRecording { stopRecording() } else { startRecording() }
    }

    private func startRecording() {
        guard monitor == nil else { return }
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleKey(event)
            return nil // Consume event (delete key etc. does not propagate to other fields)
        }
    }

    private func stopRecording() {
        isRecording = false
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }

    private func handleKey(_ event: NSEvent) {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // Esc alone is treated as cancel (no modifier)
        if event.keyCode == 0x35 && mods.subtracting([.capsLock]).isEmpty {
            stopRecording()
            return
        }
        guard let name = KeyNameLookup.name(forKeyCode: event.keyCode) else {
            NSSound.beep()
            return
        }
        modCmd    = mods.contains(.command)
        modShift  = mods.contains(.shift)
        modOption = mods.contains(.option)
        modCtrl   = mods.contains(.control)
        baseKey   = name
        stopRecording()
    }
}

/// Menu to select special keys (arrow, F1-~delete) from a list and paste them into `baseKey`.
struct SpecialKeyMenu: View {
    @Binding var baseKey: String

    var body: some View {
        Menu {
            ForEach(KeyNameLookup.specialKeys, id: \.value) { opt in
                Button(opt.label) { baseKey = opt.value }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "list.bullet")
                Text(L("Special key_cdc3db"))
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

/// Button for recording directly into a single combo string binding for macro steps.
struct ComboKeyRecorderButton: View {
    @Binding var combo: String
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button(action: toggle) {
            Image(systemName: isRecording ? "record.circle.fill" : "keyboard")
                .foregroundColor(isRecording ? .red : .accentColor)
        }
        .help(isRecording ? L("Press to cancel _Esc_ 1ccbec") : L("Press key to record _e8d275"))
        .buttonStyle(.borderless)
        .onDisappear { stopRecording() }
    }

    private func toggle() {
        if isRecording { stopRecording() } else { startRecording() }
    }

    private func startRecording() {
        guard monitor == nil else { return }
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleKey(event)
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }

    private func handleKey(_ event: NSEvent) {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == 0x35 && mods.subtracting([.capsLock]).isEmpty {
            stopRecording()
            return
        }
        guard let name = KeyNameLookup.name(forKeyCode: event.keyCode) else {
            NSSound.beep()
            return
        }
        var parts: [String] = []
        if mods.contains(.command)  { parts.append("cmd") }
        if mods.contains(.shift)    { parts.append("shift") }
        if mods.contains(.option)   { parts.append("option") }
        if mods.contains(.control)  { parts.append("ctrl") }
        parts.append(name)
        combo = parts.joined(separator: "+")
        stopRecording()
    }
}

/// Macrostep: Special key selection menu (directly overwrite combo string).
struct ComboSpecialKeyMenu: View {
    @Binding var combo: String

    var body: some View {
        Menu {
            ForEach(KeyNameLookup.specialKeys, id: \.value) { opt in
                Button(opt.label) { combo = opt.value }
            }
        } label: {
            Image(systemName: "list.bullet")
        }
        .help(L("Select special key _b5bdcd"))
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}
