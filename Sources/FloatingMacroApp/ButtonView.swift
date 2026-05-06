import SwiftUI
import AppKit
import FloatingMacroCore

/// 押下フィードバックの内部ステートマシン。`MacroButtonView` が実行直後に
/// `.running` → `.success` (1 秒) → `.idle` と自前のタイマーで遷移する。
/// アクションは現状 fire-and-forget なので「実行完了 = 成功扱い」(P2-10)。
/// 失敗時の赤フィードバックは将来 `executeButton` が結果を返すように
/// なってから配線する。
private enum ExecutionFeedback {
    case idle
    case running
    case success
    case failure
}

struct MacroButtonView: View {
    let button: ButtonDefinition
    let onTap: () -> Void
    /// 親グループの表示タイプ。`.icon` (既定) / `.wide` / `.card` で
    /// それぞれ別レイアウトに分岐する。エディター内プレビュー等、
    /// グループ文脈の無い呼び出し元は省略すれば既存挙動。
    var displayType: GroupDisplayType = .icon
    /// Optional: "Edit…" — opens Settings window focused on this button.
    var onEdit: (() -> Void)? = nil
    /// Optional: "Duplicate" — clone into the same group.
    var onDuplicate: (() -> Void)? = nil
    /// Optional: "Delete" — caller should confirm before actually deleting.
    var onDelete: (() -> Void)? = nil
    /// Optional: "Add new button" — add a new button to the same group.
    var onAddToGroup: (() -> Void)? = nil
    /// Optional: "Paste button" — paste after this button. Receives afterButtonId.
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

