import SwiftUI
import AppKit
import UniformTypeIdentifiers
import FloatingMacroCore

struct ContentHostView: View {
    @ObservedObject var presetManager: PresetManager
    /// このパネルの永続 id (`PanelConfig.id`)。Phase 3 で導入。
    /// プリセットの参照・編集ターゲットの切替・各種 UI ルックアップに使う。
    let panelID: String
    /// Phase 5: パネル右上の QR アイコンが押されたとき、AppDelegate 側の
    /// `openDeviceSend(panelID:)` を呼び出してもらうコールバック。
    /// SwiftUI 内から直接 AppDelegate を参照しないことで Preview の壊れにくさを保つ。
    /// 引数の panelID で、QR にどのパネル / プリセットを埋め込むかを指示する。
    var onDeviceSendRequested: (String) -> Void = { _ in }
    @State private var confirmingPresetDelete = false
    @State private var showingPresetReorderSheet = false
    /// プリセットメモの折りたたみ展開状態。プリセット切替時はリセット
    /// （新しいプリセットのメモは「畳まれた状態で気付ける」のが望ましい）。
    @State private var memoExpanded: Bool = false
    /// アプリ/ファイルがパネル上にドラッグされている間 true。
    /// 視覚フィードバック（青枠ハイライト）の駆動に使う。
    @State private var isDropTargeted: Bool = false

    /// このパネルが現在表示しているプリセット。Phase 3 では panelID に紐づく
    /// `PanelConfig.presetName` を経由してキャッシュ (`PresetManager.loadedPresets`)
    /// から取得する。`@ObservedObject` 経由で `presetManager.appConfig` /
    /// `loadedPresets` の変化を観測しているので preset 切替 / 編集が即座に反映される。
    private var panelPreset: Preset? {
        presetManager.panelPreset(forPanelID: panelID)
    }

    /// このパネルが指している preset 名。`appConfig.panels` から逆引き。
    private var panelPresetName: String? {
        presetManager.appConfig?.panels.first(where: { $0.id == panelID })?.presetName
    }

    /// このパネルの保存済みスクロール位置 (アプリ再起動時の復元用)。
    /// `PanelScrollView.initialY` の供給源。`appConfig` が変わっても view が
    /// 再生成されないように `let initialY` でキャプチャしてから使う想定。
    private var panelScrollY: Double {
        presetManager.appConfig?.panels.first(where: { $0.id == panelID })?.scrollY ?? 0
    }

