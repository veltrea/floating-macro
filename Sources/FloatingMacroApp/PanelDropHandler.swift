import AppKit
import Foundation
import FloatingMacroCore

/// Create buttons automatically for file/app drag-and-drop into the panel.
/// Call `handleDroppedURLs` from the `.onDrop` handler on the SwiftUI side.
///
/// Drop that can be accepted:
/// `.app` bundle launch action (keep bundle id as target)
/// Other files/folders → `launch` action (absolute path held as target)
///
/// This file is kept as thin as possible, for discrimination, icon extraction, and save path calculation.
/// all `FloatingMacroCore` side (`AppDropClassifier`, `ImageIOIconExtractor`,
/// The `IconAssetSaver` is performed and unit tested. The dependency on AppKit is
/// Only the confirmation dialog of NSAlert.
enum PanelDropHandler {

    @MainActor
    static func handleDroppedURLs(_ urls: [URL], presetManager: PresetManager) async {
        guard !urls.isEmpty else { return }
        guard let preset = presetManager.currentPreset else { return }

        // Determine the additional group to add:
        // If there is an existing group, the first one
        // If not exists, automatically create the "Launcher" group.
        let targetGroupId: String
        if let firstGroup = preset.groups.first {
            targetGroupId = firstGroup.id
        } else {
            let newId = "g-\(Int.random(in: 1000...9999))"
            let group = ButtonGroup(
                id: newId,
                label: L("ランチャー_4a2f05"),
                iconText: "🚀",
                buttons: []
            )
            guard presetManager.addGroup(group) else { return }
            targetGroupId = newId
        }

        let candidates = urls.compactMap { AppDropClassifier.classify($0) }
        guard !candidates.isEmpty else { return }

        let groupLabel = presetManager.currentPreset?
            .groups.first(where: { $0.id == targetGroupId })?.label ?? L("不明_e1eb5a")
        guard confirmAdd(candidates: candidates, groupLabel: groupLabel) else { return }

        for c in candidates {
            let buttonId = "b-\(Int.random(in: 1000...9999))"
            let sourceURL = URL(fileURLWithPath: c.iconSourcePath)

            // Icon extraction cascade (including content inspection):
            // Shared cache → Inspection
            // 1. ImageIO for .icns direct read (only in .app) → Inspection
            // 2. NSWorkspace fallback → inspection
            // Save PNG under preset folder at the point of removal, and also put .app in shared cache.
            var iconBytes: Data? = nil
            if c.kind == .app,
               let cached = await AppIconCache.shared.get(for: sourceURL),
               IconContentValidator.hasMeaningfulContent(pngData: cached) {
                iconBytes = cached
            }
            if iconBytes == nil, c.kind == .app,
               let data = try? ImageIOIconExtractor()
                   .extractPNG(from: sourceURL, size: 64),
               IconContentValidator.hasMeaningfulContent(pngData: data) {
                await AppIconCache.shared.put(for: sourceURL, data: data)
                iconBytes = data
            }
            if iconBytes == nil,
               let data = NSWorkspaceIconFallback.extractPNG(
                   appURL: sourceURL, size: 64),
               IconContentValidator.hasMeaningfulContent(pngData: data) {
                if c.kind == .app {
                    await AppIconCache.shared.put(for: sourceURL, data: data)
                }
                iconBytes = data
            }

            let iconPath: String? = iconBytes.flatMap {
                try? IconAssetSaver.saveData(
                    $0, buttonId: buttonId, presetName: preset.name)
            }

            let fallbackEmoji: String
            switch c.kind {
            case .app:    fallbackEmoji = "📦"
            case .folder: fallbackEmoji = "📁"
            case .file:   fallbackEmoji = "📎"
            }
            let button = ButtonDefinition(
                id: buttonId,
                label: c.label,
                icon: iconPath,
                iconText: iconPath == nil ? fallbackEmoji : nil,
                tooltip: c.tooltip,
                action: .launch(target: c.target)
            )
            _ = presetManager.addButton(button, toGroupId: targetGroupId)
        }
    }

    // MARK: - Confirmation

    /// Check if it's okay to convert the button in NSAlert to true for continuation.
    private static func confirmAdd(candidates: [AppDropClassifier.Candidate],
                                   groupLabel: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = L("ドロップされたアイテムをボタンにしますか_1b77ca")
        let bullets = candidates.prefix(8).map { "• \($0.label)" }.joined(separator: "\n")
        let extra = candidates.count > 8 ? L_("more_items_count", candidates.count - 8) : ""
        alert.informativeText = L_("drop_alert_informative", groupLabel, candidates.count, "\(bullets)\(extra)")
        alert.addButton(withTitle: L("追加_7dc3a5"))
        alert.addButton(withTitle: L("キャンセル_6ef349"))
        return alert.runModal() == .alertFirstButtonReturn
    }
}
