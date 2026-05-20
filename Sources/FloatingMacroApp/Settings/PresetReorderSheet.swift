import SwiftUI
import AppKit
import UniformTypeIdentifiers
import FloatingMacroCore

// MARK: - Preset reorder sheet

/// プリセット表示順を DnD で並べ替えるシート。確定するまでメモリ上で
/// 編集し、「保存」で `presetManager.reorderPresets` を呼んで永続化する。
struct PresetReorderSheet: View {
    @ObservedObject var presetManager: PresetManager
    @Binding var isPresented: Bool

    @State private var workingOrder: [PresetEntry] = []
    @State private var dragSourceId: String?
    @State private var dropTargetId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("プリセットの並べ替え_56a714"))
                .font(.headline)
            Text(L("行をドラッグして順序を変更し_保存_を押してください_e37583"))
                .font(.caption)
                .foregroundColor(.secondary)

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(workingOrder) { entry in
                        presetRow(entry)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(minHeight: 240, maxHeight: 480)
            .background(Color(NSColor.textBackgroundColor).opacity(0.4))
            .cornerRadius(6)

            HStack {
                Button(L("キャンセル_6ef349")) {
                    isPresented = false
                }
                Spacer()
                Button(L("アルファベット順にリセット_eff49f")) {
                    workingOrder = presetManager.presetEntries.sorted { $0.name < $1.name }
                }
                Button(L("保存_be5fbb")) {
                    let ids = workingOrder.map { $0.name }
                    _ = presetManager.reorderPresets(ids: ids)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear {
            workingOrder = presetManager.presetEntries
        }
    }

    private func presetRow(_ entry: PresetEntry) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .foregroundColor(.secondary)
            Text(entry.displayName)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            Text(entry.name)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(dropTargetId == entry.id
                      ? Color.accentColor.opacity(0.18)
                      : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(dragSourceId == entry.id
                        ? Color.accentColor.opacity(0.6)
                        : Color.clear,
                        lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onDrag {
            dragSourceId = entry.id
            return NSItemProvider(object: "p:\(entry.id)" as NSString)
        }
        .onDrop(of: [.text],
                delegate: PresetRowDropDelegate(
                    destId: entry.id,
                    workingOrder: $workingOrder,
                    dragSourceId: $dragSourceId,
                    dropTargetId: $dropTargetId
                ))
    }
}

/// プリセット並べ替えシート用の DropDelegate。テキストペイロード
/// `p:<id>` を読み取り、ソース行をドロップ先の直前に挿入する。
private struct PresetRowDropDelegate: DropDelegate {
    let destId: String
    @Binding var workingOrder: [PresetEntry]
    @Binding var dragSourceId: String?
    @Binding var dropTargetId: String?

    func dropEntered(info: DropInfo) {
        dropTargetId = destId
    }

    func dropExited(info: DropInfo) {
        if dropTargetId == destId { dropTargetId = nil }
    }

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.text.identifier])
    }

    func performDrop(info: DropInfo) -> Bool {
        dropTargetId = nil
        defer { dragSourceId = nil }
        guard let item = info.itemProviders(for: [UTType.text.identifier]).first else {
            return false
        }
        let dest = destId
        item.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { data, _ in
            let payload: String?
            if let s = data as? String { payload = s }
            else if let d = data as? Data, let s = String(data: d, encoding: .utf8) { payload = s }
            else { payload = nil }
            guard let payload, payload.hasPrefix("p:") else { return }
            let srcId = String(payload.dropFirst(2))
            DispatchQueue.main.async {
                guard srcId != dest,
                      let srcIdx = workingOrder.firstIndex(where: { $0.id == srcId }),
                      let dstIdx = workingOrder.firstIndex(where: { $0.id == dest })
                else { return }
                let item = workingOrder.remove(at: srcIdx)
                let insertAt = srcIdx < dstIdx ? dstIdx - 1 : dstIdx
                workingOrder.insert(item, at: insertAt)
            }
        }
        return true
    }
}
