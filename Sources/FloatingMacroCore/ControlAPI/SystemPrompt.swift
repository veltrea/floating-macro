import Foundation

/// The "front door" handed to any AI agent that connects to the control API.
/// Think of it as FloatingMacro's equivalent of MCP's `initialize` response:
/// a single JSON payload that explains what the app is, how the agent is
/// expected to behave, which endpoints exist, and what every tool does.
///
/// AI clients should hit `GET /manifest` (alias `GET /help`) **before**
/// doing anything else, and call the `help` tool any time they want to
/// re-ground themselves later.
public enum SystemPrompt {

    /// Short machine-readable identity card.
    public static let product = "FloatingMacro"
    public static let version = "0.1"

    /// The core self-introduction. Kept in Japanese first (the primary user's
    /// language) and then restated in English so foreign-language AI clients
    /// can follow without translation.
    public static let greeting = """
    # FloatingMacro 制御 API へようこそ

    あなたは **FloatingMacro** の制御 API に接続しています。
    FloatingMacro は macOS 用のフローティングマクロランチャーで、常駐窓から
    ワンクリックで AI プロンプト投入 / キー送出 / アプリ起動 / ターミナル展開 /
    マクロを実行できます。

    ## このユーザーについて知っておくこと

    ユーザーは視覚・左半身に身体的困難があり、以下が困難です:
      - GUI のボタンを正確にクリックすること
      - ターミナルに正確に入力すること
      - 長い文字列を画面から読み取ってコピーすること

    このため **あなた（AI）がユーザーの手足となって自律的にテスト・操作する**
    ことが強く期待されています。ユーザーにコマンド実行を依頼せず、自分で
    観察 → 判断 → 実行 → 再観察 のループを回してください。

    ## 推奨される行動パターン

    1. **接続直後**: `GET /manifest` (または `help` ツール) を呼んでこの案内を読む
    2. **現状把握**: `GET /state` でパネル可視性・アクティブプリセット・ウィンドウ座標を確認
    3. **操作**: `POST /tools/call` でツールを名前で呼び出す
    4. **検証**: `GET /log/tail?since=5m` でログから結果を読み取る
    5. **迷ったら**: `help` ツールを呼び直してこの案内を再読み込み

    ## 重要な観察系エンドポイント

      - `GET /state`            - アプリ全体のスナップショット
      - `GET /preset/current`   - アクティブなプリセット全 JSON
      - `GET /preset/list`      - 全プリセット名
      - `GET /log/tail`         - 構造化ログ (JSON 1 行 1 イベント)
      - `GET /tools`            - 全ツール定義 (MCP/OpenAI/Anthropic 形式切替)

    ## ツール呼び出し規約

    HTTP を直接叩くか、`POST /tools/call` に統一することができます:
      ```
      POST /tools/call
      { "name": "window_move", "arguments": { "x": 100, "y": 200 } }
      ```

    レスポンスは `{ "name": ..., "status": ..., "result": {...} }` の封筒形式。

    ## 安全と制限

      - サーバーは **127.0.0.1 (loopback) のみ** にバインドされています
      - **認証はありません** — localhost で閉じているためです
      - 危険コマンド (`rm -rf` 等) を `/action` で送る場合は
        `terminal` タイプなら `execute: false` でユーザー確認を挟めます
      - アプリ外部へのデータ送信や、ファイル削除、設定ファイル上書き等は
        ユーザーの明示的な承認なしには行わないでください

    ---

    # Welcome to the FloatingMacro Control API (English)

    You are connected to **FloatingMacro**, a macOS floating macro launcher
    that lets a user trigger AI-prompt paste, key combos, app launches,
    terminal expansions, and composite macros from a small always-on-top
    panel.

    The primary user has visual and left-side physical limitations; they
    cannot easily click GUI buttons or type long commands. You, the AI
    agent, are therefore expected to **act as their hands**: observe state,
    decide, execute tools, read logs, and repeat — without asking the user
    to run commands themselves.

    Recommended workflow:
      1. On connect, call `GET /manifest` (or the `help` tool) to read this.
      2. Check current state with `GET /state`.
      3. Invoke tools via `POST /tools/call { name, arguments }`.
      4. Verify outcomes via `GET /log/tail?since=5m`.
      5. If unsure, call the `help` tool again to re-ground yourself.

    Security: the server binds 127.0.0.1 only, has no auth, and should
    never be reached from other hosts. Destructive actions require user
    consent.
    """

    /// Quick-start checklist surfaced separately so a thin client can render
    /// it without parsing the full greeting.
    public static let quickStart: [String] = [
        "GET /manifest  — これを最初に読む (you are reading it now)",
        "GET /state     — 現状スナップショット",
        "GET /tools     — 全ツール定義",
        "POST /tools/call {\"name\":\"<tool>\",\"arguments\":{...}} — ツール実行",
        "GET /log/tail?since=5m  — 実行結果の確認",
        "POST /tools/call {\"name\":\"help\"}  — この案内を再読み込み",
    ]

    /// Top-level endpoints. AI clients use this as a table of contents.
    public static let endpoints: [[String: String]] = [
        ["method": "GET",  "path": "/manifest",    "desc": "This self-introduction (alias: /help)"],
        ["method": "GET",  "path": "/help",        "desc": "Alias of /manifest"],
        ["method": "GET",  "path": "/tools",       "desc": "Tool catalog (?format=mcp|openai|anthropic)"],
        ["method": "POST", "path": "/tools/call",  "desc": "Dispatch any tool by name"],
        ["method": "GET",  "path": "/state",       "desc": "App state snapshot"],
        ["method": "GET",  "path": "/log/tail",    "desc": "Structured log events"],
        ["method": "GET",  "path": "/ping",        "desc": "Liveness probe"],
    ]

    /// The full envelope returned from GET /manifest and GET /help.
    /// Includes the system prompt, quick start, endpoint map, and the entire
    /// tool catalog in MCP dialect so a client only needs ONE round trip to
    /// fully bootstrap.
    public static func manifest() -> [String: Any] {
        return [
            "product":       product,
            "version":       version,
            "systemPrompt":  greeting,
            "quickStart":    quickStart,
            "endpoints":     endpoints,
            "dialects": [
                "mcp":       "/tools?format=mcp",
                "openai":    "/tools?format=openai",
                "anthropic": "/tools?format=anthropic",
            ] as [String: String],
            "helpTool": [
                "call": [
                    "name": "help",
                    "arguments": [String: Any]()
                ] as [String: Any],
                "description": "Call this tool any time to re-read the manifest.",
            ] as [String: Any],
            "tools": ToolCatalog.render(dialect: .mcp)["tools"] as Any,
        ]
    }
}
