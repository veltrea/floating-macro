import Foundation

public final class ConfigWriter {
    private let encoder: JSONEncoder
    private let baseURL: URL

    public init(baseURL: URL? = nil) {
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.baseURL = baseURL ?? ConfigLoader.defaultBaseURL
    }

    public func saveAppConfig(_ config: AppConfig) throws {
        let url = baseURL.appendingPathComponent("config.json")
        let data = try encoder.encode(config)
        try data.write(to: url, options: .atomic)
    }

    public func savePreset(_ preset: Preset) throws {
        let url = baseURL.appendingPathComponent("presets/\(preset.name).json")
        let data = try encoder.encode(preset)
        try data.write(to: url, options: .atomic)
    }

    // MARK: - Default preset factory

    // settings.json を安全にマージ更新する Python ワンライナーの雛形。
    // キーと値を渡すと既存設定を壊さずに追記・上書きする。
    private static func settingsPython(
        _ assignments: String,
        message: String
    ) -> String {
        """
        python3 -c "
        import json, os, sys
        p = os.path.expanduser('~/.claude/settings.json')
        os.makedirs(os.path.dirname(p), exist_ok=True)
        try:
            with open(p) as f: d = json.load(f)
        except: d = {}
        \(assignments)
        with open(p, 'w') as f: json.dump(d, f, indent=2, ensure_ascii=False)
        print('\(message)')
        "
        """
    }

