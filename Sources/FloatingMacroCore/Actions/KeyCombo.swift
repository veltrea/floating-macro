import Foundation
import CoreGraphics

public struct KeyCombo: Equatable {
    public let modifiers: CGEventFlags
    public let keyCode: UInt16

    public init(modifiers: CGEventFlags, keyCode: UInt16) {
        self.modifiers = modifiers
        self.keyCode = keyCode
    }

    public static func parse(_ combo: String) throws -> KeyCombo {
        let parts = combo.lowercased().split(separator: "+").map { String($0).trimmingCharacters(in: .whitespaces) }
        guard !parts.isEmpty else {
            throw ActionError.invalidKeyCombo(combo)
        }

        var flags = CGEventFlags()
        var keyName: String?

        for part in parts {
            switch part {
            case "cmd", "command":
                flags.insert(.maskCommand)
            case "ctrl", "control":
                flags.insert(.maskControl)
            case "alt", "option":
                flags.insert(.maskAlternate)
            case "shift":
                flags.insert(.maskShift)
            default:
                if keyName != nil {
                    throw ActionError.invalidKeyCombo(combo)
                }
                keyName = part
            }
        }

        guard let key = keyName else {
            throw ActionError.invalidKeyCombo(combo)
        }

        guard let code = KeyCombo.keyCodeMap[key] else {
            throw ActionError.invalidKeyCombo(combo)
        }

        return KeyCombo(modifiers: flags, keyCode: code)
    }

    // MARK: - Discoverable catalog (for ACP / settings UI)

    /// Canonical supported-key catalog, organized for AI discovery.
    /// `name` は `combo` 文字列でそのまま使える正規キー名。
    /// `label` は人間向け表示名（プルダウン UI / マニフェストで使う）。
    public struct KeyEntry: Equatable {
        public let name: String
        public let label: String
        public init(name: String, label: String) {
            self.name = name
            self.label = label
        }
    }

    public static let modifierNames: [String] = ["cmd", "shift", "option", "ctrl"]

    /// Aliases the parser accepts in addition to the canonical names.
    public static let modifierAliases: [String: String] = [
        "command": "cmd",
        "control": "ctrl",
        "alt": "option",
    ]

    public static let specialKeys: [KeyEntry] = [
        .init(name: "delete",        label: "Delete (Backspace ←)"),
        .init(name: "forwarddelete", label: "Forward Delete (⌦)"),
        .init(name: "left",          label: "← Left arrow"),
        .init(name: "right",         label: "→ Right arrow"),
        .init(name: "up",            label: "↑ Up arrow"),
        .init(name: "down",          label: "↓ Down arrow"),
        .init(name: "home",          label: "Home"),
        .init(name: "end",           label: "End"),
        .init(name: "pageup",        label: "Page Up"),
        .init(name: "pagedown",      label: "Page Down"),
        .init(name: "return",        label: "Return / Enter"),
        .init(name: "tab",           label: "Tab"),
        .init(name: "space",         label: "Space"),
        .init(name: "escape",        label: "Escape"),
    ]

    public static let functionKeys: [KeyEntry] = (1...20).map {
        KeyEntry(name: "f\($0)", label: "F\($0)")
    }

    /// Aliases for keys (parser accepts both).
    public static let keyAliases: [String: String] = [
        "enter": "return",
        "esc": "escape",
        "backspace": "delete",
    ]

    // macOS virtual key codes
    static let keyCodeMap: [String: UInt16] = [
        // Letters
        "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03,
        "h": 0x04, "g": 0x05, "z": 0x06, "x": 0x07,
        "c": 0x08, "v": 0x09, "b": 0x0B, "q": 0x0C,
        "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10,
        "t": 0x11, "1": 0x12, "2": 0x13, "3": 0x14,
        "4": 0x15, "6": 0x16, "5": 0x17, "=": 0x18,
        "9": 0x19, "7": 0x1A, "-": 0x1B, "8": 0x1C,
        "0": 0x1D, "]": 0x1E, "o": 0x1F, "u": 0x20,
        "[": 0x21, "i": 0x22, "p": 0x23, "l": 0x25,
        "j": 0x26, "'": 0x27, "k": 0x28, ";": 0x29,
        "\\": 0x2A, ",": 0x2B, "/": 0x2C, "n": 0x2D,
        "m": 0x2E, ".": 0x2F, "`": 0x32,

        // Special keys
        "enter": 0x24, "return": 0x24,
        "tab": 0x30,
        "space": 0x31,
        "backspace": 0x33, "delete": 0x33,
        "escape": 0x35, "esc": 0x35,
        "forwarddelete": 0x75,

        // Arrow keys
        "left": 0x7B, "right": 0x7C,
        "down": 0x7D, "up": 0x7E,

        // Navigation
        "home": 0x73, "end": 0x77,
        "pageup": 0x74, "pagedown": 0x79,

        // Function keys
        "f1": 0x7A, "f2": 0x78, "f3": 0x63, "f4": 0x76,
        "f5": 0x60, "f6": 0x61, "f7": 0x62, "f8": 0x64,
        "f9": 0x65, "f10": 0x6D, "f11": 0x67, "f12": 0x6F,
        "f13": 0x69, "f14": 0x6B, "f15": 0x71, "f16": 0x6A,
        "f17": 0x40, "f18": 0x4F, "f19": 0x50, "f20": 0x5A,
    ]
}
