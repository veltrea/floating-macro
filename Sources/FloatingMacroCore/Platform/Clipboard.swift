import AppKit

public struct ClipboardItem {
    public let type: NSPasteboard.PasteboardType
    public let data: Data
}

public struct ClipboardSnapshot {
    public let items: [[ClipboardItem]]
}

public protocol ClipboardProtocol {
    func save() -> ClipboardSnapshot
    func restore(_ snapshot: ClipboardSnapshot)
    func setString(_ s: String)
}

public final class SystemClipboard: ClipboardProtocol {
    public static let shared = SystemClipboard()

    private var pasteboard: NSPasteboard { NSPasteboard.general }

    public func save() -> ClipboardSnapshot {
        var allItems: [[ClipboardItem]] = []
        if let items = pasteboard.pasteboardItems {
            for item in items {
                var typeData: [ClipboardItem] = []
                for type in item.types {
                    if let data = item.data(forType: type) {
                        typeData.append(ClipboardItem(type: type, data: data))
                    }
                }
                allItems.append(typeData)
            }
        }
        return ClipboardSnapshot(items: allItems)
    }

    public func restore(_ snapshot: ClipboardSnapshot) {
        pasteboard.clearContents()
        var pasteboardItems: [NSPasteboardItem] = []
        for itemData in snapshot.items {
            let item = NSPasteboardItem()
            for ci in itemData {
                item.setData(ci.data, forType: ci.type)
            }
            pasteboardItems.append(item)
        }
        if !pasteboardItems.isEmpty {
            pasteboard.writeObjects(pasteboardItems)
        }
    }

    public func setString(_ s: String) {
        pasteboard.clearContents()
        pasteboard.setString(s, forType: .string)
    }
}
