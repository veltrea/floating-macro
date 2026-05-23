import SwiftUI
import AppKit
import UniformTypeIdentifiers
import FloatingMacroCore

/// Root view of the Settings window. Left column: preset selector + group
/// browser. Right column: detail form for the selected button.
struct SettingsView: View {
    @ObservedObject var presetManager: PresetManager
    @State private var selectedButtonId: String?
    @State private var selectedGroupId: String?
    @State private var activeTab: SettingsTab = .buttons

    enum SettingsTab: String, Hashable {
        case buttons  = "buttons"
        case panels   = "panels"
        case security = "security"

        var localizedLabel: String {
            switch self {
            case .buttons:  return L("編集_757886")
            case .panels:   return L("パネル_17f050")
            case .security: return L("セキュリティ_1c7258")
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 0) {
                ForEach([SettingsTab.buttons, .panels, .security], id: \.self) { tab in
                    Button(action: { activeTab = tab }) {
                        Text(tab.localizedLabel)
                            .font(.system(size: 13))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 7)
                            .background(activeTab == tab
                                ? Color(NSColor.selectedContentBackgroundColor).opacity(0.15)
                                : Color.clear)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(activeTab == tab ? .primary : .secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)

            Divider()

            // tab content
            switch activeTab {
            case .buttons:
                HSplitView {
                    SettingsSidebar(
                        presetManager: presetManager,
                        selectedButtonId: $selectedButtonId,
                        selectedGroupId: $selectedGroupId
                    )
                    .frame(minWidth: 260, idealWidth: 300, maxWidth: 400)

                    SettingsDetail(
                        presetManager: presetManager,
                        selectedButtonId: $selectedButtonId,
                        selectedGroupId: $selectedGroupId
                    )
                    .frame(minWidth: 360, idealWidth: 420)
                }

            case .panels:
                PanelsSettingsView(presetManager: presetManager)

            case .security:
                SecuritySettingsView(presetManager: presetManager)
            }
        }
        .frame(minWidth: 640, minHeight: 480)
        .onAppear { selectFirstButtonIfNeeded() }
        .onChange(of: presetManager.externalSelectButtonRequest) { requestedId in
            guard let id = requestedId else { return }
            activeTab = .buttons
            applyExternalSelection(id)
            // Consume the request so the same id can be requested twice.
            presetManager.externalSelectButtonRequest = nil
        }
        .onChange(of: presetManager.externalSelectGroupRequest) { requestedId in
            guard let id = requestedId else { return }
            activeTab = .buttons
            selectedGroupId = id
            selectedButtonId = nil
            presetManager.externalSelectGroupRequest = nil
        }
        .onChange(of: presetManager.clearSelectionNonce) { _ in
            selectedButtonId = nil
            selectedGroupId = nil
        }
    }

    /// On open, auto-select the first button in the first non-empty group so
    /// the detail pane isn't an empty "select a button" message. Preserves
    /// the user's existing selection if they reopen the window.
    private func selectFirstButtonIfNeeded() {
        guard selectedButtonId == nil,
              let preset = presetManager.currentPreset else { return }
        for group in preset.groups {
            if let first = group.buttons.first {
                selectedGroupId = group.id
                selectedButtonId = first.id
                return
            }
        }
    }

    /// Jump selection to the given button id (usually from a right-click
    /// "Edit…" on the floating panel).
    private func applyExternalSelection(_ id: String) {
        guard let preset = presetManager.currentPreset else { return }
        for group in preset.groups {
            if group.buttons.contains(where: { $0.id == id }) {
                selectedGroupId = group.id
                selectedButtonId = id
                return
            }
        }
    }
}
