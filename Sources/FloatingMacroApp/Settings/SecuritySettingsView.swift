import SwiftUI
import AppKit
import UniformTypeIdentifiers
import FloatingMacroCore

// MARK: - SecuritySettingsView

/// Command blacklist and auto-pilot settings edit screen.
struct SecuritySettingsView: View {
    @ObservedObject var presetManager: PresetManager

    // Local editing state
    @State private var enabled: Bool = true
    @State private var autopilotEnabled: Bool = false
    @State private var hasPassword: Bool = false
    @State private var patterns: [String] = []
    @State private var newPattern: String = ""
    @State private var editingIndex: Int? = nil
    @State private var editingText: String = ""

    // Password Setting Sheet
    @State private var showingSetPasswordSheet: Bool = false
    @State private var newPassword1: String = ""
    @State private var newPassword2: String = ""
    @State private var passwordError: String = ""

    private var blacklist: CommandBlacklist {
        presetManager.appConfig?.commandBlacklist ?? CommandBlacklist()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // Header description
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("コマンドセーフガード_c5f232"))
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text(L("登録したパターンを含むコマンド_テキストをターミナルに送る前に確認ダイアログを表示します_大文字_小_858217"))
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Enabled / Disabled Toggle
                Toggle(L("確認ダイアログを有効にする_27222d"), isOn: $enabled)
                    .toggleStyle(.switch)
                    .onChange(of: enabled) { newValue in
                        presetManager.setCommandBlacklistEnabled(newValue)
                    }

                Divider()