    /// Card タイプのときに使う大判画像。`thumbnail` 優先で、無ければ通常アイコンを再利用。
    private var thumbnailImage: NSImage? {
        if let img = IconLoader.image(for: button.thumbnail) {
            return img
        }
        return inferredImage
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

    /// 状態フィードバック用の枠線色。idle のときは `.clear` で枠線を出さない。
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
            Button {
                PasteboardHelper.copyButton(button)
            } label: {
                Label("コピー", systemImage: "doc.on.doc")
            }
            if let onPasteButton = onPasteButton {
                Button {
                    onPasteButton(button.id)
                } label: {
                    Label("ボタンを貼り付け", systemImage: "doc.on.clipboard")
                }
                .disabled(!PasteboardHelper.hasButton())
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
        // 実行前の確認ダイアログ。button.confirm == true のときのみ表示。
        // destructive 指定で「実行」ボタンを赤い破壊スタイルにして、
        // 再起動・シャットダウンのような取り返しのつかない操作を視覚的に
        // 区別する。視線入力ユーザーがデフォルトボタン (Return) で誤発火
        // しないよう、デフォルトはキャンセル側に置いている。
        .confirmationDialog(
            "「\(button.label)」を実行しますか?",
            isPresented: $confirmingExecute,
            titleVisibility: .visible
        ) {
            Button(
                button.confirmDestructive ? "実行する (取り消し不可)" : "実行する",
                role: button.confirmDestructive ? .destructive : nil
            ) {
                handleConfirmedTap()
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            executeConfirmMessageView()
        }
    }

    /// onTap を直接呼ぶ前に、ButtonDefinition.confirm が true なら確認ダイアログを介在させる。
    private func handleTap() {
        if button.confirm {
            confirmingExecute = true
        } else {
            triggerFeedback()
            onTap()
        }
    }

    /// 確認ダイアログ経由で実行するときも feedback を出す。
    private func handleConfirmedTap() {
        triggerFeedback()
        onTap()
    }

    /// 実行中 → 成功の枠線アニメーションを開始する。
    /// アクション側に成功/失敗の戻り値が無いので、現状は「押された＝成功扱い」。
    /// 連打されたら最新の押下を優先するため既存タスクをキャンセルする。
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

    /// displayType によって描画するレイアウトを切り替える。`.icon` は既存挙動。
    @ViewBuilder
    private var buttonContent: some View {
        switch displayType {
        case .icon: iconLayout
        case .wide: wideLayout
        case .card: cardLayout
        }
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

    /// Wide: 全幅・大きめのアイコン + 中央寄せラベル。長いタイトルを 2 行まで許容する。
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
                // 不在のときも左マージンを保つ。
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

    /// Card: サムネイルを上、タイトルを下に出すギャラリー風レイアウト。
    /// 親 GroupView 側の `LazyVGrid` の中で使う前提。
    ///
    /// レイアウト戦略:
    ///   1. `Color.clear.aspectRatio(1, .fit)` でセルの幅から正方形ボックスを取る
    ///   2. その上に overlay + clipShape で画像/絵文字/プレースホルダを乗せる
    ///   3. `.aspectRatio(.fill)` した画像は clipShape で正方形に切り抜かれる
    /// この構成だと Image の intrinsic size が ZStack を引き伸ばす問題を踏まない。
    ///
    /// 縦方向アラインメント: LazyVGrid は同じ行内の cell 高さを揃えるが、ラベルが
    /// 1 行の cell と 2 行の cell では VStack 全体の高さが違う。デフォルトでは
    /// 行の cell が center 揃えになり「短いラベルの cell だけサムネイルが下に
    /// ずれる」ため、`.frame(maxHeight: .infinity, alignment: .top)` で **基準点を
    /// 上端に固定** する。サムネイルとラベルの位置はラベル行数によらず常に同じ。
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
                .frame(maxWidth: .infinity, alignment: .center)
            // 行内で他の cell が背の高いラベル (2 行) を持っているとき、こちらの
            // cell が center 揃えで sub-pixel 単位下にずれるのを防ぐ。Spacer
            // が下方向の空きを吸収して、サムネイルとラベルは常に上端寄せ。
            Spacer(minLength: 0)
        }
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isHovering ? Color.accentColor.opacity(0.10) : Color.clear)
        )
    }

    /// Card レイアウトの正方形ボックスに乗せるサムネイル中身。
    /// `button.cardThumbnailMode == .fill` なら外接クロップ、`.fit` なら内接余白。
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

    /// 実行確認ダイアログのメッセージ部。confirmMessage が空なら破壊性に応じて
    /// デフォルト文言を出す。
    @ViewBuilder
    private func executeConfirmMessageView() -> some View {
        let trimmed = button.confirmMessage?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            Text(trimmed)
        } else if button.confirmDestructive {
            Text("この操作は元に戻せません。")
        } else {
            Text("この操作を実行します。")
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
    var onGroupDelete: (() -> Void)? = nil
    var onButtonEdit: ((ButtonDefinition) -> Void)? = nil
    var onButtonDuplicate: ((ButtonDefinition) -> Void)? = nil
    var onButtonDelete: ((ButtonDefinition) -> Void)? = nil
    var onAddNewToThisGroup: (() -> Void)? = nil
    var onPasteButtonToGroup: ((String?) -> Void)? = nil

    @State private var collapsed: Bool
    @State private var confirmingGroupDelete = false

    init(group: ButtonGroup,
         onButtonTap: @escaping (ButtonDefinition) -> Void,
         onGroupEdit: (() -> Void)? = nil,
         onGroupDelete: (() -> Void)? = nil,
         onButtonEdit: ((ButtonDefinition) -> Void)? = nil,
         onButtonDuplicate: ((ButtonDefinition) -> Void)? = nil,
         onButtonDelete: ((ButtonDefinition) -> Void)? = nil,
         onAddNewToThisGroup: (() -> Void)? = nil,
         onPasteButtonToGroup: ((String?) -> Void)? = nil) {
        self.group = group
        self.onButtonTap = onButtonTap
        self.onGroupEdit = onGroupEdit
        self.onGroupDelete = onGroupDelete
        self.onButtonEdit = onButtonEdit
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
                if let onGroupEdit = onGroupEdit {
                    Button {
                        onGroupEdit()
                    } label: {
                        Label("編集...", systemImage: "pencil")
                    }
                }
                Button {
                    PasteboardHelper.copyGroup(group)
                } label: {
                    Label("コピー", systemImage: "doc.on.doc")
                }
                if let onPasteButtonToGroup = onPasteButtonToGroup {
                    Button {
                        onPasteButtonToGroup(nil)
                    } label: {
                        Label("ボタンを貼り付け", systemImage: "doc.on.clipboard")
                    }
                    .disabled(!PasteboardHelper.hasButton())
                }
                if onGroupDelete != nil {
                    Divider()
                    Button(role: .destructive) {
                        confirmingGroupDelete = true
                    } label: {
                        Label("削除...", systemImage: "trash")
                    }
                }
            }
            .confirmationDialog(
                "このグループを削除しますか?",
                isPresented: $confirmingGroupDelete,
                titleVisibility: .visible
            ) {
                Button("「\(group.label)」を削除", role: .destructive) {
                    onGroupDelete?()
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("グループ内のボタン \(group.buttons.count) 個もすべて削除されます。この操作は元に戻せません。")
            }

            if !collapsed {
                buttonsBody
            }
        }
    }

    /// グループの displayType に応じてボタン群のレイアウトを変える。
    /// - icon : 既存の縦並び
    /// - wide : 全幅セルの縦並び (left padding なし)
    /// - card : 2 列の LazyVGrid (Midjourney 風ギャラリー)
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
            // adaptive に minimum/maximum 両方を指定しないと、ボタン数が少ない
            // (1〜2 個) ときに 1 セルが行いっぱいに伸び、結果として中身が左寄せに
            // 見える。maximum を 140 で締めてセル幅を 96〜140pt に収める。
            // alignment: .center で行内の余りスペースをセル両側に均等に分配。
            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 96, maximum: 140), spacing: 8)
                ],
                alignment: .center,
                spacing: 8
            ) {
                ForEach(group.buttons, id: \.id) { btn in
                    macroButton(for: btn)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
        }
    }

    private func macroButton(for btn: ButtonDefinition) -> some View {
        MacroButtonView(
            button: btn,
            onTap: { onButtonTap(btn) },
            displayType: group.displayType,
            onEdit:       onButtonEdit.map      { cb in { cb(btn) } },
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
    var onGroupDelete: ((ButtonGroup) -> Void)? = nil
    var onButtonEdit: ((ButtonDefinition) -> Void)? = nil
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
                    onGroupDelete: onGroupDelete.map { cb in { cb(group) } },
                    onButtonEdit: onButtonEdit,
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

