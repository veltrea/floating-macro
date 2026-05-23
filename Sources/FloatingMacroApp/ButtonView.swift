import SwiftUI
import AppKit
import FloatingMacroCore
import WaterfallGrid

/// Internal state machine for push feedback. `MacroButtonView` executes immediately after
/// Running → Success (1 second) → Idle transition using a custom timer.
/// The action is currently fire-and-forget, so "execution complete = success" (P2-10).
/// Failure red feedback will ensure that `executeButton` returns results in the future.
/// Connect after completion.
private enum ExecutionFeedback {
    case idle
    case running
    case success
    case failure
}

struct MacroButtonView: View {
    let button: ButtonDefinition
    let onTap: () -> Void
    /// Display type of parent group. `.icon` (default) / `.wide` / `.card` / `.grid` for
    /// Each branch into separate layouts. Editor preview, etc.,
    /// Without context, omitting the caller results in existing behavior.
    var displayType: GroupDisplayType = .icon
    /// Icon display size in grid/icon layout.
    var iconSize: IconSize = .medium
    /// Whether to display labels in grid layout.
    var showLabel: Bool = true
    var onEdit: (() -> Void)? = nil
    var onCut: (() -> Void)? = nil
    var onDuplicate: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    var onAddToGroup: (() -> Void)? = nil
    var onPasteButton: ((String) -> Void)? = nil

    @State private var isHovering = false
    @State private var showTooltip = false
    @State private var tooltipTask: Task<Void, Never>?
    @State private var confirmingDelete = false
    @State private var confirmingExecute = false
    @State private var feedback: ExecutionFeedback = .idle
    @State private var feedbackTask: Task<Void, Never>?

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

    /// Image type used for Card. Integrated into icon, same as inferredImage.
    private var thumbnailImage: NSImage? { inferredImage }

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

    /// Frame border color for state feedback. When idle, do not draw the frame border with `.clear`.
    private var feedbackBorderColor: Color {
        switch feedback {
        case .idle:    return .clear
        case .running: return .yellow
        case .success: return .green
        case .failure: return .red
        }
    }

