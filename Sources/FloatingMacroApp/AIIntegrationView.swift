import SwiftUI
import AppKit
import FloatingMacroCore

/// "AI 連携" の独立ウィンドウ用ビュー。FloatingMacro を AI（Claude Code /
/// Cursor / Gemini CLI / ChatGPT 等）に操作させるための初期セットアップを
/// ワンクリックで行う。
///
/// 設計判断：Settings ウィンドウのタブにするのではなく独立ウィンドウとした。
/// Settings は「ボタン編集」というオブジェクト単位の編集ツールである一方、
/// このビューは「アプリ全体に対する初期セットアップ」で UI の粒度が違う。
/// 同じウィンドウに入れると per-button 操作と app-wide 操作が混在して
/// 混乱するため、`AIIntegrationWindowController` から呼ばれる別ウィンドウとして扱う。
///
/// 提供する操作：
/// 1. AI に貼り付ける接続用プロンプトをクリップボードへコピーする
///    （Bearer トークンを埋め込み済み — そのまま貼ればAIが /manifest 経由で
///    自己紹介を読み、以降の操作方法を理解する）
/// 2. Claude Code (`~/.claude.json`) に MCP エントリをワンクリック登録する
///    （次回 Claude Code 起動時に floatingmacro が自動接続される）
struct AIIntegrationView: View {
    @ObservedObject var presetManager: PresetManager
    @State private var statusMessage: String = ""
    @State private var statusIsError: Bool = false
    @State private var promptPreview: String = ""

    private var port: Int {
        presetManager.appConfig?.controlAPI.port ?? 17430
    }

