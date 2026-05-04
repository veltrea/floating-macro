import SwiftUI
import AppKit
import FloatingMacroCore

/// `/Applications` 配下の `.app` を Launchpad のような格子で表示し、
/// 選んで現在のグループに `launch` ボタンとして追加するシート。
/// DnD と並列の追加導線で、キーボード派 / 身体的にマウスドラッグが
/// 難しいユーザー向け。
///
/// 列挙 (`FileSystemAppListProvider`)・アイコン抽出 (`ImageIOIconExtractor`)・
/// 内容検査 (`IconContentValidator`)・キャッシュ (`AppIconCache`)・
/// 保存 (`IconAssetSaver`) はすべて `FloatingMacroCore` 側で単体テスト済み。
/// このファイルは UI ラッパーのみ。
///
/// 起動時 `AppIconPrewarmer` が `/Applications` 全アプリのアイコンを
/// バックグラウンドでキャッシュ済みなので、各セルは 0th 段の `cache.get`
/// だけでヒットして即時表示される (Launchpad 同等の体感)。キャッシュ
/// 未生成のアプリだけ ImageIO → NSWorkspace のカスケードを裏で叩く。
struct AppLauncherPickerSheet: View {
    @ObservedObject var presetManager: PresetManager
    let groupId: String
    @Binding var isPresented: Bool

    @State private var apps: [AppEntry] = []
    @State private var loading: Bool = true
    @State private var query: String = ""
    @State private var selectedURL: URL? = nil

    private let provider: AppListProvider = FileSystemAppListProvider()
    private let extractor = ImageIOIconExtractor()

    /// セルあたりの正方形サイズ (アイコン + ラベル枠)。Launchpad 比で少し
    /// 小さめの 96px。8〜9 アプリ/行を想定。
    private let cellSize: CGFloat = 96

