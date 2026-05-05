import SwiftUI
import AppKit
import FloatingMacroCore

/// Launchpad 風のアイコン格子セル 1 個。`AppLauncherPickerSheet` と
/// `AppIconPicker` で共有して使う。
///
/// `.task { await loadIcon() }` で表示されたタイミングで非同期にアイコンを読む。
/// `LazyVGrid` はスクロールで見えてないセルを作らないので、大量アプリでも
/// 実際のアイコン抽出は visible 範囲のみ。
///
/// アイコン抽出はカスケード:
/// 1. 共有 `AppIconCache` (起動時 prewarm でほぼヒット想定)
/// 2. `ImageIOIconExtractor` の async API
/// 3. `NSWorkspaceIconFallback` (UTM や Books のような Assets.car-only / 空 .icns 用)
/// 各段で `IconContentValidator` を通して空 PNG を次段に降ろす。
struct AppGridCell: View {
    let entry: AppEntry
    let isSelected: Bool
    let cellSize: CGFloat
    let extractor: ImageIOIconExtractor
    let onSelect: () -> Void
    let onActivate: () -> Void

    @State private var icon: NSImage? = nil

    private var iconSize: CGFloat { cellSize * 0.6 }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                if let icon = icon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: iconSize, height: iconSize)
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.secondary.opacity(0.12))
                        .frame(width: iconSize, height: iconSize)
                }
            }
            Text(entry.displayName)
                .font(.system(size: 11))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: cellSize - 8)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: cellSize, height: cellSize)
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.30) : Color.clear)
        )
        .contentShape(Rectangle())
        .gesture(
            // ダブルクリック → activate (追加 / 決定)
            TapGesture(count: 2).onEnded { onActivate() }
        )
        .simultaneousGesture(
            // シングルクリック → 選択のみ
            TapGesture(count: 1).onEnded { onSelect() }
        )
        .help(entry.bundleIdentifier ?? entry.url.path)
        .task { await loadIcon() }
    }

    private func loadIcon() async {
        if let data = await AppIconCache.shared.get(for: entry.url),
           IconContentValidator.hasMeaningfulContent(pngData: data) {
            icon = NSImage(data: data)
            return
        }
        if let data = try? await extractor.extractPNGAsync(from: entry.url, size: 128),
           IconContentValidator.hasMeaningfulContent(pngData: data) {
            await AppIconCache.shared.put(for: entry.url, data: data)
            icon = NSImage(data: data)
            return
        }
        if let data = NSWorkspaceIconFallback.extractPNG(appURL: entry.url, size: 128),
           IconContentValidator.hasMeaningfulContent(pngData: data) {
            await AppIconCache.shared.put(for: entry.url, data: data)
            icon = NSImage(data: data)
        }
    }
}
