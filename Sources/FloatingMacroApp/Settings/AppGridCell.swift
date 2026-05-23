import SwiftUI
import AppKit
import FloatingMacroCore

/// One icon grid cell in Launchpad style. `AppLauncherPickerSheet` and
/// Use shared with `AppIconPicker`.
///
/// Display the icon asynchronously at the timing shown by `.task { await loadIcon() }`.
/// LazyVGrid does not create invisible cells due to scrolling, so it works well even in large applications.
/// Actual icon extraction is only in the visible range.
///
/// Icon extraction cascade:
/// Shared AppIconCache (expected to hit almost all the time on launch)
/// 2. Async API for `ImageIOIconExtractor`
/// 3. `NSWorkspaceIconFallback` (for UTM and Books, assets-only / empty .icns)
/// Drop empty PNGs to the next stage through `IconContentValidator`.
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
            // double-click → activate (addition / decision)
            TapGesture(count: 2).onEnded { onActivate() }
        )
        .simultaneousGesture(
            // Single-click → Only selection
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
