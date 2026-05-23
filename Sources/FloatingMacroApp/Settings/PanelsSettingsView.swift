import SwiftUI
import FloatingMacroCore

/// Panel tab introduced in Phase 3 (P3-9) settings screen.
/// List of multiple floating panels and operations for each panel (switch preset, close)
/// Provides a panel. The menu bar's "Panel" submenu and feature overlap, but
/// Make the settings window easier to find and improve listability when there are many panels.
struct PanelsSettingsView: View {
    @ObservedObject var presetManager: PresetManager

    private var panels: [PanelConfig] {
        presetManager.appConfig?.panels ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: New Add Button and Description
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Floating Panel 9df495"))
                        .font(.system(size: 14, weight: .semibold))
                    Text(L("Display multiple panels simultaneously and assign different presets for each panel based on their purpose. 9d08cd"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button {
                    addNewPanel()
                } label: {
                    Label(L("Add new panel _83bc2f"), systemImage: "plus.rectangle")
                }
                .controlSize(.regular)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(panels, id: \.id) { panel in
                        PanelRowView(
                            presetManager: presetManager,
                            panel: panel,
                            canDelete: panels.count > 1
                        )
                    }
                    if panels.isEmpty {
                        Text(L("Panel not set_a8a5cd"))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .padding(.top, 32)
                    }
                }
                .padding(16)
            }
        }
    }

    /// Add new panel at an offset from the primary panel's position.
    private func addNewPanel() {
        let primary = presetManager.appConfig?.panels.first
        let baseX = primary?.window.x ?? 100
        let baseY = primary?.window.y ?? 100
        let baseW = primary?.window.width ?? 200
        let baseH = primary?.window.height ?? 300
        let win = WindowConfig(
            x: baseX + 32, y: baseY - 32,
            width: baseW, height: baseH,
            opacity: 1.0
        )
        let presetName = primary?.presetName ?? "default"
        _ = presetManager.addPanel(presetName: presetName, window: win)
        // The creation of NSWindow is not done through AppDelegate.addNewPanel, but here
        // Keep only updates to appConfig. Settings screen added panels should be
        // Instantly appear on the screen, you need to calculate the difference in appConfig.panels from the AppDelegate side.
        // A mechanism is required to monitor and trigger openNew, but currently it only reflects on the next startup.
        // Plans to add observers to AppDelegate for immediate reflection.
    }
}

/// One panel row. Preset selection, background color, current display state, close button.
private struct PanelRowView: View {
    @ObservedObject var presetManager: PresetManager
    let panel: PanelConfig
    let canDelete: Bool

    @State private var useBgColor: Bool
    @State private var bgColor: Color
    @State private var bgHex: String

    init(presetManager: PresetManager, panel: PanelConfig, canDelete: Bool) {
        self.presetManager = presetManager
        self.panel = panel
        self.canDelete = canDelete
        let hex = panel.window.backgroundColor
        _useBgColor = State(initialValue: hex != nil)
        _bgColor = State(initialValue: Self.colorFromHex(hex) ?? Color(NSColor.windowBackgroundColor))
        _bgHex = State(initialValue: hex ?? "")
    }

    private var displayName: String {
        presetManager.preset(named: panel.presetName)?.displayName ?? panel.presetName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                // Left: Icon + Panel Overview
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: panel.visible
                              ? "rectangle.inset.filled"
                              : "rectangle.dashed")
                            .font(.system(size: 14))
                            .foregroundColor(panel.visible ? .accentColor : .secondary)
                        Text(displayName)
                            .font(.system(size: 13, weight: .medium))
                    }
                    Text(L_("panel_position_size", Int(panel.window.x), Int(panel.window.y), Int(panel.window.width), Int(panel.window.height)))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text("id: \(panel.id.prefix(8))…")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Central: Preset Selection
                Menu {
                    ForEach(presetManager.presetEntries) { entry in
                        Button(action: {
                            presetManager.switchPanelPreset(panelID: panel.id, to: entry.name)
                        }) {
                            if entry.name == panel.presetName {
                                Label(entry.displayName, systemImage: "checkmark")
                            } else {
                                Text(entry.displayName)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(displayName)
                            .font(.system(size: 11))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(L("Switch preset displayed on this panel _1e7816"))

                // Delete button
                Button(role: .destructive) {
                    _ = presetManager.removePanel(id: panel.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!canDelete)
                .help(canDelete
                      ? L("Delete this panel from Settings _8504d8")
                      : L("The last _1_ item cannot be deleted_81a5fa"))
            }

            // background color
            HStack(spacing: 8) {
                Text(L("Background color_2f97db"))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Toggle("", isOn: $useBgColor)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                    .onChange(of: useBgColor) { enabled in
                        if enabled {
                            let hex = Self.hexFromColor(bgColor)
                            bgHex = hex
                            commitColor(hex)
                        } else {
                            bgHex = ""
                            commitColor(nil)
                        }
                    }
                if useBgColor {
                    ContinuousColorPicker(color: $bgColor)
                        .frame(width: 36, height: 20)
                        .onChange(of: bgColor) { newValue in
                            let hex = Self.hexFromColor(newValue)
                            bgHex = hex
                            commitColor(hex)
                        }
                    TextField("#RRGGBB", text: $bgHex)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                        .font(.system(size: 11, design: .monospaced))
                        .onSubmit {
                            if let c = Self.colorFromHex(bgHex) {
                                bgColor = c
                                commitColor(bgHex)
                            }
                        }
                } else {
                    Text(L("System Default_9f951e"))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.leading, 4)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
        )
    }

    private func commitColor(_ hex: String?) {
        presetManager.updatePanelBackgroundColor(id: panel.id, hex: hex)
        NotificationCenter.default.post(
            name: .panelBackgroundColorChanged,
            object: nil,
            userInfo: ["id": panel.id, "hex": hex as Any]
        )
    }

    private static func hexFromColor(_ color: Color) -> String {
        let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? .black
        let r = Int((nsColor.redComponent   * 255).rounded())
        let g = Int((nsColor.greenComponent * 255).rounded())
        let b = Int((nsColor.blueComponent  * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    private static func colorFromHex(_ hex: String?) -> Color? {
        guard let hex, hex.count >= 7, hex.hasPrefix("#"),
              let r = UInt8(hex.dropFirst().prefix(2), radix: 16),
              let g = UInt8(hex.dropFirst(3).prefix(2), radix: 16),
              let b = UInt8(hex.dropFirst(5).prefix(2), radix: 16) else {
            return nil
        }
        return Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }
}

extension Notification.Name {
    static let panelBackgroundColorChanged = Notification.Name("PanelBackgroundColorChanged")
}
