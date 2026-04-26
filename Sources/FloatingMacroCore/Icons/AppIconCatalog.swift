import Foundation

/// A well-known application entry whose icon can be fetched from NSWorkspace.
public struct AppIconEntry: Equatable {
    public let bundleId: String
    public let displayName: String
    public let categoryId: String

    public init(bundleId: String, displayName: String, categoryId: String) {
        self.bundleId = bundleId
        self.displayName = displayName
        self.categoryId = categoryId
    }
}

/// Category grouping for the app icon picker.
public struct AppIconCategory: Equatable {
    public let id: String
    public let label: String

    public init(id: String, label: String) {
        self.id = id
        self.label = label
    }
}

/// Catalog of well-known applications whose icons are useful for button /
/// group decoration.  The ``installedEntries()`` method filters to apps
/// that are actually present on the current machine.
public enum AppIconCatalog {

    public static let categories: [AppIconCategory] = [
        AppIconCategory(id: "ai", label: "AI"),
        AppIconCategory(id: "dev", label: "開発"),
        AppIconCategory(id: "browser", label: "ブラウザ"),
        AppIconCategory(id: "util", label: "ユーティリティ"),
    ]

    /// Master list — order within each category is display order.
    public static let all: [AppIconEntry] = [
        // AI
        AppIconEntry(bundleId: "com.anthropic.claudefordesktop", displayName: "Claude", categoryId: "ai"),
        AppIconEntry(bundleId: "com.openai.chatgpt", displayName: "ChatGPT", categoryId: "ai"),
        AppIconEntry(bundleId: "com.lmstudio.app", displayName: "LM Studio", categoryId: "ai"),
        AppIconEntry(bundleId: "com.cursor.Cursor", displayName: "Cursor", categoryId: "ai"),
        AppIconEntry(bundleId: "dev.codex.codex", displayName: "Codex", categoryId: "ai"),
        AppIconEntry(bundleId: "com.google.Chrome.app.kjgfgldnnfobanmfkialjljlidhmjked", displayName: "Gemini (Chrome App)", categoryId: "ai"),

        // Dev tools
        AppIconEntry(bundleId: "com.apple.Terminal", displayName: "Terminal", categoryId: "dev"),
        AppIconEntry(bundleId: "com.googlecode.iterm2", displayName: "iTerm2", categoryId: "dev"),
        AppIconEntry(bundleId: "com.microsoft.VSCode", displayName: "VS Code", categoryId: "dev"),
        AppIconEntry(bundleId: "com.todesktop.230313mzl4w4u92", displayName: "Cursor", categoryId: "dev"),
        AppIconEntry(bundleId: "dev.zed.Zed-Preview", displayName: "Zed", categoryId: "dev"),

        // Browsers
        AppIconEntry(bundleId: "com.apple.Safari", displayName: "Safari", categoryId: "browser"),
        AppIconEntry(bundleId: "com.google.Chrome", displayName: "Chrome", categoryId: "browser"),
        AppIconEntry(bundleId: "org.mozilla.firefox", displayName: "Firefox", categoryId: "browser"),
        AppIconEntry(bundleId: "com.microsoft.edgemac", displayName: "Edge", categoryId: "browser"),
        AppIconEntry(bundleId: "com.vivaldi.Vivaldi", displayName: "Vivaldi", categoryId: "browser"),

        // Utilities
        AppIconEntry(bundleId: "com.apple.finder", displayName: "Finder", categoryId: "util"),
        AppIconEntry(bundleId: "com.apple.systempreferences", displayName: "設定", categoryId: "util"),
        AppIconEntry(bundleId: "com.figma.Desktop", displayName: "Figma", categoryId: "util"),
        AppIconEntry(bundleId: "notion.id", displayName: "Notion", categoryId: "util"),
        AppIconEntry(bundleId: "com.tinyspeck.slackmacgap", displayName: "Slack", categoryId: "util"),
    ]

    /// Return only entries whose app is installed on this machine.
    /// Requires AppKit at call site (NSWorkspace), so we accept a
    /// closure to avoid importing AppKit in the Core target.
    public static func installedEntries(
        isInstalled: (String) -> Bool
    ) -> [AppIconEntry] {
        all.filter { isInstalled($0.bundleId) }
    }

    /// Entries for a specific category.
    public static func entries(
        forCategory categoryId: String,
        isInstalled: (String) -> Bool
    ) -> [AppIconEntry] {
        installedEntries(isInstalled: isInstalled)
            .filter { $0.categoryId == categoryId }
    }
}
