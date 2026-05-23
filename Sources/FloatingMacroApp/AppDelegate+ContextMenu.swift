import AppKit
import FloatingMacroCore

extension AppDelegate {

    func buildContextMenu() -> NSMenu {
        let menu = NSMenu()

        // Most Frequent Operation Block
        menu.addItem(NSMenuItem(title: L("Show/Hide bbfc3d"), action: #selector(togglePanel), keyEquivalent: ""))

        let presetsMenu = NSMenu()
        for entry in presetManager.presetEntries {
            let item = NSMenuItem(title: entry.displayName,
                                  action: #selector(switchPreset(_:)),
                                  keyEquivalent: "")
            item.representedObject = entry.name
            if entry.name == presetManager.appConfig?.activePreset {
                item.state = .on
            }
            presetsMenu.addItem(item)
        }
        let presetsItem = NSMenuItem(title: L("Preset 96104a"), action: nil, keyEquivalent: "")
        presetsItem.submenu = presetsMenu
        menu.addItem(presetsItem)

        let panelsMenu = NSMenu()
        panelsMenu.addItem(
            NSMenuItem(title: L("Add new panel _83bc2f"),
                       action: #selector(addNewPanel),
                       keyEquivalent: "")
        )
        panelsMenu.addItem(NSMenuItem.separator())
        let configPanels = presetManager.appConfig?.panels ?? []
        for cfgPanel in configPanels {
            let displayName: String
            if let preset = presetManager.preset(named: cfgPanel.presetName) {
                displayName = preset.displayName
            } else {
                displayName = cfgPanel.presetName
            }
            let isDocked = cfgPanel.dockedEdge != nil
            let isVisible = panelManager?.panel(id: cfgPanel.id)?.isVisible ?? false

            let title = isDocked
                ? L_("panel_docked_title", displayName, cfgPanel.dockedEdge!.rawValue)
                : displayName
            let item = NSMenuItem(
                title: title,
                action: #selector(togglePanelByID(_:)),
                keyEquivalent: ""
            )
            item.representedObject = cfgPanel.id
            item.state = isVisible ? .on : .off
            panelsMenu.addItem(item)

            // Submenu: Docked → Expand + Move to another edge, Normal → Edge with Dock
            if isDocked {
                let expandItem = NSMenuItem(
                    title: L("Expand 5d14be"),
                    action: #selector(undockPanelByID(_:)),
                    keyEquivalent: ""
                )
                expandItem.representedObject = cfgPanel.id
                panelsMenu.addItem(expandItem)

                let moveMenu = NSMenu()
                for edge in [DockEdge.left, .right, .top, .bottom] where edge != cfgPanel.dockedEdge {
                    let mi = NSMenuItem(title: edgeLabel(edge),
                                        action: #selector(dockPanelToEdge(_:)),
                                        keyEquivalent: "")
                    mi.representedObject = "\(cfgPanel.id)|\(edge.rawValue)"
                    moveMenu.addItem(mi)
                }
                let moveItem = NSMenuItem(title: L("Move to another edge_f97d39"), action: nil, keyEquivalent: "")
                moveItem.submenu = moveMenu
                panelsMenu.addItem(moveItem)

                if cfgPanel.dockBarPosition != nil {
                    let resetItem = NSMenuItem(
                        title: L("Reset Position c8f3a0"),
                        action: #selector(resetDockBarPosition(_:)),
                        keyEquivalent: ""
                    )
                    resetItem.representedObject = cfgPanel.id
                    panelsMenu.addItem(resetItem)
                }
            } else {
                let dockMenu = NSMenu()
                for edge in [DockEdge.left, .right, .top, .bottom] {
                    let mi = NSMenuItem(title: edgeLabel(edge),
                                        action: #selector(dockPanelToEdge(_:)),
                                        keyEquivalent: "")
                    mi.representedObject = "\(cfgPanel.id)|\(edge.rawValue)"
                    dockMenu.addItem(mi)
                }
                let dockItem = NSMenuItem(title: L("Dock to Edge 51d926"), action: nil, keyEquivalent: "")
                dockItem.submenu = dockMenu
                panelsMenu.addItem(dockItem)
            }

            if configPanels.count > 1 {
                let removeItem = NSMenuItem(
                    title: L_("panel_close_and_remove", displayName),
                    action: #selector(removePanelByID(_:)),
                    keyEquivalent: ""
                )
                removeItem.representedObject = cfgPanel.id
                panelsMenu.addItem(removeItem)
            }
        }
        if configPanels.contains(where: { $0.dockedEdge != nil }) {
            panelsMenu.addItem(NSMenuItem.separator())
            panelsMenu.addItem(NSMenuItem(
                title: L("Collect Dock Bar _bef13e"),
                action: #selector(gatherAllDockBars),
                keyEquivalent: ""
            ))
        }
        let panelsItem = NSMenuItem(title: L("Panel_17f050"), action: nil, keyEquivalent: "")
        panelsItem.submenu = panelsMenu
        menu.addItem(panelsItem)

        menu.addItem(NSMenuItem.separator())

        // Setting Block
        menu.addItem(NSMenuItem(title: L("edit_ac1264"), action: #selector(openSettings), keyEquivalent: ","))

        let opacityMenu = NSMenu()
        let currentOpacity = presetManager.appConfig?.window.opacity ?? 1.0
        let opacityChoices: [(String, Double)] = [
            ("25%", 0.25), ("50%", 0.50), ("75%", 0.75), ("100%", 1.0),
        ]
        for (label, value) in opacityChoices {
            let item = NSMenuItem(title: label,
                                  action: #selector(setOpacity(_:)),
                                  keyEquivalent: "")
            item.representedObject = NSNumber(value: value)
            if abs(currentOpacity - value) < 0.01 {
                item.state = .on
            }
            opacityMenu.addItem(item)
        }
        let opacityItem = NSMenuItem(title: L("Opacity_34dac4"), action: nil, keyEquivalent: "")
        opacityItem.submenu = opacityMenu
        menu.addItem(opacityItem)

        menu.addItem(NSMenuItem.separator())

        // AI block ---
        let agentModeMenu = NSMenu()
        let currentMode = presetManager.appConfig?.controlAPI.agentMode ?? .normal
        let agentModeChoices: [(String, AgentMode)] = [
            (L("Normal_b7519e"),       .normal),
            (L("test_autonomous_1f6a94"), .test),
            ("Claude Code",    .claudeCode),
        ]
        for (label, mode) in agentModeChoices {
            let item = NSMenuItem(title: label,
                                  action: #selector(setAgentMode(_:)),
                                  keyEquivalent: "")
            item.representedObject = mode.rawValue
            if mode == currentMode { item.state = .on }
            agentModeMenu.addItem(item)
        }
        let agentModeItem = NSMenuItem(title: L("AI_mode_fec4eb"), action: nil, keyEquivalent: "")
        agentModeItem.submenu = agentModeMenu
        menu.addItem(agentModeItem)

        let apiEnabled = presetManager.appConfig?.controlAPI.enabled ?? false
        let apiPort = presetManager.appConfig?.controlAPI.port ?? 17430
        let apiTitle = apiEnabled
            ? L_("ai_connection_on_with_port", apiPort)
            : L("AI_Disconnect e932c6")
        let apiItem = NSMenuItem(title: apiTitle,
                                 action: #selector(toggleControlAPI),
                                 keyEquivalent: "")
        apiItem.state = apiEnabled ? .on : .off
        menu.addItem(apiItem)

        menu.addItem(NSMenuItem(title: L("AI_Connecting to 784c81..."), action: #selector(openAIIntegration), keyEquivalent: ""))

        // Phase 5: Modal for Sending to Smartphone/Tablet
        let sendItem = NSMenuItem(title: L("Send to device _f9ed8b"),
                                  action: #selector(openDeviceSendFromMenu),
                                  keyEquivalent: "")
        // ControlAPI is meaningless when OFF, so it should be disabled (auto enable is not supported).
        // There may be a plan to align with the OS's request within openDeviceSend.
        // Please turn on the AI connection first.)
        sendItem.isEnabled = (presetManager.appConfig?.controlAPI.enabled ?? false)
        menu.addItem(sendItem)

        menu.addItem(NSMenuItem.separator())

        // System Block ---
        menu.addItem(NSMenuItem(title: L("Open Settings Folder _be7046"), action: #selector(openConfigFolder), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: L("Reload 54db7f"), action: #selector(reloadConfig), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: L("FloatingMacro_About Menu"), action: #selector(showAbout), keyEquivalent: ""))

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: L("exit_65be33"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        return menu
    }

}
