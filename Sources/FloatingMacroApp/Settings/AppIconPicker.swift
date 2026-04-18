import SwiftUI
import AppKit
import FloatingMacroCore

/// Grid picker for well-known application icons. Shown as a sheet from the
/// GroupEditor / ButtonEditor, analogous to `SFSymbolPicker`.
struct AppIconPicker: View {
    /// Current selection — receives the bundle identifier on pick.
    @Binding var selection: String
    let onClose: () -> Void

    @State private var categoryId: String = AppIconCatalog.categories.first?.id ?? "ai"
    @State private var filter: String = ""

    private let columns = Array(
        repeating: GridItem(.fixed(72), spacing: 10),
        count: 5
    )

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            categoryTabs
            Divider()
            content
            footer
        }
        .frame(width: 480, height: 420)
    }

    // MARK: - Subviews

    private var header: some View {
        HStack {
            Text("アプリアイコンを選択")
                .font(.headline)
            Spacer()
            TextField("検索", text: $filter)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
        }
        .padding(10)
    }

    private var categoryTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(AppIconCatalog.categories, id: \.id) { cat in
                    Button {
                        categoryId = cat.id
                    } label: {
                        Text(cat.label)
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(categoryId == cat.id
                                          ? Color.accentColor.opacity(0.2)
                                          : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }

    private var content: some View {
        Group {
            if visibleEntries.isEmpty {
                VStack {
                    Text("インストール済みのアプリが見つかりません")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(visibleEntries, id: \.bundleId) { entry in
                            appCell(entry)
                        }
                    }
                    .padding(10)
                }
            }
        }
        .frame(minHeight: 240)
    }

    private func appCell(_ entry: AppIconEntry) -> some View {
        let isSelected = selection == entry.bundleId
        return Button {
            selection = entry.bundleId
        } label: {
            VStack(spacing: 4) {
                if let img = appIcon(for: entry.bundleId) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 40, height: 40)
                } else {
                    Image(systemName: "app.dashed")
                        .font(.system(size: 28))
                        .frame(width: 40, height: 40)
                        .foregroundColor(.secondary)
                }
                Text(entry.displayName)
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .foregroundColor(.primary)
            }
            .frame(width: 72, height: 68)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.25) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .help(entry.bundleId)
    }

    private var footer: some View {
        HStack {
            Text(selection.isEmpty ? "未選択" : selection)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(1)
            Spacer()
            Button("閉じる", action: onClose)
                .keyboardShortcut(.defaultAction)
        }
        .padding(10)
    }

    // MARK: - Data

    private var visibleEntries: [AppIconEntry] {
        let q = filter.trimmingCharacters(in: .whitespaces).lowercased()
        let installed = AppIconCatalog.installedEntries { bundleId in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) != nil
        }

        let filtered: [AppIconEntry]
        if q.isEmpty {
            filtered = installed.filter { $0.categoryId == categoryId }
        } else {
            filtered = installed.filter {
                $0.displayName.lowercased().contains(q) ||
                $0.bundleId.lowercased().contains(q)
            }
        }
        return filtered
    }

    private func appIcon(for bundleId: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