    var body: some View {
        Button(action: handleTap) {
            buttonContent
        }
        .buttonStyle(.plain)
        // Identifier used by the Control API's button_press tool to locate
        // this view via the macOS Accessibility tree. Required for the
        // synthesized real-click path that exercises actual hit-testing
        // (otherwise tests can't catch "the click never reached the
        // button" bugs like window obstruction or hit-test breakage).
        .accessibilityIdentifier("fm-button-\(button.id)")
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
            if let onCut = onCut {
                Button {
                    onCut()
                } label: {
                    Label(L("切り取り_cut"), systemImage: "scissors")
                }
            }
            Button {
                PasteboardHelper.copyButton(button)
            } label: {
                Label(L("コピー_copy"), systemImage: "doc.on.doc")
            }
            if let onPasteButton = onPasteButton {
                Button {
                    onPasteButton(button.id)
                } label: {
                    Label(L("貼り付け_paste"), systemImage: "doc.on.clipboard")
                }
                .disabled(!PasteboardHelper.hasButton())
            }
            if let onDuplicate = onDuplicate {
                Button {
                    onDuplicate()
                } label: {
                    Label(L("複製_duplicate"), systemImage: "plus.square.on.square")
                }
            }
            Divider()
            if let onEdit = onEdit {
                Button {
                    onEdit()
                } label: {
                    Label(L("編集_ac1264"), systemImage: "pencil")
                }
            }
            if let onAddToGroup = onAddToGroup {
                Button {
                    onAddToGroup()
                } label: {
                    Label(L("新規ボタンを追加_03ae9c"), systemImage: "plus.circle")
                }
            }
            if onDelete != nil {
                Divider()
                Button(role: .destructive) {
                    confirmingDelete = true
                } label: {
                    Label(L("削除_eec57b"), systemImage: "trash")
                }
            }
        }
        .confirmationDialog(
            L("このボタンを削除しますか_ec2177"),
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button(L_("delete_named_item", button.label), role: .destructive) {
                onDelete?()
            }
            Button(L("キャンセル_6ef349"), role: .cancel) {}
        } message: {
            Text(L("この操作は元に戻せません_3955a5"))
        }
        .confirmationDialog(
            L_("execute_named_item_question", button.label),
            isPresented: $confirmingExecute,
            titleVisibility: .visible
        ) {
            Button(
                button.confirmDestructive ? L("実行する_取り消し不可_b5cb87") : L("実行する_484791"),
                role: button.confirmDestructive ? .destructive : nil
            ) {
                handleConfirmedTap()
            }
            Button(L("キャンセル_6ef349"), role: .cancel) {}
        } message: {
            executeConfirmMessageView()
        }
    }

    /// If onTap is called directly, if ButtonDefinition.confirm is true, insert a confirmation dialog in between.
    private func handleTap() {
        if button.confirm {
            confirmingExecute = true
        } else {
            triggerFeedback()
            onTap()
        }
    }

    /// Output a confirmation dialog and provide feedback when executed via the dialog.
    private func handleConfirmedTap() {
        triggerFeedback()
        onTap()
    }

    /// Start success frame animation on execution.
    /// Since there is no return value indicating success/failure on the action side, currently it is treated as "pressed = success".
    /// Cancel existing tasks to prioritize the latest press if pressed repeatedly.
    private func triggerFeedback() {
        feedbackTask?.cancel()
        feedback = .running
        feedbackTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.2)) { feedback = .success }
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { feedback = .idle }
        }
    }

    /// Switch the layout to be drawn by displayType. The `.icon` retains existing behavior.
    @ViewBuilder
    private var buttonContent: some View {
        switch displayType {
        case .icon: iconLayout
        case .wide: wideLayout
        case .card: cardLayout
        case .grid: gridLayout
        }
    }

    /// Grid: Icon + (optional) label. Finder icon display style.
    /// Unlike card, the app icon/emoticon takes center stage without using a thumbnail.
    private var gridLayout: some View {
        let sz = iconSize.points
        return VStack(spacing: 2) {
            if let img = inferredImage {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: sz, height: sz)
            } else if let iconText = button.iconText, !iconText.isEmpty {
                Text(iconText)
                    .font(.system(size: sz * 0.7))
                    .foregroundColor(resolvedForeground)
                    .frame(width: sz, height: sz)
            } else {
                Image(systemName: "app.dashed")
                    .font(.system(size: sz * 0.6))
                    .foregroundColor(.secondary)
                    .frame(width: sz, height: sz)
            }
            if showLabel {
                Text(button.label)
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .multilineTextAlignment(.center)
                    .foregroundColor(resolvedForeground)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(4)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovering ? Color.accentColor.opacity(0.10) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(feedbackBorderColor, lineWidth: feedback == .idle ? 0 : 2)
        )
    }

    private var iconLayout: some View {
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
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(feedbackBorderColor, lineWidth: feedback == .idle ? 0 : 2)
        )
    }

    /// Wide: Full-width large icon + centered label. Allows up to 2 lines for long titles.
    private var wideLayout: some View {
        HStack(spacing: 10) {
            if let img = inferredImage {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)
            } else if let iconText = button.iconText, !iconText.isEmpty {
                Text(iconText)
                    .font(.system(size: 22))
                    .foregroundColor(resolvedForeground)
                    .frame(width: 28, height: 28)
            } else {
                // Keep left margin even when not in use.
                Color.clear.frame(width: 28, height: 28)
            }
            Text(button.label)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .foregroundColor(resolvedForeground)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(feedbackBorderColor, lineWidth: feedback == .idle ? 0 : 2)
        )
    }

    /// Gallery-style layout with thumbnail on top and title below.
    /// Assuming use in the parent LazyVGrid.
    ///
    /// Layout Strategy:
    /// 1. `Color.clear.aspectRatio(1, .fit)` to get a square box from the cell's width
    /// Place images, emojis, placeholders on top using overlay and clipShape.
    /// An image with `.aspectRatio(.fill)` will be clipped to a square by `clipShape`.
    /// This configuration avoids the problem of Image's intrinsic size stretching ZStack.
    ///
    /// Vertical alignment: LazyVGrid aligns the height of cells within the same row, but labels...
    /// The height of the entire VStack differs between a single-line cell and a two-line cell. By default,
    /// The cells are aligned to the center, and only short label cells have thumbnails below.
    /// above the top edge of the window.
    /// Fix to the top. The position of the thumbnail and label is always the same regardless of the number of label rows.
    private var cardLayout: some View {
        VStack(spacing: 6) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .overlay(thumbnailContent)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(feedbackBorderColor,
                                      lineWidth: feedback == .idle ? 0 : 2)
                )
            Text(button.label)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundColor(resolvedForeground)
                .frame(maxWidth: .infinity, maxHeight: 30, alignment: .top)
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isHovering ? Color.accentColor.opacity(0.10) : Color.clear)
        )
    }

    /// Thumbnail content placed on a square box in Card layout.
    /// If button.cardThumbnailMode is .fill, use outer crop; if .fit, use inner padding.
    @ViewBuilder
    private var thumbnailContent: some View {
        if let img = thumbnailImage {
            if button.cardThumbnailMode == .fit {
                ZStack {
                    (resolvedBackground ?? Color.secondary.opacity(0.12))
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
            } else {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
        } else if let iconText = button.iconText, !iconText.isEmpty {
            ZStack {
                (resolvedBackground ?? Color.secondary.opacity(0.12))
                Text(iconText)
                    .font(.system(size: 36))
                    .foregroundColor(resolvedForeground)
            }
        } else {
            ZStack {
                (resolvedBackground ?? Color.secondary.opacity(0.12))
                Image(systemName: "square.dashed")
                    .font(.system(size: 28))
                    .foregroundColor(.secondary)
            }
        }
    }

    /// The message part of the execution confirmation dialog. If confirmMessage is empty, it depends on the destructive nature.
    /// Display default text.
    @ViewBuilder
    private func executeConfirmMessageView() -> some View {
        let trimmed = button.confirmMessage?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            Text(trimmed)
        } else if button.confirmDestructive {
            Text(L("この操作は元に戻せません_3955a5"))
        } else {
            Text(L("この操作を実行します_26d7fa"))
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
    var onGroupCut: (() -> Void)? = nil
    var onGroupDuplicate: (() -> Void)? = nil
    var onGroupDelete: (() -> Void)? = nil
    var onPasteGroup: (() -> Void)? = nil
    var onButtonEdit: ((ButtonDefinition) -> Void)? = nil
    var onButtonCut: ((ButtonDefinition) -> Void)? = nil
    var onButtonDuplicate: ((ButtonDefinition) -> Void)? = nil
    var onButtonDelete: ((ButtonDefinition) -> Void)? = nil
    var onAddNewToThisGroup: (() -> Void)? = nil
    var onPasteButtonToGroup: ((String?) -> Void)? = nil

    @State private var collapsed: Bool
    @State private var confirmingGroupDelete = false

    init(group: ButtonGroup,
         onButtonTap: @escaping (ButtonDefinition) -> Void,
         onGroupEdit: (() -> Void)? = nil,
         onGroupCut: (() -> Void)? = nil,
         onGroupDuplicate: (() -> Void)? = nil,
         onGroupDelete: (() -> Void)? = nil,
         onPasteGroup: (() -> Void)? = nil,
         onButtonEdit: ((ButtonDefinition) -> Void)? = nil,
         onButtonCut: ((ButtonDefinition) -> Void)? = nil,
         onButtonDuplicate: ((ButtonDefinition) -> Void)? = nil,
         onButtonDelete: ((ButtonDefinition) -> Void)? = nil,
         onAddNewToThisGroup: (() -> Void)? = nil,
         onPasteButtonToGroup: ((String?) -> Void)? = nil) {
        self.group = group
        self.onButtonTap = onButtonTap
        self.onGroupEdit = onGroupEdit
        self.onGroupCut = onGroupCut
        self.onGroupDuplicate = onGroupDuplicate
        self.onGroupDelete = onGroupDelete
        self.onPasteGroup = onPasteGroup
        self.onButtonEdit = onButtonEdit
        self.onButtonCut = onButtonCut
        self.onButtonDuplicate = onButtonDuplicate
        self.onButtonDelete = onButtonDelete
        self.onAddNewToThisGroup = onAddNewToThisGroup
        self.onPasteButtonToGroup = onPasteButtonToGroup
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
                if let onGroupCut = onGroupCut {
                    Button {
                        onGroupCut()
                    } label: {
                        Label(L("切り取り_cut"), systemImage: "scissors")
                    }
                }
                Button {
                    PasteboardHelper.copyGroup(group)
                } label: {
                    Label(L("コピー_copy"), systemImage: "doc.on.doc")
                }
                if let onPasteGroup = onPasteGroup {
                    Button {
                        onPasteGroup()
                    } label: {
                        Label(L("貼り付け_paste"), systemImage: "doc.on.clipboard")
                    }
                    .disabled(!PasteboardHelper.hasGroup())
                }
                if let onGroupDuplicate = onGroupDuplicate {
                    Button {
                        onGroupDuplicate()
                    } label: {
                        Label(L("複製_duplicate"), systemImage: "plus.square.on.square")
                    }
                }
                Divider()
                if let onGroupEdit = onGroupEdit {
                    Button {
                        onGroupEdit()
                    } label: {
                        Label(L("編集_ac1264"), systemImage: "pencil")
                    }
                }
                if let onPasteButtonToGroup = onPasteButtonToGroup {
                    Button {
                        onPasteButtonToGroup(nil)
                    } label: {
                        Label(L("ボタンを貼り付け_1743f6"), systemImage: "doc.on.clipboard.fill")
                    }
                    .disabled(!PasteboardHelper.hasButton())
                }
                if onGroupDelete != nil {
                    Divider()
                    Button(role: .destructive) {
                        confirmingGroupDelete = true
                    } label: {
                        Label(L("削除_eec57b"), systemImage: "trash")
                    }
                }
            }
            .confirmationDialog(
                L("このグループを削除しますか_fd0e79"),
                isPresented: $confirmingGroupDelete,
                titleVisibility: .visible
            ) {
                Button(L_("delete_named_item", group.label), role: .destructive) {
                    onGroupDelete?()
                }
                Button(L("キャンセル_6ef349"), role: .cancel) {}
            } message: {
                Text(L_("delete_group_message_buttons", group.buttons.count))
            }

            if !collapsed {
                buttonsBody
            }
        }
    }

    /// Change the button layout based on the group's display type.
    /// icon: existing vertical layout
    /// wide: Full-width cell vertical layout (no left padding)
    /// card: 2-column LazyVGrid (Midjourney-style gallery)
    @ViewBuilder
    private var buttonsBody: some View {
        switch group.displayType {
        case .icon:
            VStack(alignment: .leading, spacing: 2) {
                ForEach(group.buttons, id: \.id) { btn in
                    macroButton(for: btn)
                }
            }
            .padding(.leading, 16)
        case .wide:
            VStack(alignment: .leading, spacing: 4) {
                ForEach(group.buttons, id: \.id) { btn in
                    macroButton(for: btn)
                }
            }
            .padding(.horizontal, 8)
        case .card:
            WaterfallGrid(group.buttons, id: \.id) { btn in
                macroButton(for: btn)
            }
            .gridStyle(columns: paolocolumns(default: 2), spacing: 8)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
        case .grid:
            WaterfallGrid(group.buttons, id: \.id) { btn in
                macroButton(for: btn)
            }
            .gridStyle(columns: paolocolumns(default: 4), spacing: 6)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
        }
    }

    /// Convert `group.columns` to a LazyVGrid columns definition.
    /// `.auto` is `adaptive(minimum:max:)`, `.fixed(n)` is `flexible()` with n pieces.
    private func gridColumns(minCellWidth: CGFloat,
                             maxCellWidth: CGFloat,
                             spacing: CGFloat) -> [GridItem] {
        switch group.columns {
        case .auto:
            return [GridItem(.adaptive(minimum: minCellWidth, maximum: maxCellWidth),
                             spacing: spacing)]
        case .fixed(let n):
            return Array(repeating: GridItem(.flexible(), spacing: spacing),
                         count: max(1, n))
        }
    }

    private func paolocolumns(default defaultCount: Int) -> Int {
        switch group.columns {
        case .auto: return defaultCount
        case .fixed(let count): return max(1, count)
        }
    }

    private func macroButton(for btn: ButtonDefinition) -> some View {
        MacroButtonView(
            button: btn,
            onTap: { onButtonTap(btn) },
            displayType: group.displayType,
            iconSize: group.iconSize,
            showLabel: group.showLabels,
            onEdit:       onButtonEdit.map      { cb in { cb(btn) } },
            onCut:        onButtonCut.map       { cb in { cb(btn) } },
            onDuplicate:  onButtonDuplicate.map { cb in { cb(btn) } },
            onDelete:     onButtonDelete.map    { cb in { cb(btn) } },
            onAddToGroup: onAddNewToThisGroup,
            onPasteButton: onPasteButtonToGroup.map { cb in { afterId in cb(afterId) } }
        )
    }
}

