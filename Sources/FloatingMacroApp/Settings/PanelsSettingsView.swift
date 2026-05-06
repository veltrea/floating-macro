import SwiftUI
import FloatingMacroCore

/// Phase 3 (P3-9) で導入された設定画面の「パネル」タブ。
/// 複数フローティングパネルの一覧と各パネルへの操作 (preset 切替・閉じる)
/// を提供する。メニューバーの「パネル」サブメニューと機能は重複するが、
/// 設定 window から発見しやすくし、複数パネルが多いときの一覧性を上げる。
struct PanelsSettingsView: View {
    @ObservedObject var presetManager: PresetManager

    private var panels: [PanelConfig] {
        presetManager.appConfig?.panels ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ヘッダー: 新規追加ボタンと説明文
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("フローティングパネル")
                        .font(.system(size: 14, weight: .semibold))
                    Text("複数のパネルを同時表示し、用途別に違うプリセットを割り当てられます。")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button {
                    addNewPanel()
                } label: {
                    Label("新しいパネルを追加", systemImage: "plus.rectangle")
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
                        Text("パネルが設定されていません。")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .padding(.top, 32)
                    }
                }
                .padding(16)
            }
        }
    }

    /// プライマリパネルの位置からオフセットして新規追加。
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
        // NSWindow の生成は AppDelegate.addNewPanel 経由ではなく、ここでは
        // appConfig 更新のみに留める。Settings 画面で追加されたパネルが
        // 即座に画面に出るには、AppDelegate 側で appConfig.panels の差分を
        // 監視して openNew する仕組みが要るが、現状は次回起動時に反映される。
        // (将来 AppDelegate に observer を追加して即時反映にする予定)
    }
}

/// 1 つのパネル行。プリセット選択・現在の表示状態・閉じるボタン。
private struct PanelRowView: View {
    @ObservedObject var presetManager: PresetManager
    let panel: PanelConfig
    let canDelete: Bool

    private var displayName: String {
        presetManager.preset(named: panel.presetName)?.displayName ?? panel.presetName
    }

    var body: some View {
        HStack(spacing: 12) {
            // 左: アイコン + パネル概要
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
                Text("位置 (\(Int(panel.window.x)), \(Int(panel.window.y))) ・ サイズ \(Int(panel.window.width))×\(Int(panel.window.height))")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text("id: \(panel.id.prefix(8))…")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.7))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 中央: プリセット選択
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
            .help("このパネルが表示するプリセットを切り替え")

            // 右: 削除ボタン
            Button(role: .destructive) {
                _ = presetManager.removePanel(id: panel.id)
                // NSWindow の orderOut は AppDelegate を経由しないと届かないが、
                // 次回起動で反映される (上の addNewPanel と同じ理由)。
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!canDelete)
            .help(canDelete
                  ? "このパネルを設定から削除"
                  : "最後の 1 件は削除できません")
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
}
