import SwiftUI
import AppKit
import UniformTypeIdentifiers
import FloatingMacroCore

/// 行ベースの DnD 用デリゲート。
/// テキスト UTType でドラッグペイロードを受け取り、ハイライト管理と onDrop を行う。
struct RowDropDelegate: DropDelegate {
    let destGroupId: String
    let beforeButtonId: String?
    let isGroupTarget: Bool
    @Binding var dropTargetGroupId: String?
    @Binding var dropTargetButtonId: String?
    let onDrop: (String) -> Bool

    func dropEntered(info: DropInfo) {
        if isGroupTarget {
            dropTargetGroupId = destGroupId
        } else {
            dropTargetButtonId = beforeButtonId
        }
    }

    func dropExited(info: DropInfo) {
        if isGroupTarget, dropTargetGroupId == destGroupId {
            dropTargetGroupId = nil
        }
        if !isGroupTarget, dropTargetButtonId == beforeButtonId {
            dropTargetButtonId = nil
        }
    }

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.text.identifier])
    }

    func performDrop(info: DropInfo) -> Bool {
        dropTargetGroupId = nil
        dropTargetButtonId = nil
        guard let item = info.itemProviders(for: [UTType.text.identifier]).first else {
            return false
        }
        // ペイロード読み出しは非同期。メインスレッドをブロックしないこと。
        // 同期 wait + main.sync の組み合わせは確実にデッドロックする。
        let onDrop = self.onDrop
        item.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { data, _ in
            let payload: String?
            if let str = data as? String {
                payload = str
            } else if let d = data as? Data, let s = String(data: d, encoding: .utf8) {
                payload = s
            } else {
                payload = nil
            }
            guard let payload else { return }
            DispatchQueue.main.async { _ = onDrop(payload) }
        }
        return true
    }
}
