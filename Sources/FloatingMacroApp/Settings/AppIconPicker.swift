import SwiftUI
import AppKit
import FloatingMacroCore

/// Select icon of installed app and set to button/group icon
/// Setting sheet. Flat display similar to Launchpad, same as `AppLauncherPickerSheet`.
/// Enumerate recursively under `/Applications` using `FileSystemAppListProvider`.
///
/// Difference: The result of selecting with the picker is bound to the `selection` binding as a **bundle ID**.
/// Just undo writing, do not create the button itself (only selecting icon source).
///
/// Old implementation uses hard-coded bundle ID list of `AppIconCatalog` and 4 genre categories.
/// However, since the design did not include apps that were not in the list at all, it was abolished.
struct AppIconPicker: View {
    /// Bundle ID written when selected (Settings side `iconPath` binding).
    @Binding var selection: String
    let onClose: () -> Void

    @State private var apps: [AppEntry] = []
    @State private var loading: Bool = true
    @State private var query: String = ""
    @State private var selectedURL: URL? = nil

    private let provider: AppListProvider = FileSystemAppListProvider()
    private let extractor = ImageIOIconExtractor()

    /// Size of square cells per cell. Same as AppLauncherPickerSheet, 96px.
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
            Text(L("アプリのアイコンを選択_c79deb"))
                .font(.headline)
            Text(L("Applications_System_Applications_Applications_をサブフ_fd878e"))
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
                Text(L_("app_filter_count_double_click_done", filteredApps.count, apps.count))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button(L("キャンセル_6ef349"), action: onClose)
                .keyboardShortcut(.cancelAction)
            Button(L("決定_56346e")) { commitSelection() }
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

    /// Write the bundle ID of the selected app into the binding and close the sheet.
    /// Cannot use as icon source because bundle ID is missing (Info.plist missing)
    /// The "Decide" button is disabled and cannot be reached.
    private func commitSelection() {
        guard let entry = selectedEntry,
              let bid = entry.bundleIdentifier
        else { return }
        selection = bid
        onClose()
    }
}