    /// SettingsWindowController を開く前に編集ターゲット (`currentPreset`) を
    /// このパネルのプリセットに切り替えるショートカット。複数パネルが別々の
    /// プリセットを表示しているとき、編集アクションが「このパネルのプリセット」
    /// に対して行われるようにする。
    private func openSettings(selectButtonId: String? = nil,
                              selectGroupId: String? = nil) {
        presetManager.setEditTarget(panelID: panelID)
        SettingsWindowController.shared.show(
            presetManager: presetManager,
            selectButtonId: selectButtonId,
            selectGroupId: selectGroupId
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // 上端ヘッダー: 左にプリセット切替、右に AI 連携ウィンドウへの導線。
            // プリセット picker をここに常時出すことで、複数プリセットの
            // 切替を発見しやすくする (設定画面の picker と同期)。
            HStack(spacing: 4) {
                Menu {
                    ForEach(presetManager.presetEntries) { entry in
                        Button(action: {
                            presetManager.switchPanelPreset(panelID: panelID, to: entry.name)
                        }) {
                            if entry.name == panelPresetName {
                                Label(entry.displayName, systemImage: "checkmark")
                            } else {
                                Text(entry.displayName)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 2) {
                        Text(panelPreset?.displayName ?? "—")
                            .font(.system(size: 11))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                // 縦は固定 (高さがゼロにならないように)、横は柔軟にして
                // 長いプリセット名のときに右側のアイコン群を押し出さない。
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(0)
                .help(L("プリセットを切り替え_右クリックで編集_並べ替え_削除_2a0d21"))
                .contextMenu {
                    Button {
                        openSettings()
                    } label: {
                        Label(L("編集_ac1264"), systemImage: "pencil")
                    }
                    .disabled(panelPreset == nil)

                    Button {
                        showingPresetReorderSheet = true
                    } label: {
                        Label(L("並べ替え_3341c5"), systemImage: "arrow.up.arrow.down")
                    }
                    .disabled(presetManager.presetEntries.count < 2)

                    Divider()

                    Button(role: .destructive) {
                        confirmingPresetDelete = true
                    } label: {
                        Label(L("削除_eec57b"), systemImage: "trash")
                    }
                    .disabled(
                        panelPreset == nil
                        || panelPreset?.name == "default"
                    )
                }
                .confirmationDialog(
                    L("このプリセットを削除しますか_e3f19c"),
                    isPresented: $confirmingPresetDelete,
                    titleVisibility: .visible
                ) {
                    if let preset = panelPreset {
                        Button(L_("delete_named_item", preset.displayName), role: .destructive) {
                            _ = presetManager.deletePreset(name: preset.name)
                        }
                    }
                    Button(L("キャンセル_6ef349"), role: .cancel) {}
                } message: {
                    if let preset = panelPreset {
                        let buttonCount = preset.groups.reduce(0) { $0 + $1.buttons.count }
                        Text(L_("delete_preset_message_groups_buttons", preset.groups.count, buttonCount))
                    }
                }
                .sheet(isPresented: $showingPresetReorderSheet) {
                    PresetReorderSheet(
                        presetManager: presetManager,
                        isPresented: $showingPresetReorderSheet
                    )
                }

                Spacer(minLength: 4)

                Button {
                    openSettings()
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L("編集ウィンドウを開く_99e3e1"))

                // Phase 5: QR / デバイスに送信。このパネル単独の QR を出す。
                Button {
                    onDeviceSendRequested(panelID)
                } label: {
                    Image(systemName: "qrcode")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L("デバイスに送信_54b8f3"))

                Button {
                    AIIntegrationWindowController.shared.show(
                        presetManager: presetManager
                    )
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L("AI_に接続を設定_6c80c4"))
            }
            .padding(.horizontal, 4)
            .padding(.top, 2)

            // プリセットメモ（折りたたみ）。memo が空のプリセットでは描画しない。
            if let memo = panelPreset?.memo,
               !memo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                presetMemoBlock(memo)
            }

            // ボタン一覧
            if let preset = panelPreset {
                // PanelScrollView (NSScrollView ラッパー) を使うことで
                // アプリ再起動後にスクロール位置を復元できる。
                // 復元値はこのパネルの `PanelConfig.scrollY`。スクロール変化は
                // PresetManager が debounce 付きで永続化する。
                let initialY = CGFloat(panelScrollY)
                PanelScrollView(
                    initialY: initialY,
                    onScrollChange: { y in
                        presetManager.updatePanelScrollY(id: panelID, y: Double(y))
                    }
                ) {
                    VStack(spacing: 0) {
                        PresetView(
                            preset: preset,
                            onButtonTap: { button in
                                presetManager.executeButton(button)
                            },
                            onGroupEdit: { group in
                                openSettings(selectGroupId: group.id)
                            },
                            onGroupCut: { group in
                                PasteboardHelper.copyGroup(group)
                                presetManager.setEditTarget(panelID: panelID)
                                _ = presetManager.deleteGroup(id: group.id)
                            },
                            onGroupDuplicate: { group in
                                presetManager.setEditTarget(panelID: panelID)
                                _ = presetManager.duplicateGroup(id: group.id)
                            },
                            onGroupDelete: { group in
                                presetManager.setEditTarget(panelID: panelID)
                                _ = presetManager.deleteGroup(id: group.id)
                            },
                            onPasteGroup: { _ in
                                pasteGroup()
                            },
                            onButtonEdit: { button in
                                openSettings(selectButtonId: button.id)
                            },
                            onButtonCut: { button in
                                PasteboardHelper.copyButton(button)
                                presetManager.setEditTarget(panelID: panelID)
                                _ = presetManager.deleteButton(id: button.id)
                            },
                            onButtonDuplicate: { button in
                                presetManager.setEditTarget(panelID: panelID)
                                _ = presetManager.duplicateButton(id: button.id)
                            },
                            onButtonDelete: { button in
                                presetManager.setEditTarget(panelID: panelID)
                                _ = presetManager.deleteButton(id: button.id)
                            },
                            onButtonAdd: { group in
                                addNewButton(toGroupId: group.id)
                            },
                            onPasteButton: { group, afterButtonId in
                                pasteButtonToGroup(group.id, afterButtonId: afterButtonId)
                            }
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .contentShape(Rectangle())
                    .contextMenu {
                        panelContextMenu(preset: preset)
                    }
                }
                .frame(maxHeight: .infinity)
                .layoutPriority(1)
            } else {
                VStack {
                    Spacer()
                    Text(L("プリセットが読み込めません_4f5aeb"))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }

            // エラーバナー
            if let error = presetManager.errorMessage {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundColor(.white)
                    .padding(6)
                    .frame(maxWidth: .infinity)
                    .background(Color.red.opacity(0.85))
                    .cornerRadius(4)
                    .padding(4)
            }

            // Accessibility 権限喪失バッジ。CGEvent.post は権限がなくても
            // void で成功扱いを返してしまうため、ログだけ見ても気づけない
            // (= ユーザーが「テキストボタンが効かない」と感じる主因)。
            // ここに常時バッジを出すことで、リビルド後に権限が剥がれた
            // 状態を視覚的に必ず気づけるようにする。
            if !presetManager.accessibilityTrusted {
                // Self-restart recovery flow:
                //   1. tccutil reset → drop the (possibly stale) TCC entry
                //   2. Re-launch ourselves with --prompt-accessibility
                //   3. terminate the current process
                //   4. The new process, on startup, calls
                //      AXIsProcessTrustedWithOptions(prompt: true) → the OS
                //      shows its system "Allow FloatingMacro?" dialog and
                //      adds a fresh entry to the Accessibility list. The
                //      user just flips the switch.
                //
                // Same-process prompt: true は AXIsProcessTrusted() が stale
                // TRUE を返してバナーが誤って消える問題があるため、self-restart
                // でクリーン状態にしてから prompt: true を呼ぶ。
                let recover: () -> Void = {
                    // Self-restart recovery:
                    //   1. tccutil reset で stale TCC エントリを削除
                    //   2. NSWorkspace.openApplication で自身を
                    //      --prompt-accessibility 引数付きで再起動
                    //   3. completion ハンドラで現プロセスを terminate
                    //
                    // 同プロセスで prompt: true を呼ぶ「シンプル版」と違い、
                    // 新プロセスで AX キャッシュがクリーンな状態から
                    // prompt: true を呼ぶので、古いエントリ + stale TRUE
                    // で一覧追加が阻害される状況を回避できる。
                    //
                    // OpenConfiguration.arguments で argv に確実に
                    // --prompt-accessibility を渡す (Process + open --args
                    // 経由だと Launch Services が argv を落とすケースが
                    // あるため、現代的な API を使う)。
                    let logger = LoggerContext.shared
                    let bundleId = Bundle.main.bundleIdentifier ?? "com.veltrea.FloatingMacro"
                    logger.info("Accessibility", "recover requested", ["bundleId": bundleId])
                    TCCResetter.resetAccessibility(bundleId: bundleId)
                    let appURL = Bundle.main.bundleURL
                    let config = NSWorkspace.OpenConfiguration()
                    // Forward Apple's localization arguments so the relaunched
                    // process keeps the same display language.
                    var relaunchArgs: [String] = ["--prompt-accessibility"]
                    let argv = CommandLine.arguments
                    var idx = 1
                    while idx < argv.count {
                        let a = argv[idx]
                        if a == "-AppleLanguages" || a == "-AppleLocale" || a == "-AppleTextDirection" {
                            relaunchArgs.append(a)
                            if idx + 1 < argv.count {
                                relaunchArgs.append(argv[idx + 1])
                                idx += 1
                            }
                        }
                        idx += 1
                    }
                    config.arguments = relaunchArgs
                    config.createsNewApplicationInstance = true
                    logger.info("Accessibility", "relaunching", ["appURL": appURL.path])
                    NSWorkspace.shared.openApplication(at: appURL, configuration: config) { runningApp, error in
                        if let error = error {
                            logger.error("Accessibility", "relaunch failed", [
                                "error": String(describing: error),
                            ])
                            // フォールバック: 設定画面だけでも開く
                            DispatchQueue.main.async {
                                AccessibilityChecker.openSystemPreferences()
                            }
                            return
                        }
                        let pidStr = runningApp.map { String($0.processIdentifier) } ?? "nil"
                        logger.info("Accessibility", "relaunch succeeded", ["newPid": pidStr])
                        DispatchQueue.main.async {
                            NSApp.terminate(nil)
                        }
                    }
                }
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                    Text(L("アクセシビリティ権限が無効_8d74e5"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer(minLength: 4)
                    Button(action: recover) {
                        Text(L("修復_87dfef"))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.white)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.white, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .help(L("tccutil_で_TCC_エントリをリセットし_prompt_accessibility_付きで自_490e1b"))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.95))
                .cornerRadius(4)
                .padding(4)
            }
        }
        // 最大サイズに上限を設けない。これまで maxWidth: 300, maxHeight: 600
        // でハードキャップしていたため、ユーザーが NSPanel をドラッグして
        // 広げてもコンテントが追従せず「縮小はできるが拡大できない」現象が
        // 起きていた。SwiftUI 側を .infinity にして NSPanel のリサイズに
        // フルで追従するようにする。
        .frame(minWidth: 180, maxWidth: .infinity,
               minHeight: 100, maxHeight: .infinity)
        // パネル全面でファイル/アプリのドロップを受け付け、ボタン化する。
        // .app は bundle id ベースの launch action、その他のファイルは
        // 絶対パスの launch action として登録される。
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDroppedProviders(providers)
            return true
        }
        .overlay(
            // ドラッグ中の視覚フィードバック。Stream Deck と同じく「ここに
            // 落とせる」のが分かるようにアクセントカラーで縁を強調する。
            RoundedRectangle(cornerRadius: 6)
                .stroke(isDropTargeted ? Color.accentColor : Color.clear,
                        lineWidth: 3)
                .allowsHitTesting(false)
        )
    }

    /// `.onDrop` のプロバイダから fileURL を取り出し、PanelDropHandler に渡す。
    /// NSItemProvider の loadItem はコールバックベースなので非同期で集めて
    /// 全件揃ったタイミングでメインスレッドからハンドラを呼ぶ。
    private func handleDroppedProviders(_ providers: [NSItemProvider]) {
        let group = DispatchGroup()
        var collected: [URL] = []
        let lock = NSLock()

        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier,
                              options: nil) { item, _ in
                defer { group.leave() }
                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let direct = item as? URL {
                    url = direct
                } else {
                    url = nil
                }
                if let u = url {
                    lock.lock()
                    collected.append(u)
                    lock.unlock()
                }
            }
        }

        group.notify(queue: .main) {
            Task { @MainActor in
                await PanelDropHandler.handleDroppedURLs(
                    collected, presetManager: presetManager)
            }
        }
    }

    // MARK: - Panel context menu

    @ViewBuilder
    private func backgroundColorMenu() -> some View {
        Menu {
            let presetColors: [(String, String)] = [
                (L("システム既定_9f951e"), ""),
                (L("ダークネイビー_70cf68"), "#1a1a2e"),
                (L("ディープパープル_548918"), "#2d1b4e"),
                (L("ミッドナイトグリーン_c85eb7"), "#0d2b2b"),
                (L("チャコール_76021c"), "#2b2b2b"),
                (L("スレートブルー_13f2de"), "#1e2d3d"),
                (L("ダークレッド_0e9bcc"), "#2e1a1a"),
                (L("フォレストグリーン_6cc1ed"), "#1a2e1a"),
            ]
            let currentHex = presetManager.appConfig?.panels
                .first(where: { $0.id == panelID })?.window.backgroundColor
            ForEach(presetColors, id: \.1) { label, hex in
                Button {
                    let value = hex.isEmpty ? nil : hex
                    presetManager.updatePanelBackgroundColor(id: panelID, hex: value)
                    NotificationCenter.default.post(
                        name: .panelBackgroundColorChanged,
                        object: nil,
                        userInfo: ["id": panelID, "hex": value as Any]
                    )
                } label: {
                    HStack {
                        Text(label)
                        if (!hex.isEmpty && currentHex == hex)
                            || (hex.isEmpty && currentHex == nil) {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            Divider()
            Button {
                openColorPanel()
            } label: {
                Label(L("カスタム色_b41239"), systemImage: "paintpalette")
            }
        } label: {
            Label(L("背景色_2f97db"), systemImage: "paintbrush")
        }
    }

    private func openColorPanel() {
        let panel = NSColorPanel.shared
        let currentHex = presetManager.appConfig?.panels
            .first(where: { $0.id == panelID })?.window.backgroundColor
        if let hex = currentHex, hex.count >= 7, hex.hasPrefix("#"),
           let r = UInt8(hex.dropFirst().prefix(2), radix: 16),
           let g = UInt8(hex.dropFirst(3).prefix(2), radix: 16),
           let b = UInt8(hex.dropFirst(5).prefix(2), radix: 16) {
            panel.color = NSColor(
                srgbRed: CGFloat(r) / 255,
                green:   CGFloat(g) / 255,
                blue:    CGFloat(b) / 255,
                alpha:   1.0
            )
        }
        panel.setTarget(nil)
        panel.setAction(nil)
        let id = panelID
        let observer = NotificationCenter.default.addObserver(
            forName: NSColorPanel.colorDidChangeNotification,
            object: panel, queue: .main
        ) { [weak presetManager] note in
            guard let cp = note.object as? NSColorPanel,
                  let srgb = cp.color.usingColorSpace(.sRGB) else { return }
            let r = Int((srgb.redComponent   * 255).rounded())
            let g = Int((srgb.greenComponent * 255).rounded())
            let b = Int((srgb.blueComponent  * 255).rounded())
            let hex = String(format: "#%02X%02X%02X", r, g, b)
            presetManager?.updatePanelBackgroundColor(id: id, hex: hex)
            NotificationCenter.default.post(
                name: .panelBackgroundColorChanged,
                object: nil,
                userInfo: ["id": id, "hex": hex]
            )
        }
        panel.orderFront(nil)
        objc_setAssociatedObject(panel, "bgColorObserver", observer, .OBJC_ASSOCIATION_RETAIN)
    }

    @ViewBuilder
    private func panelContextMenu(preset: Preset) -> some View {
        if preset.groups.isEmpty {
            Button {
                addNewGroup()
            } label: {
                Label(L("新規グループを追加_8faec6"), systemImage: "folder.badge.plus")
            }
            Button {
                pasteGroup()
            } label: {
                Label(L("グループを貼り付け_7d4378"), systemImage: "doc.on.clipboard")
            }
            .disabled(!PasteboardHelper.hasGroup())
            Divider()
            backgroundColorMenu()
            Divider()
            Button {
                openSettings()
            } label: {
                Label(L("編集を開く_7cf378"), systemImage: "gear")
            }
        } else if preset.groups.count == 1, let group = preset.groups.first {
            Button {
                addNewButton(toGroupId: group.id)
            } label: {
                Label(L("新規ボタンを追加_03ae9c"), systemImage: "plus.circle")
            }
            Button {
                addNewGroup()
            } label: {
                Label(L("新規グループを追加_8faec6"), systemImage: "folder.badge.plus")
            }
            Divider()
            Button {
                pasteButtonToGroup(group.id)
            } label: {
                Label(L("ボタンを貼り付け_1743f6"), systemImage: "doc.on.clipboard")
            }
            .disabled(!PasteboardHelper.hasButton())
            Button {
                pasteGroup()
            } label: {
                Label(L("グループを貼り付け_7d4378"), systemImage: "doc.on.clipboard")
            }
            .disabled(!PasteboardHelper.hasGroup())
            Divider()
            backgroundColorMenu()
            Divider()
            Button {
                openSettings()
            } label: {
                Label(L("編集を開く_7cf378"), systemImage: "gear")
            }
        } else {
            ForEach(preset.groups, id: \.id) { group in
                Button {
                    addNewButton(toGroupId: group.id)
                } label: {
                    Label(L_("add_to_named_group", group.label), systemImage: "plus.circle")
                }
            }
            Divider()
            Button {
                addNewGroup()
            } label: {
                Label(L("新規グループを追加_8faec6"), systemImage: "folder.badge.plus")
            }
            Divider()
            Button {
                pasteButtonToGroup(preset.groups.last!.id)
            } label: {
                Label(L("ボタンを貼り付け_1743f6"), systemImage: "doc.on.clipboard")
            }
            .disabled(!PasteboardHelper.hasButton())
            Button {
                pasteGroup()
            } label: {
                Label(L("グループを貼り付け_7d4378"), systemImage: "doc.on.clipboard")
            }
            .disabled(!PasteboardHelper.hasGroup())
            Divider()
            backgroundColorMenu()
            Divider()
            Button {
                openSettings()
            } label: {
                Label(L("編集を開く_7cf378"), systemImage: "gear")
            }
        }
    }

    private func addNewButton(toGroupId groupId: String) {
        let id = "b-\(Int.random(in: 1000...9999))"
        let button = ButtonDefinition(
            id: id, label: L("新ボタン_d6206a"),
            iconText: "✨",
            action: .text(content: "", pasteDelayMs: 120, restoreClipboard: true, appendMode: false)
        )
        // このパネルのプリセットを編集ターゲットに切り替えてから add → settings で選択。
        presetManager.setEditTarget(panelID: panelID)
        _ = presetManager.addButton(button, toGroupId: groupId)
        openSettings(selectButtonId: id)
    }

    private func addNewGroup() {
        let id = "g-\(Int.random(in: 1000...9999))"
        let group = ButtonGroup(
            id: id, label: L("新グループ_050f97"),
            iconText: "📁",
            buttons: []
        )
        presetManager.setEditTarget(panelID: panelID)
        _ = presetManager.addGroup(group)
        openSettings(selectGroupId: id)
    }

    private func pasteButtonToGroup(_ groupId: String, afterButtonId: String? = nil) {
        guard let btn = PasteboardHelper.pasteButton() else { return }
        presetManager.setEditTarget(panelID: panelID)
        _ = presetManager.addButton(btn, toGroupId: groupId, afterButtonId: afterButtonId)
    }

    private func pasteGroup() {
        guard let group = PasteboardHelper.pasteGroup() else { return }
        presetManager.setEditTarget(panelID: panelID)
        _ = presetManager.addGroup(group)
    }

    // MARK: - Preset memo block

    /// プリセット単位メモの折りたたみブロック。タイトル行は常時表示し、
    /// クリックで本文を展開／格納する。展開状態はプリセット切替で false に
    /// 戻すことで「新しいプリセットでも気付ける」設計にしている。
    @ViewBuilder
    private func presetMemoBlock(_ memo: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Button(action: { withAnimation(.easeInOut(duration: 0.15)) { memoExpanded.toggle() } }) {
                HStack(spacing: 4) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 10))
                    Text(L("メモ_9490ad"))
                        .font(.system(size: 10, weight: .medium))
                    if !memoExpanded {
                        Text(memo.split(separator: "\n").first.map(String.init) ?? "")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: memoExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .foregroundColor(.primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if memoExpanded {
                Text(memo)
                    .font(.system(size: 11))
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)
                    .padding(.bottom, 4)
            }
        }
        .background(Color.yellow.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.yellow.opacity(0.35), lineWidth: 0.5)
        )
        .padding(.horizontal, 4)
        .onChange(of: panelPresetName) { _ in
            // このパネルのプリセットが切り替わったらメモ展開状態をリセット。
            memoExpanded = false
        }
    }

}