                // Autopilot Section --------------------------------------------
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "airplane")
                            .foregroundColor(autopilotEnabled ? .orange : .secondary)
                        Text(L("オートパイロットモード_03f795"))
                            .font(.headline)
                        if autopilotEnabled {
                            Text(L("有効_ce1518"))
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.2))
                                .foregroundColor(.orange)
                                .cornerRadius(4)
                        }
                    }

                    Text(L("有効にすると_パターンに一致するコマンドでも確認ダイアログなしで実行されます_AIに完全に操作を委ね_c01c70"))
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if !hasPassword {
                        HStack(spacing: 8) {
                            Image(systemName: "lock.slash")
                                .foregroundColor(.secondary)
                            Text(L("パスワードが未設定です_先にパスワードを設定してください_7fe6ab"))
                                .font(.callout)
                                .foregroundColor(.secondary)
                        }
                        Button(L("パスワードを設定する_e91363")) {
                            newPassword1 = ""; newPassword2 = ""; passwordError = ""
                            showingSetPasswordSheet = true
                        }
                    } else {
                        HStack(spacing: 12) {
                            if autopilotEnabled {
                                Button(L("オートパイロットを無効にする_fa7832")) {
                                    presetManager.disableAutopilot()
                                    autopilotEnabled = false
                                }
                                .foregroundColor(.orange)
                            } else {
                                Button(L("オートパイロットを有効にする_69de91")) {
                                    enableAutopilotWithPrompt()
                                }
                            }
                            Button(L("パスワードを変更する_ba5901")) {
                                newPassword1 = ""; newPassword2 = ""; passwordError = ""
                                showingSetPasswordSheet = true
                            }
                            .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(14)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(autopilotEnabled ? Color.orange.opacity(0.5) : Color.gray.opacity(0.2))
                )

                if enabled {
                    Divider()

                    // pattern list
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("確認対象パターン一覧_e4b5f1"))
                            .font(.headline)

                        if patterns.isEmpty {
                            Text(L("パターンが登録されていません_f9f240"))
                                .foregroundColor(.secondary)
                                .font(.callout)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(patterns.indices, id: \.self) { i in
                                    HStack(spacing: 8) {
                                        if editingIndex == i {
                                            TextField(L("パターン_1f6ae2"), text: $editingText)
                                                .textFieldStyle(.roundedBorder)
                                                .font(.system(size: 12, design: .monospaced))
                                            Button(L("確定_ba0fcf")) {
                                                let trimmed = editingText.trimmingCharacters(in: .whitespaces)
                                                if !trimmed.isEmpty {
                                                    patterns[i] = trimmed
                                                    savePatterns()
                                                }
                                                editingIndex = nil
                                            }
                                            .buttonStyle(.borderedProminent)
                                            .controlSize(.small)
                                            Button(L("キャンセル_6ef349")) { editingIndex = nil }
                                                .controlSize(.small)
                                        } else {
                                            Text(patterns[i])
                                                .font(.system(size: 12, design: .monospaced))
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                            Button(L("編集_757886")) {
                                                editingIndex = i
                                                editingText = patterns[i]
                                            }
                                            .controlSize(.small)
                                            Button(role: .destructive) {
                                                patterns.remove(at: i)
                                                savePatterns()
                                            } label: {
                                                Image(systemName: "trash")
                                            }
                                            .controlSize(.small)
                                        }
                                    }
                                    .padding(.vertical, 5)
                                    .padding(.horizontal, 8)
                                    .background(i % 2 == 0
                                        ? Color(NSColor.controlBackgroundColor)
                                        : Color.clear)
                                }
                            }
                            .cornerRadius(6)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.2)))
                        }
                    }

                    // Add new pattern
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L("パターンを追加_bf7d0b"))
                            .font(.headline)
                        HStack {
                            TextField(L("例_rm_rf_ee43ae"), text: $newPattern)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                                .onSubmit { addPattern() }
                            Button(L("追加_7dc3a5"), action: addPattern)
                                .disabled(newPattern.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }

                    HStack {
                        Button(L("デフォルトパターンに戻す_516a9f")) {
                            patterns = CommandBlacklist.defaultPatterns
                            savePatterns()
                        }
                        .foregroundColor(.orange)
                        Spacer()
                        Text(L_("patterns_registered_count", patterns.count))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { loadFromConfig() }
        .onChange(of: presetManager.appConfig?.commandBlacklist) { _ in
            loadFromConfig()
        }
        // Password Setting Sheet
        .sheet(isPresented: $showingSetPasswordSheet) {
            VStack(alignment: .leading, spacing: 16) {
                Text(hasPassword ? L("パスワードを変更_fb3e11") : L("オートパイロット用パスワードを設定_55fc32"))
                    .font(.headline)

                if hasPassword {
                    SecureField(L("現在のパスワード_ada493"), text: $newPassword1)
                        .textFieldStyle(.roundedBorder)
                    SecureField(L("新しいパスワード_291f74"), text: $newPassword2)
                        .textFieldStyle(.roundedBorder)
                } else {
                    SecureField(L("パスワード_4bdfe7"), text: $newPassword1)
                        .textFieldStyle(.roundedBorder)
                    SecureField(L("確認のためもう一度_6bd0d5"), text: $newPassword2)
                        .textFieldStyle(.roundedBorder)
                }

                if !passwordError.isEmpty {
                    Text(passwordError)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                HStack {
                    Button(L("キャンセル_6ef349")) {
                        showingSetPasswordSheet = false
                    }
                    Spacer()
                    Button(hasPassword ? L("変更する_0f1a79") : L("設定する_a160b0")) {
                        commitPassword()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newPassword1.isEmpty || newPassword2.isEmpty)
                }
            }
            .padding(24)
            .frame(width: 320)
        }
    }

    // MARK: - Helpers

    private func loadFromConfig() {
        let bl = blacklist
        enabled         = bl.enabled
        autopilotEnabled = bl.autopilotEnabled
        hasPassword     = bl.autopilotPasswordHash != nil
        patterns        = bl.patterns
    }

    private func addPattern() {
        let trimmed = newPattern.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !patterns.contains(trimmed) else { return }
        patterns.append(trimmed)
        newPattern = ""
        savePatterns()
    }

    private func savePatterns() {
        presetManager.setCommandBlacklistPatterns(patterns)
    }

    private func enableAutopilotWithPrompt() {
        guard let passphrase = CommandConfirmation.promptPassphrase(
            title: L("オートパイロットを有効にする_3d57fc"),
            message: L("パスワードを入力してください_n有効にすると確認ダイアログなしにすべてのコマンドが実行されます_927a3e")
        ) else { return }
        if presetManager.enableAutopilot(passphrase: passphrase) {
            autopilotEnabled = true
        } else {
            let alert = NSAlert()
            alert.messageText = L("パスワードが違います_e629b7")
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    private func commitPassword() {
        if hasPassword {
            // Changed: newPassword1 = Currently, newPassword2 = New
            if newPassword2.count < 4 {
                passwordError = L("4文字以上のパスワードを設定してください_85efe5")
                return
            }
            if presetManager.setAutopilotPassword(oldPassphrase: newPassword1, newPassphrase: newPassword2) {
                hasPassword = true
                showingSetPasswordSheet = false
            } else {
                passwordError = L("現在のパスワードが違います_2309b8")
            }
        } else {
            // New setting: newPassword1 = password, newPassword2 = confirm
            guard newPassword1 == newPassword2 else {
                passwordError = L("パスワードが一致しません_0fa3b3")
                return
            }
            if newPassword1.count < 4 {
                passwordError = L("4文字以上のパスワードを設定してください_85efe5")
                return
            }
            if presetManager.setAutopilotPassword(oldPassphrase: nil, newPassphrase: newPassword1) {
                hasPassword = true
                showingSetPasswordSheet = false
            }
        }
    }
}