    static func makeDefaultPreset() -> Preset {
        // ── テキスト貼り付けアクション (Claude Code のプロンプトに投入) ──
        func txt(_ content: String) -> Action {
            .text(content: content, pasteDelayMs: 120, restoreClipboard: true)
        }
        // ── ターミナル実行アクション ──
        func term(_ command: String) -> Action {
            .terminal(app: "Terminal", command: command,
                      newWindow: false, execute: true, profile: nil)
        }

        return Preset(
            name: "default",
            displayName: "Claude Code",
            groups: [
                // ━━━ セッション中に使うコマンド ━━━
                ButtonGroup(
                    id: "group-session",
                    label: "Claude Code",
                    icon: "com.anthropic.claudefordesktop",
                    buttons: [
                        ButtonDefinition(
                            id: "btn-ultrathink",
                            label: "ultrathink",
                            iconText: "🧠",
                            tooltip: "そのターンだけ高品質な思考を発動（effort が high 未満の時に有効）",
                            action: txt("ultrathink で次のタスクに取り組んでください。")
                        ),
                        ButtonDefinition(
                            id: "btn-stop-loop",
                            label: "止まって",
                            iconText: "⏸",
                            tooltip: "ループを中断して状況報告させる",
                            action: txt("ループっぽいので一旦止まって、現状と次のアクションを報告してください。")
                        ),
                        ButtonDefinition(
                            id: "btn-research-first",
                            label: "調査優先",
                            iconText: "🔍",
                            tooltip: "推測せずファイルを読んでから作業させる（CLAUDE.md ルール相当）",
                            action: txt("コードを変更する前に、必ず対象ファイルを読んで内容を把握してください。推測で作業せず、調査・確認を最優先にしてください。")
                        ),
                        ButtonDefinition(
                            id: "btn-test-after",
                            label: "テスト実行",
                            iconText: "✅",
                            tooltip: "変更後にテストを実行して動作確認させる",
                            action: txt("変更が完了したらテストを実行して、動作確認の結果を報告してください。")
                        ),
                    ]
                ),

                // ━━━ /effort 切り替え ━━━
                ButtonGroup(
                    id: "group-effort",
                    label: "Effort",
                    icon: "com.anthropic.claudefordesktop",
                    buttons: [
                        ButtonDefinition(
                            id: "btn-effort-high",
                            label: "high",
                            iconText: "⬆",
                            backgroundColor: "#2D7D46",
                            tooltip: "品質重視の日常使い（推奨）",
                            action: txt("/effort high")
                        ),
                        ButtonDefinition(
                            id: "btn-effort-max",
                            label: "max",
                            iconText: "🔥",
                            backgroundColor: "#C23B22",
                            tooltip: "全力思考。難しいデバッグや設計に（トークン消費大）",
                            action: txt("/effort max")
                        ),
                        ButtonDefinition(
                            id: "btn-effort-low",
                            label: "low",
                            iconText: "⚡",
                            backgroundColor: "#555555",
                            tooltip: "ファイル名変更・コメント追加など軽作業を高速処理",
                            action: txt("/effort low")
                        ),
                        ButtonDefinition(
                            id: "btn-effort-auto",
                            label: "auto",
                            iconText: "🤖",
                            backgroundColor: "#3B6BA5",
                            tooltip: "思考量をモデルにお任せ（API課金勢向け）",
                            action: txt("/effort auto")
                        ),
                    ]
                ),

                // ━━━ settings.json の恒久設定 (ターミナルで実行) ━━━
                ButtonGroup(
                    id: "group-settings",
                    label: "設定",
                    icon: "sf:gearshape",
                    buttons: [
                        ButtonDefinition(
                            id: "btn-cfg-quality",
                            label: "品質重視設定",
                            iconText: "🛡",
                            backgroundColor: "#2D7D46",
                            tooltip: "effortLevel=high + Adaptive Thinking無効化 + 思考サマリー表示",
                            action: term(settingsPython(
                                """
                                d['effortLevel'] = 'high'
                                d.setdefault('env', {})['CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING'] = '1'
                                d['showThinkingSummaries'] = True
                                """,
                                message: "設定完了: effortLevel=high, Adaptive Thinking無効化, 思考サマリー表示"
                            ))
                        ),
                        ButtonDefinition(
                            id: "btn-cfg-balanced",
                            label: "バランス設定",
                            iconText: "⚖",
                            backgroundColor: "#3B6BA5",
                            tooltip: "effortLevel=auto + Adaptive Thinking無効化（速度とコストのバランス）",
                            action: term(settingsPython(
                                """
                                d['effortLevel'] = 'auto'
                                d.setdefault('env', {})['CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING'] = '1'
                                d['showThinkingSummaries'] = True
                                """,
                                message: "設定完了: effortLevel=auto, Adaptive Thinking無効化, 思考サマリー表示"
                            ))
                        ),
                        ButtonDefinition(
                            id: "btn-cfg-disable-adaptive",
                            label: "Adaptive Thinking 無効化",
                            iconText: "🚫",
                            backgroundColor: "#8B4513",
                            tooltip: "推論ゼロバグの回避。Boris Cherny氏推奨の最重要ワークアラウンド",
                            action: term(settingsPython(
                                """
                                d.setdefault('env', {})['CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING'] = '1'
                                """,
                                message: "設定完了: CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING=1"
                            ))
                        ),
                        ButtonDefinition(
                            id: "btn-cfg-show-thinking",
                            label: "思考サマリー表示",
                            iconText: "💭",
                            tooltip: "Claudeの思考過程サマリーをUI上に再表示する",
                            action: term(settingsPython(
                                """
                                d['showThinkingSummaries'] = True
                                """,
                                message: "設定完了: showThinkingSummaries=true"
                            ))
                        ),
                    ]
                ),

                // ━━━ バージョン管理 ━━━
                ButtonGroup(
                    id: "group-version",
                    label: "バージョン",
                    icon: "sf:arrow.triangle.2.circlepath",
                    collapsed: true,
                    buttons: [
                        ButtonDefinition(
                            id: "btn-downgrade",
                            label: "v2.1.98 にダウングレード",
                            iconText: "⬇",
                            backgroundColor: "#8B0000",
                            tooltip: "隠しトークン問題 (v2.1.100以降) を回避する最後の安定版",
                            action: term("npm uninstall -g @anthropic-ai/claude-code && npm install -g @anthropic-ai/claude-code@2.1.98 && echo 'ダウングレード完了: v2.1.98'")
                        ),
                        ButtonDefinition(
                            id: "btn-upgrade-latest",
                            label: "最新版に更新",
                            iconText: "⬆",
                            tooltip: "Claude Code を最新版にアップデート",
                            action: term("npm install -g @anthropic-ai/claude-code@latest && claude --version")
                        ),
                        ButtonDefinition(
                            id: "btn-check-version",
                            label: "バージョン確認",
                            iconText: "📋",
                            tooltip: "現在の Claude Code バージョンを表示",
                            action: term("claude --version")
                        ),
                    ]
                ),
            ]
        )
    }

    public func writeDefaultConfigIfNeeded() throws {
        let fm = FileManager.default
        let loader = ConfigLoader(baseURL: baseURL)
        try loader.ensureDirectories()

        let configURL = baseURL.appendingPathComponent("config.json")
        if !fm.fileExists(atPath: configURL.path) {
            try saveAppConfig(AppConfig())
        }

        let defaultPresetURL = baseURL.appendingPathComponent("presets/default.json")
        if !fm.fileExists(atPath: defaultPresetURL.path) {
            let preset = Self.makeDefaultPreset()
            try savePreset(preset)
        }
    }
}
