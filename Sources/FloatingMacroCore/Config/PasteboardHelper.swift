import Foundation
import AppKit
import UniformTypeIdentifiers

public enum PasteboardHelper {

    // MARK: - Custom UTTypes

    static let buttonType = UTType(exportedAs: "com.floatingmacro.button")
    static let groupType  = UTType(exportedAs: "com.floatingmacro.group")

    // MARK: - Copy

    public static func copyButton(_ button: ButtonDefinition) {
        guard let data = try? JSONEncoder().encode(button) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(data, forType: .init(buttonType.identifier))
    }

    public static func copyGroup(_ group: ButtonGroup) {
        guard let data = try? JSONEncoder().encode(group) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(data, forType: .init(groupType.identifier))
    }

    // MARK: - Peek

    public static func hasButton() -> Bool {
        NSPasteboard.general.data(forType: .init(buttonType.identifier)) != nil
    }

    public static func hasGroup() -> Bool {
        NSPasteboard.general.data(forType: .init(groupType.identifier)) != nil
    }

    // MARK: - Paste (returns a copy with fresh IDs)

    public static func pasteButton() -> ButtonDefinition? {
        guard let data = NSPasteboard.general.data(forType: .init(buttonType.identifier)),
              let src = try? JSONDecoder().decode(ButtonDefinition.self, from: data)
        else { return nil }
        return ButtonDefinition(
            id: freshButtonId(),
            label: src.label,
            icon: src.icon,
            iconText: src.iconText,
            backgroundColor: src.backgroundColor,
            textColor: src.textColor,
            width: src.width,
            height: src.height,
            tooltip: src.tooltip,
            confirm: src.confirm,
            confirmMessage: src.confirmMessage,
            confirmDestructive: src.confirmDestructive,
            thumbnail: src.thumbnail,
            cardThumbnailMode: src.cardThumbnailMode,
            action: src.action
        )
    }

    public static func pasteGroup() -> ButtonGroup? {
        guard let data = NSPasteboard.general.data(forType: .init(groupType.identifier)),
              let src = try? JSONDecoder().decode(ButtonGroup.self, from: data)
        else { return nil }
        let newButtons = src.buttons.map { b in
            ButtonDefinition(
                id: freshButtonId(),
                label: b.label,
                icon: b.icon,
                iconText: b.iconText,
                backgroundColor: b.backgroundColor,
                textColor: b.textColor,
                width: b.width,
                height: b.height,
                tooltip: b.tooltip,
                confirm: b.confirm,
                confirmMessage: b.confirmMessage,
                confirmDestructive: b.confirmDestructive,
                thumbnail: b.thumbnail,
                cardThumbnailMode: b.cardThumbnailMode,
                action: b.action
            )
        }
        return ButtonGroup(
            id: freshGroupId(),
            label: src.label,
            icon: src.icon,
            iconText: src.iconText,
            backgroundColor: src.backgroundColor,
            textColor: src.textColor,
            tooltip: src.tooltip,
            collapsed: false,
            displayType: src.displayType,
            buttons: newButtons
        )
    }

    // MARK: - ID generators

    private static func freshButtonId() -> String {
        "b-\(Int.random(in: 10000...99999))"
    }

    private static func freshGroupId() -> String {
        "g-\(Int.random(in: 10000...99999))"
    }
}