    private var endpoint: String {
        "http://127.0.0.1:\(port)"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // ─── 概要 ───────────────────────────────────────────
                VStack(alignment: .leading, spacing: 6) {
                    Text("AI に FloatingMacro を操作させる")
                        .font(.title3).fontWeight(.semibold)
                    Text("FloatingMacro は \(endpoint) で HTTP API を公開しており、AI コーディングツール（Claude Code、Cursor、Gemini CLI、ChatGPT 等）から自分自身の設定を読み書きできます。下の操作で、AI 側に必要な情報を渡せます。")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()

                // ─── アクション 1: プロンプトをコピー ────────────────────
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.on.clipboard")
                        Text("接続用プロンプトをコピー").font(.headline)
                    }

                    Text("Claude Code、Cursor、ChatGPT 等の AI に貼り付けるプロンプトをクリップボードにコピーします。Bearer トークンが埋め込まれた状態で、AI に貼り付けるだけで FloatingMacro を操作できるようになります。")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack {
                        Button(action: copyConnectionPrompt) {
                            Label("プロンプトをコピー", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.borderedProminent)

                        Button(action: { promptPreview = makeConnectionPrompt(token: tokenForPreview()) }) {
                            Text("プレビューを更新")
                        }
                        .buttonStyle(.bordered)
                    }

                    if !promptPreview.isEmpty {
                        ScrollView(.vertical) {
                            Text(promptPreview)
                                .font(.system(size: 11, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .padding(8)
                        }
                        .frame(maxHeight: 180)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.3)))
                    }
                }
                .padding(14)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2)))

                // ─── アクション 2: Claude Code に MCP 登録 ───────────────
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "gearshape.2")
                        Text("Claude Code に MCP として登録").font(.headline)
                    }

                    Text("~/.claude.json に floatingmacro エントリを追記します。Claude Code を再起動すると自動的に MCP サーバーとして接続されます。既存の mcpServers 設定は壊しません。")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button(action: registerClaudeCodeMCP) {
                        Label("Claude Code に登録", systemImage: "checkmark.shield")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(14)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2)))

                // ─── 接続情報（参考） ───────────────────────────────
                VStack(alignment: .leading, spacing: 6) {
                    Text("接続情報").font(.headline)
                    HStack(spacing: 6) {
                        Text("エンドポイント:").foregroundColor(.secondary)
                        Text(endpoint).font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                        CopyInlineButton(text: endpoint)
                    }
                    HStack(alignment: .top, spacing: 6) {
                        Text("トークン取得:").foregroundColor(.secondary)
                        Text("security find-generic-password -s FloatingMacro -a ControlAPIToken -w")
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        CopyInlineButton(text: "security find-generic-password -s FloatingMacro -a ControlAPIToken -w")
                    }
                    Text("認証不要のディスカバリー: GET /manifest, /help, /.well-known/agent.json, /openapi.json, /ping, /health")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // ─── 結果メッセージ ──────────────────────────────────
                if !statusMessage.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: statusIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .foregroundColor(statusIsError ? .orange : .green)
                        Text(statusMessage)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10)
                    .background((statusIsError ? Color.orange : Color.green).opacity(0.12))
                    .cornerRadius(6)
                }
            }
            .padding(20)
        }
    }

    // MARK: - Actions

    private func copyConnectionPrompt() {
        guard let token = loadToken() else {
            setStatus("Keychain からトークンを取得できませんでした。", isError: true)
            return
        }
        let prompt = makeConnectionPrompt(token: token)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(prompt, forType: .string)
        setStatus("クリップボードにコピーしました（\(prompt.count) 文字）。AI に貼り付けてください。", isError: false)
    }

    private func registerClaudeCodeMCP() {
        guard let token = loadToken() else {
            setStatus("Keychain からトークンを取得できませんでした。", isError: true)
            return
        }
        let url = URL(fileURLWithPath: NSString(string: "~/.claude.json").expandingTildeInPath)
        var dict: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                let data = try Data(contentsOf: url)
                if let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    dict = parsed
                }
            } catch {
                setStatus("既存の ~/.claude.json を読めませんでした: \(error.localizedDescription)", isError: true)
                return
            }
        }
        var mcpServers = dict["mcpServers"] as? [String: Any] ?? [:]
        mcpServers["floatingmacro"] = [
            "type": "http",
            "url":  "\(endpoint)/mcp",
            "headers": ["Authorization": "Bearer \(token)"],
        ] as [String: Any]
        dict["mcpServers"] = mcpServers
        do {
            let out = try JSONSerialization.data(withJSONObject: dict,
                                                 options: [.prettyPrinted, .sortedKeys])
            try out.write(to: url, options: .atomic)
            setStatus("登録しました。Claude Code を再起動すれば floatingmacro が自動接続されます。", isError: false)
        } catch {
            setStatus("書き込みに失敗しました: \(error.localizedDescription)", isError: true)
        }
    }

    // MARK: - Helpers

    private func loadToken() -> String? {
        try? TokenStore.loadOrCreate()
    }

    private func tokenForPreview() -> String {
        loadToken() ?? "<トークンを Keychain から取得できませんでした>"
    }

    private func setStatus(_ message: String, isError: Bool) {
        statusMessage = message
        statusIsError = isError
    }

    /// 文字列の右脇に置く小さなコピーボタン。クリックでクリップボードに
    /// コピーし、約 1.5 秒だけアイコンが ✓ に変わって完了をフィードバックする。
    private struct CopyInlineButton: View {
        let text: String
        @State private var copied: Bool = false

        var body: some View {
            Button {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(text, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    copied = false
                }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11))
                    .foregroundColor(copied ? .green : .secondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help("クリップボードにコピー")
        }
    }

    private func makeConnectionPrompt(token: String) -> String {
        """
        あなたは macOS 上で動いている FloatingMacro を操作できる AI です。

        接続先: \(endpoint)
        認証トークン: \(token)

        最初に curl -s \(endpoint)/manifest | jq を実行してアプリの自己紹介と全ツール定義を取得してください（このエンドポイントは認証不要）。manifest の中の systemPrompt と tools 配列がこの API の真の説明書です。

        操作の原則:
        - すべてのツール呼び出しは POST /tools/call 経由で行う
        - 個別エンドポイント (/group/add 等) を直接叩かない
        - 認証が必要なエンドポイントには Authorization: Bearer ヘッダにトークンを付ける

        現状を把握してから作業を始めてください:
        - GET /state でパネル状態とアクティブプリセットを取得
        - GET /preset/current で現在のグループ・ボタン構成を取得

        ユーザーがあなたに FloatingMacro の操作権限を与えています。何をしたいか確認してから作業に入ってください。
        """
    }
}
