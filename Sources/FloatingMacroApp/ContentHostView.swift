import SwiftUI
import AppKit
import UniformTypeIdentifiers
import FloatingMacroCore

struct ContentHostView: View {
    @ObservedObject var presetManager: PresetManager
    /// This panel's persistent ID (`PanelConfig.id`). Introduced in Phase 3.
    /// Use for switching preset reference and edit targets, various UI lookups.
    let panelID: String
    /// Phase 5: When the QR icon in the upper right corner of the panel is tapped, the AppDelegate side...
    /// Callback to call `openDeviceSend(panelID:)`.
    /// Maintain preview stability by not directly referencing AppDelegate from SwiftUI.
    /// Specifies which panel/preset to embed in the QR using the panelID argument.
    var onDeviceSendRequested: (String) -> Void = { _ in }
    @State private var confirmingPresetDelete = false
    @State private var showingPresetReorderSheet = false
    /// Preset memo folding/expanding state. Reset when switching presets.
    /// New preset notes should be "noticed in a compact state."
    @State private var memoExpanded: Bool = false
    /// While the app/file is being dragged over the panel, true.
    /// Use for driving visual feedback (blue frame highlight).
    @State private var isDropTargeted: Bool = false

    /// This is the preset currently displayed by this panel. In Phase 3, it is associated with panelID.
    /// Via `PanelConfig.presetName`, cache (PresetManager.loadedPresets)
    /// from obtaining. `@ObservedObject` via the `presetManager.appConfig` /
    /// Observing changes in `loadedPresets`, preset switching/editing is reflected immediately.
    private var panelPreset: Preset? {
        presetManager.panelPreset(forPanelID: panelID)
    }

    /// The preset name this panel points to. Reverse lookup from `appConfig.panels`.
    private var panelPresetName: String? {
        presetManager.appConfig?.panels.first(where: { $0.id == panelID })?.presetName
    }

    /// Saved scroll position of this panel (for restoration on app restart).
    /// Supply source for `PanelScrollView.initialY`. Even if `appConfig` changes, the view remains unchanged.
    /// Assuming capture and use before regeneration with `let initialY`.
    private var panelScrollY: Double {
        presetManager.appConfig?.panels.first(where: { $0.id == panelID })?.scrollY ?? 0
    }

    /// Before opening SettingsWindowController, set the edit target (currentPreset) to
    /// This is the shortcut to switch to a preset of this panel. Multiple panels are separate.
    /// When displaying presets, if the edit action is "Preset of this panel",
    /// To be done as per the request.
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
            // Header bar on top: Left for preset switching, right for connection to AI collaboration window.
            // By constantly displaying the preset picker here, you can manage multiple presets.
            // Make switch discovery easier (synchronize with settings screen picker).
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
                // Vertical is fixed (height does not become zero), horizontal is flexible.
                // Do not push out the icon group on the right when there is a long preset name.
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(0)
                .help(L("Switch preset _ Edit with right-click _ Sort _ Delete _ 2a0d21"))
                .contextMenu {
                    Button {
                        openSettings()
                    } label: {
                        Label(L("edit_ac1264"), systemImage: "pencil")
                    }
                    .disabled(panelPreset == nil)

                    Button {
                        showingPresetReorderSheet = true
                    } label: {
                        Label(L("Sort_3341c5"), systemImage: "arrow.up.arrow.down")
                    }
                    .disabled(presetManager.presetEntries.count < 2)

                    Divider()

                    Button(role: .destructive) {
                        confirmingPresetDelete = true
                    } label: {
                        Label(L("Delete eec57b"), systemImage: "trash")
                    }
                    .disabled(
                        panelPreset == nil
                        || panelPreset?.name == "default"
                    )
                }
                .confirmationDialog(
                    L("Are you sure you want to delete this preset? _e3f19c"),
                    isPresented: $confirmingPresetDelete,
                    titleVisibility: .visible
                ) {
                    if let preset = panelPreset {
                        Button(L_("delete_named_item", preset.displayName), role: .destructive) {
                            _ = presetManager.deletePreset(name: preset.name)
                        }
                    }
                    Button(L("Cancel 6ef349"), role: .cancel) {}
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
                .help(L("Open Edit Window_99e3e1"))

                // Phase 5: Send to device. Display this single QR panel.
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
                .help(L("Send to device 54b8f3"))

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
                .help(L("AI_Set up connection 6c80c4"))
            }
            .padding(.horizontal, 4)
            .padding(.top, 2)

