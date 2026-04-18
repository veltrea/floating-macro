import Foundation

/// Curated catalog of SF Symbols the UI picker exposes by default.
///
/// SF Symbols are shipped with macOS 11+ and rendered at runtime by the
/// system — this catalog only stores the **identifier strings** (which are
/// public API names), never the glyph data. The identifiers are taken from
/// Apple's SF Symbols app, which is the canonical, Apple-authored reference
/// used by every macOS developer; they are not copyrightable per se (they
/// are interface names that must match exactly to call the API).
///
/// We keep the list small (~150) to give users a focused, Mac-native
/// experience. Users who need something outside the catalog can still type
/// `sf:<name>` directly — the `icon` field is freeform text.
public enum SFSymbolCatalog {

    public struct Category: Equatable {
        public let id: String
        public let label: String
        public let symbols: [String]
    }

    /// Ordered list of categories shown in the picker.
    public static let categories: [Category] = [
        Category(id: "general", label: "一般", symbols: [
            "star", "star.fill",
            "heart", "heart.fill",
            "bookmark", "bookmark.fill",
            "pin", "pin.fill",
            "flag", "flag.fill",
            "tag", "tag.fill",
            "bell", "bell.fill",
            "sparkles",
        ]),
        Category(id: "ui", label: "UI", symbols: [
            "plus", "minus", "xmark", "checkmark",
            "plus.circle", "xmark.circle", "checkmark.circle",
            "ellipsis", "ellipsis.circle",
            "magnifyingglass",
            "gear", "gearshape", "gearshape.fill",
            "info.circle", "questionmark.circle",
            "exclamationmark.triangle",
            "trash", "trash.fill",
            "square.and.arrow.up", "square.and.arrow.down",
        ]),
        Category(id: "nav", label: "ナビ", symbols: [
            "chevron.left", "chevron.right", "chevron.up", "chevron.down",
            "arrow.left", "arrow.right", "arrow.up", "arrow.down",
            "arrow.up.left", "arrow.up.right",
            "arrow.clockwise", "arrow.counterclockwise",
            "arrow.up.arrow.down",
            "house", "house.fill",
            "arrow.uturn.left", "arrow.uturn.right",
        ]),
        Category(id: "files", label: "ファイル", symbols: [
            "doc", "doc.fill", "doc.text",
            "doc.on.doc",
            "folder", "folder.fill",
            "tray", "tray.full",
            "archivebox", "archivebox.fill",
            "externaldrive", "internaldrive",
            "paperplane", "paperplane.fill",
        ]),
        Category(id: "media", label: "メディア", symbols: [
            "play", "play.fill", "pause", "pause.fill", "stop", "stop.fill",
            "forward", "forward.fill", "backward", "backward.fill",
            "speaker", "speaker.fill",
            "speaker.slash", "speaker.wave.2",
            "music.note", "mic", "mic.slash",
            "camera", "camera.fill",
            "photo", "photo.fill",
        ]),
        Category(id: "comm", label: "通信", symbols: [
            "envelope", "envelope.fill",
            "message", "message.fill",
            "phone", "phone.fill",
            "bubble.left", "bubble.right",
            "bell.slash",
            "wifi", "network",
            "globe",
        ]),
        Category(id: "tools", label: "ツール", symbols: [
            "wrench", "hammer", "screwdriver",
            "paintbrush", "paintbrush.fill",
            "scissors", "ruler", "pencil",
            "square.and.pencil", "pencil.circle",
            "wand.and.stars",
            "bolt", "bolt.fill",
            "lock", "lock.fill", "key", "key.fill",
        ]),
        Category(id: "system", label: "システム", symbols: [
            "keyboard", "command", "option",
            "terminal",
            "cpu", "memorychip",
            "server.rack",
            "display",
            "apple.terminal",
            "clock", "clock.fill", "timer", "stopwatch", "alarm",
            "calendar",
            "sparkle",
            "brain.head.profile",
        ]),
    ]

    /// Flat list of all symbol names across categories (de-duplicated, stable order).
    public static var all: [String] {
        var seen = Set<String>()
        var out: [String] = []
        for category in categories {
            for name in category.symbols where !seen.contains(name) {
                seen.insert(name)
                out.append(name)
            }
        }
        return out
    }

    public static func category(id: String) -> Category? {
        categories.first(where: { $0.id == id })
    }

    /// Full reference string to store in `ButtonDefinition.icon`.
    public static func reference(for name: String) -> String {
        "sf:\(name)"
    }
}
