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

                // ─── アクション 2: 各 AI クライアントに MCP 登録 ───────────
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "gearshape.2")
                        Text("AI クライアントに MCP として登録").font(.headline)
                    }

                    Text("対応する AI クライアントの設定ファイルに floatingmacro エントリを追記します。クライアントを再起動すると MCP サーバーとして自動接続されます。既存の設定は壊しません。")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 8) {
                        registerRow(
                            icon: "checkmark.shield",
                            title: "Claude Code",
                            subtitle: "~/.claude.json",
                            httpAction: registerClaudeCodeMCP,
                            stdioAction: registerClaudeCodeStdio
                        )
                        registerRow(
                            icon: "cursorarrow.rays",
                            title: "Cursor",
                            subtitle: "~/.cursor/mcp.json",
                            httpAction: registerCursorMCP,
                            stdioAction: registerCursorStdio
                        )
                        registerRow(
                            icon: "terminal",
                            title: "Gemini CLI",
                            subtitle: "~/.gemini/settings.json",
                            httpAction: registerGeminiCLIMCP,
                            stdioAction: registerGeminiCLIStdio
                        )
                        registerRow(
                            icon: "chevron.left.forwardslash.chevron.right",
                            title: "VS Code",
                            subtitle: "~/Library/Application Support/Code/User/mcp.json",
                            httpAction: registerVSCodeMCP,
                            stdioAction: registerVSCodeStdio
                        )
                        registerRow(
                            icon: "wind",
                            title: "Windsurf",
                            subtitle: "~/.codeium/windsurf/mcp_config.json",
                            httpAction: registerWindsurfMCP,
                            stdioAction: registerWindsurfStdio
                        )
                    }

                    Text("「CLI 登録」(青) は fmcli というコマンドラインツール経由で接続する方式 (推奨)。「HTTP 登録」(枠) は HTTP 経由で接続する方式 (中級者向け)。両方を同時に登録することも可能です (内部的に別名で登録されるので衝突しません)。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Claude Desktop / Trae / Antigravity の登録ボタンは未提供。Claude Desktop は Pro 以上で「設定 → Connectors」から URL を直接登録できます (URL とトークンは下の『接続情報』からコピーしてください)。または手動で claude_desktop_config.json に CLI 経由で登録してください (詳細はマニュアル参照)。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
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
        registerHTTPMCP(
            clientName: "Claude Code",
            relativePath: "~/.claude.json",
            rootKey: "mcpServers",
            entry: { token in [
                "type": "http",
                "url":  "\(endpoint)/mcp",
                "headers": ["Authorization": "Bearer \(token)"],
            ] }
        )
    }

    private func registerCursorMCP() {
        // Cursor: ~/.cursor/mcp.json の mcpServers に { url, headers } を書く。
        // 最新の Cursor は url の存在で HTTP transport と判別する (type 不要)。
        registerHTTPMCP(
            clientName: "Cursor",
            relativePath: "~/.cursor/mcp.json",
            rootKey: "mcpServers",
            entry: { token in [
                "url":  "\(endpoint)/mcp",
                "headers": ["Authorization": "Bearer \(token)"],
            ] }
        )
    }

    private func registerGeminiCLIMCP() {
        // Gemini CLI: ~/.gemini/settings.json の mcpServers に
        // { httpUrl, headers } を書く。Gemini CLI は httpUrl フィールドを
        // StreamableHTTPClientTransport にマップする (url は SSE 用で別物)。
        registerHTTPMCP(
            clientName: "Gemini CLI",
            relativePath: "~/.gemini/settings.json",
            rootKey: "mcpServers",
            entry: { token in [
                "httpUrl":  "\(endpoint)/mcp",
                "headers": ["Authorization": "Bearer \(token)"],
            ] }
        )
    }

    private func registerVSCodeMCP() {
        // VS Code: 新仕様の ~/Library/Application Support/Code/User/mcp.json
        // を使う。ルートキーは "servers" (他クライアントの "mcpServers" とは違う)、
        // type は "http"。
        registerHTTPMCP(
            clientName: "VS Code",
            relativePath: "~/Library/Application Support/Code/User/mcp.json",
            rootKey: "servers",
            entry: { token in [
                "type": "http",
                "url":  "\(endpoint)/mcp",
                "headers": ["Authorization": "Bearer \(token)"],
            ] }
        )
    }

    private func registerWindsurfMCP() {
        // Windsurf: ~/.codeium/windsurf/mcp_config.json の mcpServers に
        // { serverUrl, headers } を書く (URL フィールド名が他と違う)。
        registerHTTPMCP(
            clientName: "Windsurf",
            relativePath: "~/.codeium/windsurf/mcp_config.json",
            rootKey: "mcpServers",
            entry: { token in [
                "serverUrl":  "\(endpoint)/mcp",
                "headers": ["Authorization": "Bearer \(token)"],
            ] }
        )
    }

    /// 各クライアントの設定ファイルに floatingmacro エントリを追記する共通実装 (HTTP 版)。
    /// 既存設定を壊さないよう、ファイルが存在すれば JSON として読み込み、
    /// 指定された rootKey 配下に "floatingmacro" キーを上書きで挿入する。
    /// 親ディレクトリが存在しない場合は作成する (例: ~/.cursor/, ~/.gemini/)。
    private func registerHTTPMCP(
        clientName: String,
        relativePath: String,
        rootKey: String,
        entry: (String) -> [String: Any]
    ) {
        guard let token = loadToken() else {
            setStatus("Keychain からトークンを取得できませんでした。", isError: true)
            return
        }
        writeServerEntry(
            clientName: clientName,
            mode: "HTTP",
            relativePath: relativePath,
            rootKey: rootKey,
            serverName: "floatingmacro",
            entryDict: entry(token)
        )
    }

    /// stdio 版 (Node.js 製 MCP server 経由) で登録する共通実装。
    /// 登録名は HTTP 版と衝突しないよう "floatingmacro-stdio" を固定で使う。
    ///
    /// 仕組み:
    ///   1. アプリバンドル内 (Contents/Resources/npm/) に同梱された
    ///      Node.js 製 MCP server (npm パッケージ) を、ユーザー環境の
    ///      npx 経由でローカルファイルパスから起動する。
    ///   2. 認証トークンは args 経由で渡す (Keychain アクセス不要)。
    ///   3. npx の絶対パスは ~/.zshrc / ~/.bash_profile を読んだ login shell
    ///      経由で解決 (各 AI クライアントが PATH を継承しないため)。
    private func registerStdioMCP(
        clientName: String,
        relativePath: String,
        rootKey: String,
        entry: (_ shellPath: String, _ packageRef: String, _ token: String) -> [String: Any]
    ) {
        guard let token = loadToken() else {
            setStatus("Keychain からトークンを取得できませんでした。", isError: true)
            return
        }
        guard let bundleNpmPath = bundledNpmPackagePath() else {
            setStatus("バンドル内に同梱された npm パッケージが見つかりません (Contents/Resources/npm)。build-app.sh で再ビルドしてください。", isError: true)
            return
        }
        // ユーザーの login shell を経由して npx を起動する。
        // fnm / nvm / Homebrew のどのインストール方式でも、ログインシェルは
        // ~/.zshrc / ~/.bash_profile を読み込んで PATH を組み立てるので、
        // npx の絶対パスを設定ファイルに直書きする必要がない (fnm の session
        // 固有 shim パスは shell 終了で無効化されるので絶対パスは脆弱)。
        let loginShell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let packageRef = "file:\(bundleNpmPath)"
        writeServerEntry(
            clientName: clientName,
            mode: "CLI",
            relativePath: relativePath,
            rootKey: rootKey,
            serverName: "floatingmacro-stdio",
            entryDict: entry(loginShell, packageRef, token)
        )
    }

    /// アプリバンドルに同梱されている npm パッケージの絶対パス。
    /// build-app.sh が Contents/Resources/npm/ にコピーしている前提。
    /// 開発中 (swift run 直起動など) では nil を返し、呼び出し側がエラーを出す。
    private func bundledNpmPackagePath() -> String? {
        guard let res = Bundle.main.resourcePath else { return nil }
        let path = res + "/npm"
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir),
              isDir.boolValue else {
            return nil
        }
        // package.json があるかも軽く検証
        if !FileManager.default.fileExists(atPath: path + "/package.json") {
            return nil
        }
        return path
    }


    /// HTTP 版・stdio 版共通の書き込みロジック。
    /// 既存ファイルを JSON として読み込み、rootKey 配下に serverName エントリを上書きし、
    /// atomic 書き込みで保存する。親ディレクトリは必要なら自動作成。
    private func writeServerEntry(
        clientName: String,
        mode: String,
        relativePath: String,
        rootKey: String,
        serverName: String,
        entryDict: [String: Any]
    ) {
        let url = URL(fileURLWithPath: NSString(string: relativePath).expandingTildeInPath)
        var dict: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                let data = try Data(contentsOf: url)
                if !data.isEmpty,
                   let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    dict = parsed
                }
            } catch {
                setStatus("既存の \(relativePath) を読めませんでした: \(error.localizedDescription)", isError: true)
                return
            }
        }
        var servers = dict[rootKey] as? [String: Any] ?? [:]
        servers[serverName] = entryDict
        dict[rootKey] = servers
        do {
            let parent = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: parent, withIntermediateDirectories: true)
            let out = try JSONSerialization.data(
                withJSONObject: dict,
                options: [.prettyPrinted, .sortedKeys])
            try out.write(to: url, options: .atomic)
            setStatus("\(clientName) に \(mode) 版を登録しました (\(serverName))。\(clientName) を再起動すれば自動接続されます。", isError: false)
        } catch {
            setStatus("\(clientName) への書き込みに失敗しました: \(error.localizedDescription)", isError: true)
        }
    }

    /// 各クライアント用の登録ボタン 1 行。アイコン + クライアント名 + パス +
    /// 「CLI 登録」(主、青) + 「HTTP 登録」(補助、枠) の横並び。
    @ViewBuilder
    private func registerRow(
        icon: String,
        title: String,
        subtitle: String,
        httpAction: @escaping () -> Void,
        stdioAction: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout).fontWeight(.medium)
                Text(subtitle)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button(action: stdioAction) {
                Text("CLI 登録")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .help("fmcli (CLI ツール) を経由して接続。一般的・推奨。")
            Button(action: httpAction) {
                Text("HTTP 登録")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("HTTP プロトコルで直接接続。中級者向け。")
        }
    }

    // MARK: - stdio 版 (Node.js 製 npm パッケージ経由) 各クライアント別登録
    //
    // 各関数は (shellPath, packageRef, token) を受け取り、各クライアントの
    // 設定ファイル形式に合わせた JSON エントリを返す。
    //
    // shellPath はユーザーの $SHELL (通常 /bin/zsh)。login shell として
    // 起動して ~/.zshrc / ~/.bash_profile を読み込むことで、fnm / nvm /
    // Homebrew どれで Node.js を入れているユーザーでも PATH 上の npx を
    // 見つけられるようにしている。

    /// 共通の args を作る。`<shell> -lc "exec npx -y <pkg> --token <token>"`
    private func stdioArgs(packageRef: String, token: String) -> [String] {
        // single-quote で囲って token / pkg を shell metacharacter から守る。
        // token は 64-char hex で危険な文字は無いが念のため。
        // シングルクォートを文字列内で使う必要はない (token も pkg も含まない)。
        let inner = "exec npx -y '\(packageRef)' --token '\(token)'"
        return ["-lc", inner]
    }

    private func registerClaudeCodeStdio() {
        registerStdioMCP(
            clientName: "Claude Code",
            relativePath: "~/.claude.json",
            rootKey: "mcpServers",
            entry: { shell, pkg, token in [
                "command": shell,
                "args": self.stdioArgs(packageRef: pkg, token: token),
            ] }
        )
    }

    private func registerCursorStdio() {
        registerStdioMCP(
            clientName: "Cursor",
            relativePath: "~/.cursor/mcp.json",
            rootKey: "mcpServers",
            entry: { shell, pkg, token in [
                "command": shell,
                "args": self.stdioArgs(packageRef: pkg, token: token),
            ] }
        )
    }

    private func registerGeminiCLIStdio() {
        registerStdioMCP(
            clientName: "Gemini CLI",
            relativePath: "~/.gemini/settings.json",
            rootKey: "mcpServers",
            entry: { shell, pkg, token in [
                "command": shell,
                "args": self.stdioArgs(packageRef: pkg, token: token),
            ] }
        )
    }

    private func registerVSCodeStdio() {
        // VS Code は stdio の場合 type: "stdio" が必要 (HTTP 版は type: "http")。
        registerStdioMCP(
            clientName: "VS Code",
            relativePath: "~/Library/Application Support/Code/User/mcp.json",
            rootKey: "servers",
            entry: { shell, pkg, token in [
                "type": "stdio",
                "command": shell,
                "args": self.stdioArgs(packageRef: pkg, token: token),
            ] }
        )
    }

    private func registerWindsurfStdio() {
        registerStdioMCP(
            clientName: "Windsurf",
            relativePath: "~/.codeium/windsurf/mcp_config.json",
            rootKey: "mcpServers",
            entry: { shell, pkg, token in [
                "command": shell,
                "args": self.stdioArgs(packageRef: pkg, token: token),
            ] }
        )
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