            // Draw only if memo is not empty (collapsed preset). Memo is empty, do not draw.
            if let memo = panelPreset?.memo,
               !memo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                presetMemoBlock(memo)
            }

            // Button List
            if let preset = panelPreset {
                // Using PanelScrollView (NSScrollView wrapper) allows you to...
                // Scroll position can be restored after app restart.
                // The restored value is this panel's `PanelConfig.scrollY`. Scroll changes are
                // PresetManager persists with debounce.
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
                    Text(L("Preset could not be loaded: 4f5aeb"))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }

            // Error banner
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

            // Accessibility permission loss badge. CGEvent.post can be used without permissions.
            // Returning success treatment with void makes it impossible to notice even by just looking at the log.
            // (= Users feel that text buttons are ineffective.)
            // Here is the translation:
This places badges continuously, allowing them to be stripped after a rebuild.
            // Make sure the state can be visually recognized at all times.
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
                // Same-process prompt: true is AXIsProcessTrusted() stale
                // Return TRUE because there is a problem that the banner may disappear accidentally, so self-restart.
                // Call prompt: true after setting it to a clean state.
                let recover: () -> Void = {
                    // Self-restart recovery:
                    // Remove stale TCC entries with tccutil reset
                    // 2. Open Application in NSWorkspace
                    // Restart with arguments for accessibility
                    // Terminate current process in completion handler
                    //
                    // In contrast to the simpler version that calls prompt: true in the same process,
                    // Clean AX cache from a new process
                    // Calling true invokes old entries + stale TRUE
                    // Can avoid situations where adding to the list is hindered.
                    //
                    // Ensure argv in OpenConfiguration.arguments
                    // Passing `--prompt-accessibility` (Process + open --args)
                    // If via the Launch Services, there are cases where argv is lost.
                    // For this reason, use modern APIs).
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
                            // Fallback: Open only the settings screen
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
                    Text(L("Accessibility permission disabled: 8d74e5"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer(minLength: 4)
                    Button(action: recover) {
                        Text(L("Repair_87dfef"))
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
                    .help(L("tccutil_Reset _TCC_ entry with _prompt_accessibility_ to self 0x490e1b"))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.95))
                .cornerRadius(4)
                .padding(4)
            }
        }
        // Set no upper limit on maximum size. Previously maxWidth: 300, maxHeight: 600
        // Due to the hard cap, users were unable to drag an NSPanel.
        // Expanding but content not following, phenomenon that can shrink but cannot expand
        // Woke up. Set SwiftUI side to .infinity and NSPanel resize.
        // Follow all in full.
        .frame(minWidth: 180, maxWidth: .infinity,
               minHeight: 100, maxHeight: .infinity)
        // Accept file/app drop across the panel and convert it to a button.
        // The `.app` is a launch action based on the bundle ID, while other files are...
        // Registered as a launch action for absolute paths.
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDroppedProviders(providers)
            return true
        }
        .overlay(
            // Drag feedback during dragging. Similar to Stream Deck, here is the visual feedback while dragging.
            // Highlight the edge with an accent color so that it's clear which can be dropped.
            RoundedRectangle(cornerRadius: 6)
                .stroke(isDropTargeted ? Color.accentColor : Color.clear,
                        lineWidth: 3)
                .allowsHitTesting(false)
        )
    }

    /// Pass the fileURL obtained from the `.onDrop` provider to the PanelDropHandler.
    /// loadItem of NSItemProvider is callback-based, so gather asynchronously.
    /// Call the handler from the main thread when all pieces are available.
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
                (L("System Default_9f951e"), ""),
                (L("darknavy_70cf68"), "#1a1a2e"),
                (L("Deep Purple 548918"), "#2d1b4e"),
                (L("midnight_green_c85eb7"), "#0d2b2b"),
                (L("charcoal_76021c"), "#2b2b2b"),
                (L("SlateBlue_13F2DE"), "#1e2d3d"),
                (L("DarkRed_0e9bcc"), "#2e1a1a"),
                (L("ForestGreen_6cc1ed"), "#1a2e1a"),
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
                Label(L("Custom color_b41239"), systemImage: "paintpalette")
            }
        } label: {
            Label(L("Background color_2f97db"), systemImage: "paintbrush")
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
                Label(L("Add new group: 8faec6"), systemImage: "folder.badge.plus")
            }
            Button {
                pasteGroup()
            } label: {
                Label(L("Paste group 7d4378"), systemImage: "doc.on.clipboard")
            }
            .disabled(!PasteboardHelper.hasGroup())
            Divider()
            backgroundColorMenu()
            Divider()
            Button {
                openSettings()
            } label: {
                Label(L("Open Edit 7cf378"), systemImage: "gear")
            }
        } else if preset.groups.count == 1, let group = preset.groups.first {
            Button {
                addNewButton(toGroupId: group.id)
            } label: {
                Label(L("Add New Button 03ae9c"), systemImage: "plus.circle")
            }
            Button {
                addNewGroup()
            } label: {
                Label(L("Add new group: 8faec6"), systemImage: "folder.badge.plus")
            }
            Divider()
            Button {
                pasteButtonToGroup(group.id)
            } label: {
                Label(L("Button Paste 1743f6"), systemImage: "doc.on.clipboard")
            }
            .disabled(!PasteboardHelper.hasButton())
            Button {
                pasteGroup()
            } label: {
                Label(L("Paste group 7d4378"), systemImage: "doc.on.clipboard")
            }
            .disabled(!PasteboardHelper.hasGroup())
            Divider()
            backgroundColorMenu()
            Divider()
            Button {
                openSettings()
            } label: {
                Label(L("Open Edit 7cf378"), systemImage: "gear")
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
                Label(L("Add new group: 8faec6"), systemImage: "folder.badge.plus")
            }
            Divider()
            Button {
                pasteButtonToGroup(preset.groups.last!.id)
            } label: {
                Label(L("Button Paste 1743f6"), systemImage: "doc.on.clipboard")
            }
            .disabled(!PasteboardHelper.hasButton())
            Button {
                pasteGroup()
            } label: {
                Label(L("Paste group 7d4378"), systemImage: "doc.on.clipboard")
            }
            .disabled(!PasteboardHelper.hasGroup())
            Divider()
            backgroundColorMenu()
            Divider()
            Button {
                openSettings()
            } label: {
                Label(L("Open Edit 7cf378"), systemImage: "gear")
            }
        }
    }

    private func addNewButton(toGroupId groupId: String) {
        let id = "b-\(Int.random(in: 1000...9999))"
        let button = ButtonDefinition(
            id: id, label: L("New button _d6206a"),
            iconText: "✨",
            action: .text(content: "", pasteDelayMs: 120, restoreClipboard: true, appendMode: false)
        )
        // Switch to edit target preset of this panel, then select from add → settings.
        presetManager.setEditTarget(panelID: panelID)
        _ = presetManager.addButton(button, toGroupId: groupId)
        openSettings(selectButtonId: id)
    }

    private func addNewGroup() {
        let id = "g-\(Int.random(in: 1000...9999))"
        let group = ButtonGroup(
            id: id, label: L("New group_050f97"),
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

    /// Preset unit memo folding block. The title line is always displayed,
    /// Expand/Store text with a click. The expansion state is set to false by default for preset switching.
    /// By removing, we have designed it to be able to notice even with a new preset.
    @ViewBuilder
    private func presetMemoBlock(_ memo: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Button(action: { withAnimation(.easeInOut(duration: 0.15)) { memoExpanded.toggle() } }) {
                HStack(spacing: 4) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 10))
                    Text(L("memo_9490ad"))
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
            // Reset the memo expansion state when the panel's preset switches.
            memoExpanded = false
        }
    }

}