    private var filteredApps: [AppEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return apps }
        return apps.filter { entry in
            if entry.displayName.range(of: q, options: .caseInsensitive) != nil { return true }
            if let bid = entry.bundleIdentifier,
               bid.range(of: q, options: .caseInsensitive) != nil { return true }
            return false
        }
    }

    private var selectedEntry: AppEntry? {
        guard let url = selectedURL else { return nil }
        return apps.first { $0.url == url }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("アプリを選んでボタンに追加")
                .font(.headline)
            Text("`/Applications`・`/System/Applications`・`~/Applications` を一覧します。Bundle ID も検索対象です。")
                .font(.caption)
                .foregroundColor(.secondary)

            TextField("検索 (アプリ名 / bundle id)", text: $query)
                .textFieldStyle(.roundedBorder)

            gridScrollView

            Divider()

            footerBar
        }
        .padding(16)
        .frame(width: 880, height: 620)
        .onAppear { loadApps() }
    }

    // MARK: - Subviews

    private var gridScrollView: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: cellSize, maximum: cellSize),
                                    spacing: 4)],
                spacing: 4
            ) {
                ForEach(filteredApps, id: \.url) { entry in
                    AppGridCell(
                        entry: entry,
                        isSelected: selectedURL == entry.url,
                        cellSize: cellSize,
                        extractor: extractor,
                        onSelect: { selectedURL = entry.url },
                        onActivate: {
                            selectedURL = entry.url
                            Task { await commit() }
                        }
                    )
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
        }
        .background(Color.black.opacity(0.06))
        .cornerRadius(8)
    }

    private var footerBar: some View {
        HStack(spacing: 8) {
            if loading {
                ProgressView().scaleEffect(0.6)
                Text("読み込み中…").font(.caption).foregroundColor(.secondary)
            } else if let entry = selectedEntry {
                Text(entry.displayName)
                    .font(.callout)
                    .bold()
                    .lineLimit(1)
                if let bid = entry.bundleIdentifier {
                    Text(bid)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } else {
                Text("\(filteredApps.count) / \(apps.count) 件 — クリックで選択 / ダブルクリックで追加")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("キャンセル") { isPresented = false }
                .keyboardShortcut(.cancelAction)
            Button("追加") { Task { await commit() } }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedURL == nil)
        }
    }

    // MARK: - Actions

    private func loadApps() {
        loading = true
        let provider = self.provider
        Task.detached(priority: .userInitiated) {
            let result: [AppEntry] = (try? provider.availableApplications()) ?? []
            await MainActor.run {
                self.apps = result
                self.loading = false
            }
        }
    }

    private func commit() async {
        guard let entry = selectedEntry else { return }
        guard let preset = presetManager.currentPreset else { return }

        let buttonId = "b-\(Int.random(in: 1000...9999))"

        // カスケード: 共有キャッシュ → ImageIO → NSWorkspace
        // (各段で IconContentValidator)
        var iconBytes: Data? = nil
        if let cached = await AppIconCache.shared.get(for: entry.url),
           IconContentValidator.hasMeaningfulContent(pngData: cached) {
            iconBytes = cached
        }
        if iconBytes == nil,
           let data = try? extractor.extractPNG(from: entry.url, size: 64),
           IconContentValidator.hasMeaningfulContent(pngData: data) {
            await AppIconCache.shared.put(for: entry.url, data: data)
            iconBytes = data
        }
        if iconBytes == nil,
           let data = NSWorkspaceIconFallback.extractPNG(appURL: entry.url, size: 64),
           IconContentValidator.hasMeaningfulContent(pngData: data) {
            await AppIconCache.shared.put(for: entry.url, data: data)
            iconBytes = data
        }

        let iconPath: String? = iconBytes.flatMap {
            try? IconAssetSaver.saveData(
                $0, buttonId: buttonId, presetName: preset.name)
        }

        let target = entry.bundleIdentifier ?? entry.url.path
        let tooltip: String
        if let bid = entry.bundleIdentifier {
            tooltip = "\(entry.displayName) (\(bid))"
        } else {
            tooltip = entry.url.path
        }
        let button = ButtonDefinition(
            id: buttonId,
            label: entry.displayName,
            icon: iconPath,
            iconText: iconPath == nil ? "📦" : nil,
            tooltip: tooltip,
            action: .launch(target: target)
        )

        await MainActor.run {
            _ = presetManager.addButton(button, toGroupId: groupId)
            isPresented = false
        }
    }
}

// MARK: - Grid Cell

/// Launchpad 風のアイコン格子のセル 1 個。
/// `.task { await loadIcon() }` で表示されたタイミングで非同期に
/// アイコンを読む。LazyVGrid はスクロールで見えてないセルを作らないので、
/// 大量アプリでも実際の抽出は visible 範囲のみ。
private struct AppGridCell: View {
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
            // Double click → 追加 (commit)
            TapGesture(count: 2).onEnded { onActivate() }
        )
        .simultaneousGesture(
            // Single click → 選択のみ (double が拾われた場合も発火するが、
            // selection の冪等性で副作用なし)
            TapGesture(count: 1).onEnded { onSelect() }
        )
        .help(entry.bundleIdentifier ?? entry.url.path)
        .task { await loadIcon() }
    }

    private func loadIcon() async {
        // 0th: キャッシュ (起動時 prewarm でほぼヒット想定)
        if let data = await AppIconCache.shared.get(for: entry.url),
           IconContentValidator.hasMeaningfulContent(pngData: data) {
            icon = NSImage(data: data)
            return
        }
        // 1st: ImageIO
        if let data = try? await extractor.extractPNGAsync(from: entry.url, size: 128),
           IconContentValidator.hasMeaningfulContent(pngData: data) {
            await AppIconCache.shared.put(for: entry.url, data: data)
            icon = NSImage(data: data)
            return
        }
        // 2nd: NSWorkspace fallback (UTM・Books など)
        if let data = NSWorkspaceIconFallback.extractPNG(appURL: entry.url, size: 128),
           IconContentValidator.hasMeaningfulContent(pngData: data) {
            await AppIconCache.shared.put(for: entry.url, data: data)
            icon = NSImage(data: data)
        }
    }
}
