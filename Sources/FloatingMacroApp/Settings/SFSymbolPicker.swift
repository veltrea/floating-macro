import SwiftUI
import AppKit
import FloatingMacroCore

/// Grid picker for SF Symbols, shown as a sheet from the ButtonEditor.
/// Renders each symbol via `Image(systemName:)` — the OS does the drawing,
/// so no bitmap assets are bundled.
struct SFSymbolPicker: View {
    /// Current selection (as stored in the button's `icon` field, i.e. with
    /// the `sf:` prefix).
    @Binding var selection: String
    /// Dismiss hook, wired by the parent sheet presenter.
    let onClose: () -> Void

    @State private var categoryId: String = SFSymbolCatalog.categories.first?.id
        ?? "general"
    @State private var filter: String = ""

    private let columns = Array(
        repeating: GridItem(.fixed(44), spacing: 8),
        count: 8
    )

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            categoryTabs
            Divider()
            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(visibleSymbols, id: \.self) { name in
                        symbolCell(name)
                    }
                }
                .padding(10)
            }
            .frame(minHeight: 280)
            footer
        }
        .frame(width: 540, height: 480)
    }

    // MARK: - Subviews

    private var header: some View {
        HStack {
            Text("SF Symbol を選択")
                .font(.headline)
            Spacer()
            TextField("検索 (例: star, mic, lock)", text: $filter)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
        }
        .padding(10)
    }

    private var categoryTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(SFSymbolCatalog.categories, id: \.id) { cat in
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

    private func symbolCell(_ name: String) -> some View {
        let isSelected = selection == SFSymbolCatalog.reference(for: name)
        return Button {
            selection = SFSymbolCatalog.reference(for: name)
        } label: {
            VStack(spacing: 2) {
                Image(systemName: name)
                    .font(.system(size: 18))
                    .frame(width: 36, height: 36)
                    .foregroundColor(.primary)
            }
            .frame(width: 44, height: 44)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isSelected ? Color.accentColor.opacity(0.25) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .help(name)
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

    // MARK: - Filter

    private var visibleSymbols: [String] {
        let base: [String]
        if filter.trimmingCharacters(in: .whitespaces).isEmpty {
            base = SFSymbolCatalog.category(id: categoryId)?.symbols ?? []
        } else {
            // 検索時は全カテゴリから横断検索
            let q = filter.lowercased()
            base = SFSymbolCatalog.all.filter { $0.contains(q) }
        }
        return base
    }
}
