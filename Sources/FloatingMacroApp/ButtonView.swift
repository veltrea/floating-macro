import SwiftUI
import AppKit
import FloatingMacroCore

struct MacroButtonView: View {
    let button: ButtonDefinition
    let onTap: () -> Void
    /// Optional: "Edit…" — opens Settings window focused on this button.
    var onEdit: (() -> Void)? = nil
    /// Optional: "Duplicate" — clone into the same group.
    var onDuplicate: (() -> Void)? = nil
    /// Optional: "Delete" — caller should confirm before actually deleting.
    var onDelete: (() -> Void)? = nil
    /// Optional: "Add new button" — add a new button to the same group.
    var onAddToGroup: (() -> Void)? = nil

    @State private var isHovering = false
    @State private var showTooltip = false
    @State private var tooltipTask: Task<Void, Never>?
    @State private var confirmingDelete = false

    /// Attempt to synthesize an icon. Priority:
    ///   1. explicit `icon` (file path / bundle id)
    ///   2. for a `.launch` action whose target looks like an app, infer
    ///      the app icon automatically
    private var inferredImage: NSImage? {
        if let img = IconLoader.image(for: button.icon) {
            return img
        }
        if case .launch(let target) = button.action {
            return IconLoader.image(for: target)
        }
        return nil
    }

    /// Parse `backgroundColor` hex string into a SwiftUI Color. nil = default.
    private var resolvedBackground: Color? {
        guard let hex = button.backgroundColor else { return nil }
        return Color(hex: hex)
    }

    /// Decide the text/icon color. Priority:
    ///   1. explicit `textColor` (parsed as hex)
    ///   2. white if a background color is set (fits Stitch / colorful buttons)
    ///   3. system primary otherwise (respects Dark/Light)
    private var resolvedForeground: Color {
        if let hex = button.textColor, let c = Color(hex: hex) {
            return c
        }
        return button.backgroundColor != nil ? .white : .primary
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                if let img = inferredImage {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 18, height: 18)
                } else if let iconText = button.iconText, !iconText.isEmpty {
                    Text(iconText)
                        .font(.system(size: 14))
                        .foregroundColor(resolvedForeground)
                }
                Text(button.label)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .foregroundColor(resolvedForeground)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(backgroundFill)
            )
        }
        .buttonStyle(.plain)
        .frame(width: button.width.map { CGFloat($0) },
               height: button.height.map { CGFloat($0) })
        .popover(isPresented: $showTooltip, arrowEdge: .bottom) {
            if let tip = button.tooltip, !tip.isEmpty {
                Text(tip)
                    .font(.system(size: 11))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .fixedSize()
            }
        }
        .onHover { hovering in
            isHovering = hovering
            tooltipTask?.cancel()
            if hovering, let tip = button.tooltip, !tip.isEmpty {
                tooltipTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeIn(duration: 0.15)) {
                        showTooltip = true
                    }
                }
            } else {
                withAnimation(.easeOut(duration: 0.1)) {
                    showTooltip = false
                }
            }
        }
        .contextMenu {
            if let onEdit = onEdit {
                Button {
                    onEdit()
                } label: {
                    Label("編集...", systemImage: "pencil")
                }
            }
            if let onDuplicate = onDuplicate {
                Button {
                    onDuplicate()
                } label: {
                    Label("複製", systemImage: "plus.square.on.square")
                }
            }
            if let onAddToGroup = onAddToGroup {
                Button {
                    onAddToGroup()
                } label: {
                    Label("新規ボタンを追加", systemImage: "plus.circle")
                }
            }
            if onDelete != nil {
                Divider()
                Button(role: .destructive) {
                    confirmingDelete = true
                } label: {
                    Label("削除...", systemImage: "trash")
                }
            }
        }
        .confirmationDialog(
            "このボタンを削除しますか?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("「\(button.label)」を削除", role: .destructive) {
                onDelete?()
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("この操作は元に戻せません。")
        }
    }

    private var backgroundFill: Color {
        if let custom = resolvedBackground {
            return isHovering ? custom.opacity(0.75) : custom
        }
        return isHovering ? Color.accentColor.opacity(0.15) : Color.clear
    }
}

struct GroupView: View {
    let group: ButtonGroup
    let onButtonTap: (ButtonDefinition) -> Void
    var onGroupEdit: (() -> Void)? = nil
    var onButtonEdit: ((ButtonDefinition) -> Void)? = nil
    var onButtonDuplicate: ((ButtonDefinition) -> Void)? = nil
    var onButtonDelete: ((ButtonDefinition) -> Void)? = nil
    var onAddNewToThisGroup: (() -> Void)? = nil

