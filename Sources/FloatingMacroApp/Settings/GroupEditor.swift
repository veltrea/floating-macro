import SwiftUI
import AppKit
import FloatingMacroCore

// MARK: - GroupEditor

struct GroupEditor: View {
    let group: ButtonGroup
    @ObservedObject var presetManager: PresetManager
    var onDelete: (() -> Void)? = nil

    @State private var label: String = ""
    @State private var iconText: String = ""
    @State private var iconPath: String = ""
    @State private var backgroundColor: Color = .clear
    @State private var backgroundHex: String = ""
    @State private var useBackgroundColor: Bool = false
    @State private var textColor: Color = .white
    @State private var textHex: String = ""
    @State private var useTextColor: Bool = false
    @State private var tooltip: String = ""
    @State private var displayType: GroupDisplayType = .icon
    @State private var columns: GroupColumns = .auto
    @State private var iconSize: IconSize = .medium
    @State private var showLabels: Bool = true
    @State private var showingSFSymbolPicker: Bool = false
    @State private var showingAppIconPicker: Bool = false
    @State private var confirmingDelete: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text(L_("group_id_label", group.id)).font(.caption).foregroundColor(.secondary)
                        Spacer()
                    }

                    // Group header editor preview
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("プレビュー_21b7d4")).font(.caption).foregroundColor(.secondary)
                        HStack {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(previewTextColor)
                                    .frame(width: 12)
                                if !iconText.isEmpty {
                                    Text(iconText).font(.system(size: 12))
                                }
                                Text(label.isEmpty ? group.label : label)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(previewTextColor)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                previewBackground.map { color in
                                    RoundedRectangle(cornerRadius: 4).fill(color)
                                }
                            )
                            Spacer()
                        }
                        .padding(8)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                    }

                    Group {
                        labeled(L("グループ名_0a11c7")) {
                            TextField(L("グループの見出し_f24511"), text: $label)
                                .textFieldStyle(.roundedBorder)
                        }

                        labeled(L("アイコンテキスト_絵文字など_c666a5")) {
                            TextField(L("や_など_49750c"), text: $iconText)
                                .textFieldStyle(.roundedBorder)
                        }

                        labeled(L("アイコン_d160a5")) {
                            HStack(alignment: .top, spacing: 12) {
                                IconDropZoneView(
                                    iconRef: iconPath,
                                    iconText: iconText,
                                    onDropImageURL: { url in importIconFile(from: url) },
                                    onClickFallback: { pickIconFile() }
                                )
                                VStack(alignment: .leading, spacing: 6) {
                                    Button("SF Symbol...") { showingSFSymbolPicker = true }
                                        .help(L("SF_Symbol_を一覧から選ぶ_ab178d"))
                                    Button(L("アプリから_29035e")) { showingAppIconPicker = true }
                                        .help(L("インストール済みアプリのアイコンから選ぶ_8d8c57"))
                                    Button(L("クリア_deba64")) { iconPath = "" }
                                        .disabled(iconPath.isEmpty)
                                    Text(L("画像をドロップするか枠をクリックすると_preset_配下にコピーして登録します_e6c5e7"))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                    }

                    Group {
                        labeled(L("背景色_2f97db")) {
                            HStack {
                                Toggle(L("有効_ce1518"), isOn: $useBackgroundColor)
                                if useBackgroundColor {
                                    ContinuousColorPicker(color: $backgroundColor)
                                        .frame(width: 44, height: 24)
                                        .onChange(of: backgroundColor) { newValue in
                                            backgroundHex = Self.hexFromColor(newValue)
                                        }
                                    TextField("#RRGGBB", text: $backgroundHex)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 110)
                                }
                            }
                        }

                        labeled(L("文字色_94e49c")) {
                            HStack {
                                Toggle(L("有効_ce1518"), isOn: $useTextColor)
                                if useTextColor {
                                    ContinuousColorPicker(color: $textColor)
                                        .frame(width: 44, height: 24)
                                        .onChange(of: textColor) { newValue in
                                            textHex = Self.hexFromColor(newValue)
                                        }
                                    TextField("#RRGGBB", text: $textHex)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 110)
                                } else {
                                    Text(L("自動_背景色があれば白_なければシステム既定_22d22a"))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }

                    Divider()

                    displayTypeSection

                    labeled(L("ツールチップ_ホバー時に表示_e40d98")) {
                        TextField(L("グループの用途を説明_5a4540"), text: $tooltip)
                            .textFieldStyle(.roundedBorder)
                    }

                    Text(L_("button_count_label", group.buttons.count))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()
            HStack {
                Spacer()
                if onDelete != nil {
                    Button(role: .destructive) {
                        confirmingDelete = true
                    } label: {
                        Label(L("削除_c6577c"), systemImage: "trash")
                    }
                }
                Button(action: commit) {
                    Label(L("保存_be5fbb"), systemImage: "checkmark.circle.fill")
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .onAppear { loadFromGroup() }
        .onChange(of: presetManager.appIconPickerRequestNonce) { _ in
            showingAppIconPicker = true
        }
        .onChange(of: presetManager.dismissPickerNonce) { _ in
            showingSFSymbolPicker = false
            showingAppIconPicker = false
        }
        .onChange(of: presetManager.externalBackgroundColorRequest) { req in
            guard let req else { return }
            if let hex = req.hex, let color = Color(hex: hex) {
                useBackgroundColor = true
                backgroundColor = color
                backgroundHex = hex
            } else {
                useBackgroundColor = false
                backgroundHex = ""
            }
            presetManager.externalBackgroundColorRequest = nil
        }
        .onChange(of: presetManager.externalTextColorRequest) { req in
            guard let req else { return }
            if let hex = req.hex, let color = Color(hex: hex) {
                useTextColor = true
                textColor = color
                textHex = hex
            } else {
                useTextColor = false
                textHex = ""
            }
            presetManager.externalTextColorRequest = nil
        }
        .onChange(of: presetManager.commitNonce) { _ in
            commit()
        }
        .sheet(isPresented: $showingSFSymbolPicker) {
            SFSymbolPicker(
                selection: $iconPath,
                onClose: { showingSFSymbolPicker = false }
            )
        }
        .sheet(isPresented: $showingAppIconPicker) {
            AppIconPicker(
                selection: $iconPath,
                onClose: { showingAppIconPicker = false }
            )
        }
        .confirmationDialog(
            L("このグループを削除しますか_fd0e79"),
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button(L_("delete_named_item", group.label), role: .destructive) { onDelete?() }
            Button(L("キャンセル_6ef349"), role: .cancel) {}
        } message: {
            Text(L("グループ内のボタンもすべて削除されます_この操作は元に戻せません_4da004"))
        }
    }

    // MARK: - Mapping between state and model

    private func loadFromGroup() {
        label = group.label
        iconText = group.iconText ?? ""
        iconPath = group.icon ?? ""
        tooltip = group.tooltip ?? ""
        displayType = group.displayType
        columns = group.columns
        iconSize = group.iconSize
        showLabels = group.showLabels
        if let hex = group.backgroundColor, let color = Color(hex: hex) {
            backgroundColor = color
            backgroundHex = hex
            useBackgroundColor = true
        } else {
            useBackgroundColor = false
            backgroundHex = ""
        }
        if let hex = group.textColor, let color = Color(hex: hex) {
            textColor = color
            textHex = hex
            useTextColor = true
        } else {
            useTextColor = false
            textHex = ""
        }
    }

    private func commit() {
        // Same automatic migration as ButtonEditor: Copy external absolute path to preset under.
        let migratedIcon = ButtonEditor.migrateIfNeeded(
            path: iconPath.isEmpty ? nil : iconPath,
            into: .icons,
            assetId: group.id,
            presetManager: presetManager
        )
        if let m = migratedIcon, m != iconPath { iconPath = m }

        _ = presetManager.updateGroup(
            id: group.id,
            label: label.isEmpty ? nil : label,
            icon: migratedIcon == nil ? .some(nil) : .some(migratedIcon),
            iconText: iconText.isEmpty ? .some(nil) : .some(iconText),
            backgroundColor: useBackgroundColor
                ? .some(backgroundHex.isEmpty ? Self.hexFromColor(backgroundColor) : backgroundHex)
                : .some(nil),
            textColor: useTextColor
                ? .some(textHex.isEmpty ? Self.hexFromColor(textColor) : textHex)
                : .some(nil),
            tooltip: tooltip.isEmpty ? .some(nil) : .some(tooltip),
            displayType: displayType,
            columns: (displayType == .card || displayType == .grid) ? columns : nil,
            iconSize: iconSize,
            showLabels: displayType == .grid ? showLabels : nil
        )
    }

    @ViewBuilder
    private var displayTypeSection: some View {
        labeled(L("ボタンの表示タイプ_4d03fd")) {
            VStack(alignment: .leading, spacing: 4) {
                Picker("", selection: $displayType) {
                    Text(L("icon_小さなアイコン_9d9c3e")).tag(GroupDisplayType.icon)
                    Text(L("wide_横長セル_9e31df")).tag(GroupDisplayType.wide)
                    Text(L("card_大きなサムネイル_ed0037")).tag(GroupDisplayType.card)
                    Text(L("grid_アイコングリッド_d4e92a")).tag(GroupDisplayType.grid)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                Text(displayTypeHint(displayType))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        if displayType == .card || displayType == .grid {
            labeled(L("列数_b2c7f3")) {
                columnsPickerContent
            }
        }
        labeled(L("アイコンサイズ_f7a3c2")) {
            VStack(alignment: .leading, spacing: 4) {
                Picker("", selection: $iconSize) {
                    Text("S (16pt)").tag(IconSize.small)
                    Text("M (32pt)").tag(IconSize.medium)
                    Text("L (48pt)").tag(IconSize.large)
                    Text("XL (64pt)").tag(IconSize.xlarge)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                Text(L("アプリアイコンや絵文字の表示サイズを変更します_b8e1d4"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        if displayType == .grid {
            labeled(L("ラベル表示_a1d5f8")) {
                Toggle(L("アイコンの下に名前を表示_c3b7e2"), isOn: $showLabels)
            }
        }
    }

    @ViewBuilder
    private var columnsPickerContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            let maxColumns = displayType == .grid ? 12 : 3
            Picker("", selection: $columns) {
                Text(L("自動_5c8b29")).tag(GroupColumns.auto)
                ForEach(1...maxColumns, id: \.self) { n in
                    Text("\(n)").tag(GroupColumns.fixed(n))
                }
            }
            .labelsHidden()
            .fixedSize()
            Text(columnsHint(columns))
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Explanation of the differences in display types in one line.
    private func displayTypeHint(_ type: GroupDisplayType) -> String {
        switch type {
        case .icon: return L("既存の小さなアイコン_ラベルを縦に並べる_コンパクトな表示_08324c")
        case .wide: return L("全幅の横長セル_長いラベルや_視認性を優先したいボタンに_70ed46")
        case .card: return L("サムネイル画像_タイトルを_2_列のグリッドに配置_プロンプトギャラリー向け_3fed87")
        case .grid: return L("アイコンをグリッド状に並べる_ランチャー風_列数を自由に設定可_7f1e3b")
        }
    }

    private func columnsHint(_ cols: GroupColumns) -> String {
        switch cols {
        case .auto: return L("ウィンドウ幅に応じて列数が自動で変わります_最小セル幅_120pt_a3f8b1")
        case .fixed(let n): return L_("fixed_columns_hint", n)
        }
    }

    private func pickIconFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .png, .jpeg]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = L("選択_8ba15a")
        if panel.runModal() == .OK, let url = panel.url {
            importIconFile(from: url)
        }
    }

    /// Copy the received image as a preset group icon under preset/.
    fileprivate func importIconFile(from url: URL) {
        guard let newPath = ButtonEditor.importImage(
            from: url, into: .icons,
            assetId: group.id, presetManager: presetManager
        ) else { return }
        iconPath = newPath
    }

    private func labeled<V: View>(_ title: String, @ViewBuilder _ content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundColor(.secondary)
            content()
        }
    }

    private static func hexFromColor(_ color: Color) -> String {
        let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? .black
        let r = Int((nsColor.redComponent   * 255).rounded())
        let g = Int((nsColor.greenComponent * 255).rounded())
        let b = Int((nsColor.blueComponent  * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    private var previewBackground: Color? {
        guard useBackgroundColor else { return nil }
        let hex = backgroundHex.isEmpty ? Self.hexFromColor(backgroundColor) : backgroundHex
        return Color(hex: hex)
    }

    private var previewTextColor: Color {
        if useTextColor {
            let hex = textHex.isEmpty ? Self.hexFromColor(textColor) : textHex
            return Color(hex: hex) ?? .secondary
        }
        return .secondary
    }
}

