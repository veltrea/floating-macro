import AppKit
import Foundation
import FloatingMacroCore

/// パネルへのファイル / アプリのドラッグ&ドロップで自動的にボタンを作成する。
/// SwiftUI 側の `.onDrop` ハンドラから `handleDroppedURLs` を呼ぶ。
///
/// 受け付けるドロップ:
///   - `.app` バンドル        → `launch` action (bundle id を target に保持)
///   - その他のファイル/フォルダ → `launch` action (絶対パスを target に保持)
///
/// このファイルはなるべく薄く保たれており、判別・アイコン抽出・保存パス算出
/// はすべて `FloatingMacroCore` 側 (`AppDropClassifier`, `ImageIOIconExtractor`,
/// `IconAssetSaver`) で行われ、単体テストされる。AppKit に依存するのは
/// `NSAlert` の確認ダイアログだけ。
enum PanelDropHandler {

    @MainActor
    static func handleDroppedURLs(_ urls: [URL], presetManager: PresetManager) async {
        guard !urls.isEmpty else { return }
        guard let preset = presetManager.currentPreset else { return }

        // 追加先グループを決める:
        //   - 既存グループがあれば 1 つめ
        //   - 無ければ「ランチャー」グループを自動作成
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

            // アイコン抽出のカスケード (中身検査込み):
            //   0. 共有キャッシュ → 検査
            //   1. ImageIO で .icns 直読み (.app のみ) → 検査
            //   2. NSWorkspace fallback → 検査
            // 取れた段階で preset 配下に PNG を保存し、.app は共有キャッシュにも put。
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

    /// NSAlert で「ボタン化していい？」を確認する。`true` で続行。
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