    @State private var collapsed: Bool

    init(group: ButtonGroup,
         onButtonTap: @escaping (ButtonDefinition) -> Void,
         onGroupEdit: (() -> Void)? = nil,
         onButtonEdit: ((ButtonDefinition) -> Void)? = nil,
         onButtonDuplicate: ((ButtonDefinition) -> Void)? = nil,
         onButtonDelete: ((ButtonDefinition) -> Void)? = nil,
         onAddNewToThisGroup: (() -> Void)? = nil) {
        self.group = group
        self.onButtonTap = onButtonTap
        self.onGroupEdit = onGroupEdit
        self.onButtonEdit = onButtonEdit
        self.onButtonDuplicate = onButtonDuplicate
        self.onButtonDelete = onButtonDelete
        self.onAddNewToThisGroup = onAddNewToThisGroup
        self._collapsed = State(initialValue: group.collapsed)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Group header
            Button(action: { withAnimation(.easeInOut(duration: 0.15)) { collapsed.toggle() } }) {
                HStack(spacing: 4) {
                    Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(group.textColor.flatMap { Color(hex: $0) } ?? .secondary)
                        .frame(width: 12)
                    if let iconText = group.iconText {
                        Text(iconText)
                            .font(.system(size: 12))
                    }
                    if let icon = group.icon, let img = IconLoader.image(for: icon) {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 14, height: 14)
                    }
                    Text(group.label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(group.textColor.flatMap { Color(hex: $0) } ?? .secondary)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    group.backgroundColor.flatMap { Color(hex: $0) }.map { color in
                        RoundedRectangle(cornerRadius: 4).fill(color)
                    }
                )
            }
            .buttonStyle(.plain)
            .help(group.tooltip ?? "")
            .contextMenu {
                if let onGroupEdit = onGroupEdit {
                    Button {
                        onGroupEdit()
                    } label: {
                        Label("グループを編集...", systemImage: "pencil")
                    }
                }
            }

            if !collapsed {
                ForEach(group.buttons, id: \.id) { btn in
                    MacroButtonView(
                        button: btn,
                        onTap: { onButtonTap(btn) },
                        onEdit:       onButtonEdit.map      { cb in { cb(btn) } },
                        onDuplicate:  onButtonDuplicate.map { cb in { cb(btn) } },
                        onDelete:     onButtonDelete.map    { cb in { cb(btn) } },
                        onAddToGroup: onAddNewToThisGroup
                    )
                }
                .padding(.leading, 16)
            }
        }
    }
}

struct PresetView: View {
    let preset: Preset
    let onButtonTap: (ButtonDefinition) -> Void
    var onGroupEdit: ((ButtonGroup) -> Void)? = nil
    var onButtonEdit: ((ButtonDefinition) -> Void)? = nil
    var onButtonDuplicate: ((ButtonDefinition) -> Void)? = nil
    var onButtonDelete: ((ButtonDefinition) -> Void)? = nil
    var onButtonAdd: ((ButtonGroup) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(preset.groups, id: \.id) { group in
                GroupView(
                    group: group,
                    onButtonTap: onButtonTap,
                    onGroupEdit: onGroupEdit.map { cb in { cb(group) } },
                    onButtonEdit: onButtonEdit,
                    onButtonDuplicate: onButtonDuplicate,
                    onButtonDelete: onButtonDelete,
                    onAddNewToThisGroup: onButtonAdd.map { cb in { cb(group) } }
                )
            }
        }
        .padding(8)
    }
}

// MARK: - Hex color helper

extension Color {
    /// Parse `#RRGGBB` or `#RRGGBBAA` (case insensitive, `#` optional).
    init?(hex: String) {
        var str = hex.trimmingCharacters(in: .whitespaces)
        if str.hasPrefix("#") { str.removeFirst() }
        guard str.count == 6 || str.count == 8,
              let value = UInt64(str, radix: 16) else {
            return nil
        }
        let r, g, b, a: Double
        if str.count == 6 {
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >>  8) & 0xFF) / 255
            b = Double( value        & 0xFF) / 255
            a = 1.0
        } else {
            r = Double((value >> 24) & 0xFF) / 255
            g = Double((value >> 16) & 0xFF) / 255
            b = Double((value >>  8) & 0xFF) / 255
            a = Double( value        & 0xFF) / 255
        }
        self.init(red: r, green: g, blue: b, opacity: a)
    }
}

