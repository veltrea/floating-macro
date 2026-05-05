import SwiftUI
import AppKit
import FloatingMacroCore

/// インストール済みアプリのアイコンを選んでボタン / グループのアイコンに
/// 設定するシート。`AppLauncherPickerSheet` と同じ Launchpad 風フラット表示で、
/// `/Applications` 配下を `FileSystemAppListProvider` で再帰的に列挙する。
///
/// 違い: ピッカーで選んだ結果は **bundle id** を `selection` バインディングに
/// 書き戻すだけで、ボタン本体は作らない (icon ソースの選定だけ)。
///
/// 旧実装は `AppIconCatalog` のハードコード bundle id リスト + 4 ジャンル分類
/// だったが、リストにないアプリは全く出てこない設計だったので撤廃した。
struct AppIconPicker: View {
    /// 選択時に書き込まれる bundle id (Settings 側の `iconPath` バインディング)。
    @Binding var selection: String
    let onClose: () -> Void

    @State private var apps: [AppEntry] = []
    @State private var loading: Bool = true
    @State private var query: String = ""
    @State private var selectedURL: URL? = nil

    private let provider: AppListProvider = FileSystemAppListProvider()
    private let extractor = ImageIOIconExtractor()

    /// セルあたりの正方形サイズ。AppLauncherPickerSheet と同じ 96px。
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
            Text("アプリのアイコンを選択")
                .font(.headline)
            Text("`/Applications`・`/System/Applications`・`~/Applications` をサブフォルダ込みで一覧します。Bundle ID も検索対象です。")
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
                            commitSelection()
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
                Text("\(filteredApps.count) / \(apps.count) 件 — クリックで選択 / ダブルクリックで決定")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("キャンセル", action: onClose)
                .keyboardShortcut(.cancelAction)
            Button("決定") { commitSelection() }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedURL == nil || selectedEntry?.bundleIdentifier == nil)
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

    /// 選んだアプリの bundle id をバインディングに書き込んでシートを閉じる。
    /// bundle id が無いアプリ (Info.plist 欠落) は icon ソースとして使えないので
    /// 「決定」ボタンが無効化されて到達しない。
    private func commitSelection() {
        guard let entry = selectedEntry,
              let bid = entry.bundleIdentifier
        else { return }
        selection = bid
        onClose()
    }
}
