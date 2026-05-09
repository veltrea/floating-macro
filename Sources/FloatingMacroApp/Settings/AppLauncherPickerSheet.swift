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
            Text(L("アプリを選んでボタンに追加_d779e9"))
                .font(.headline)
            Text(L("Applications_System_Applications_Applications_を一覧し_2c2155"))
                .font(.caption)
                .foregroundColor(.secondary)

            TextField(L("検索_アプリ名_bundle_id_850b64"), text: $query)
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
                Text(L("読み込み中_4699f5")).font(.caption).foregroundColor(.secondary)
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
                Text(L_("app_filter_count_double_click_add", filteredApps.count, apps.count))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button(L("キャンセル_6ef349")) { isPresented = false }
                .keyboardShortcut(.cancelAction)
            Button(L("追加_7dc3a5")) { Task { await commit() } }
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

// `AppGridCell` は別ファイル ([AppGridCell.swift](AppGridCell.swift)) に切り出し、
// `AppIconPicker` と共有している。