struct PresetView: View {
    let preset: Preset
    let onButtonTap: (ButtonDefinition) -> Void
    var onGroupEdit: ((ButtonGroup) -> Void)? = nil
    var onGroupCut: ((ButtonGroup) -> Void)? = nil
    var onGroupDuplicate: ((ButtonGroup) -> Void)? = nil
    var onGroupDelete: ((ButtonGroup) -> Void)? = nil
    var onPasteGroup: ((ButtonGroup) -> Void)? = nil
    var onButtonEdit: ((ButtonDefinition) -> Void)? = nil
    var onButtonCut: ((ButtonDefinition) -> Void)? = nil
    var onButtonDuplicate: ((ButtonDefinition) -> Void)? = nil
    var onButtonDelete: ((ButtonDefinition) -> Void)? = nil
    var onButtonAdd: ((ButtonGroup) -> Void)? = nil
    var onPasteButton: ((ButtonGroup, String?) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(preset.groups, id: \.id) { group in
                GroupView(
                    group: group,
                    onButtonTap: onButtonTap,
                    onGroupEdit: onGroupEdit.map { cb in { cb(group) } },
                    onGroupCut: onGroupCut.map { cb in { cb(group) } },
                    onGroupDuplicate: onGroupDuplicate.map { cb in { cb(group) } },
                    onGroupDelete: onGroupDelete.map { cb in { cb(group) } },
                    onPasteGroup: onPasteGroup.map { cb in { cb(group) } },
                    onButtonEdit: onButtonEdit,
                    onButtonCut: onButtonCut,
                    onButtonDuplicate: onButtonDuplicate,
                    onButtonDelete: onButtonDelete,
                    onAddNewToThisGroup: onButtonAdd.map { cb in { cb(group) } },
                    onPasteButtonToGroup: onPasteButton.map { cb in { afterId in cb(group, afterId) } }
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

