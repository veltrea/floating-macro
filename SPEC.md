# FloatingMacro — 仕様書

最終更新: 2026-04-16

---

## 1. 概要

**FloatingMacro** は macOS 用のフローティング式マクロランチャー。画面上に常駐する小さなウィンドウからワンクリックで以下を実行できる:

- キーボードショートカット送出
- 任意テキストの貼り付け(クリップボード経由)
- アプリ / ファイル / URL 起動
- ターミナル起動 + コマンド自動入力
- 上記を組み合わせた **マクロ** (順次実行)

本プロジェクトは Windows 用の類似ソフト (FloatingButton by Trifolium Studio) をクリーンルーム方式で参考にしつつ、Mac ネイティブで再設計する。元ソフトのコードは一切参照しない。観察可能な挙動とスクリーンショットのみを参考にする。

### AI オリエンテッドな設計 — AI エージェントを第一級ユーザーとして扱う

FloatingMacro は **AI エージェントがアプリの観察・設定・操作をエンドツーエンドで行える** ことを最初からの設計要件にしている。既存アプリに AI を後付けするのではなく、**AI を第一級のユーザーとして想定するとどんな設計になるか** を小さなユーティリティの中で試すプロジェクト:

- ログは JSON 1 行 1 イベント形式 (AI がパイプで読める)
- HTTP 制御 API を内蔵 (localhost のみ、外部依存ゼロ)
- API は ACP / MCP / A2A 相当の標準プロトコルと互換
- CLI (`fmcli`) は AI が bash から直接叩ける

---

## 2. ターゲットユーザーと主要ユースケース

### 想定ユーザー
- ペンタブ / トラックパッド中心でキーボードショートカットを頻繁に出しにくいユーザー
- AI エージェント (Claude Code / Claude CLI 等) にプロンプトを素早く流し込みたい開発者
- 複数のターミナル + ディレクトリ移動 + コマンド起動を一発でやりたい開発者
- **AI エージェントをアプリ操作の主役にする使い方 (AI-first workflow) を試したい開発者**

### 主要ユースケース
1. **AI プロンプト投入** — "ultrathink で考えて" 等の定型プロンプトをボタン一発で貼付
2. **開発環境一撃展開** — 1 ボタンで 4〜5 ターミナルを開き、各ディレクトリに `cd` して `claude` を起動
3. **作業シーン切替** — プリセットを切り替えて "執筆モード" / "開発モード" / "デバッグモード" のボタン群を差し替え
4. **アプリランチャー** — よく使うアプリ / フォルダ / URL をグループ化して配置 (アプリアイコン自動取得)
5. **AI からの遠隔操作** — Claude / Gemini が制御 API 経由でボタンを追加・編集、ウィンドウを動かし、アクションを実行

---

## 3. 非目標 (Non-goals)

- Windows / Linux 対応 (Mac 専用)
- マルチモニタの詳細位置記憶 (v2 以降で検討)
- クラウド同期 (ローカル設定のみ)
- OCR / 画像認識ベースの自動化
- スクリプト言語実行エンジン (単発シェルコマンドは可、JS/Python VM は持たない)
- 既存マクロツール (Keyboard Maestro, BetterTouchTool) の完全代替

---

## 4. プラットフォーム / 技術スタック

| 項目 | 選定 |
|---|---|
| 言語 | Swift 5.9 |
| UI | SwiftUI + AppKit (NSPanel) のハイブリッド |
| 最低 OS | macOS 13 (Ventura) |
| ビルド | Swift Package Manager |
| バイナリ | universal (arm64 + x86_64) |
| 依存 | 標準フレームワークのみ (AppKit / SwiftUI / Carbon / ApplicationServices / Network.framework) |

### Swift 5.9 を選ぶ理由
Swift 6 の strict concurrency を MVP で抱え込むと UI と非同期処理の衝突対応に時間を取られる。6 への移行は v2 以降に後回し。

### 外部依存を入れない理由
常駐ツールは起動速度 / セキュリティ / メンテ容易性が重要。標準フレームワークだけで実装可能なので最小構成を維持する。HTTP サーバーも `Network.framework` の `NWListener` で自前実装する (swift-nio / Vapor は導入しない)。

---

## 5. プロジェクト構成

```
floatingmacro/
├── Package.swift
├── SPEC.md                       # この文書
├── README.md                     # (後日)
├── Sources/
│   ├── FloatingMacroCore/        # 純粋ロジック (UI / AppKit 依存は Platform/ のみ)
│   │   ├── Config/
│   │   │   ├── ButtonDefinition.swift
│   │   │   ├── Preset.swift                  # Preset / ButtonGroup / WindowConfig / ControlAPIConfig / AppConfig
│   │   │   ├── ConfigLoader.swift
│   │   │   ├── ConfigWriter.swift
│   │   │   └── PresetEditor.swift            # preset/group/button の CRUD 純粋ロジック
│   │   ├── Actions/
│   │   │   ├── Action.swift
│   │   │   ├── KeyCombo.swift
│   │   │   ├── KeyActionExecutor.swift
│   │   │   ├── TextActionExecutor.swift
│   │   │   ├── LaunchActionExecutor.swift
│   │   │   ├── TerminalActionExecutor.swift
│   │   │   └── ActionError.swift
│   │   ├── Macro/
│   │   │   └── MacroRunner.swift
│   │   ├── Platform/
│   │   │   ├── Clipboard.swift
│   │   │   ├── AppleScriptRunner.swift
│   │   │   ├── WorkspaceLauncher.swift
│   │   │   └── EventSynthesizer.swift
│   │   ├── Permissions/
│   │   │   ├── AccessibilityChecker.swift
│   │   │   └── AutomationChecker.swift
│   │   ├── Icons/
│   │   │   └── IconResolver.swift            # パス解決ロジック (AppKit 非依存)
│   │   ├── Logging/
│   │   │   ├── LogLevel.swift
│   │   │   ├── LogEvent.swift
│   │   │   ├── Logger.swift                  # FMLogger / NullLogger / InMemoryLogger / ComposedLogger / LoggerContext
│   │   │   ├── FileLogWriter.swift
│   │   │   └── ConsoleLogWriter.swift
│   │   └── ControlAPI/
│   │       ├── HTTPMessage.swift             # HTTPRequest / HTTPResponse
│   │       ├── HTTPParser.swift              # JSONでない生の HTTP/1.1 パーサ
│   │       ├── ControlServer.swift           # NWListener ラッパ
│   │       ├── SystemPrompt.swift            # AI への自己紹介プロンプト + manifest()
│   │       ├── ToolCatalog.swift             # 全ツール定義 + MCP/OpenAI/Anthropic 3形式変換
│   │       ├── OpenAPIGenerator.swift        # OpenAPI 3.1 JSON 自動生成
│   │       ├── AgentCard.swift               # A2A Agent Card 出力
│   │       └── MCPAdapter.swift              # JSON-RPC 2.0 over HTTP (Anthropic MCP)
│   ├── FloatingMacroCLI/
│   │   └── main.swift                        # `fmcli` - CLI テストハーネス + ログ閲覧
│   └── FloatingMacroApp/
│       ├── App.swift                         # AppDelegate
│       ├── FloatingPanel.swift               # NSPanel サブクラス
│       ├── ButtonView.swift                  # SwiftUI ボタン描画 + アイコン
│       ├── PresetManager.swift               # ObservableObject + 編集 API
│       ├── IconLoader.swift                  # NSImage キャッシュ + NSWorkspace アイコン取得
│       ├── Settings/
│       │   ├── SettingsView.swift            # SwiftUI 設定ウィンドウのルート
│       │   ├── SettingsDetail.swift          # ボタン属性編集フォーム
│       │   └── SettingsWindowController.swift
│       └── ControlAPI/
│           └── ControlHandlers.swift         # HTTP エンドポイント実装 (REST + /tools/call + /mcp)
├── Tests/
│   └── FloatingMacroCoreTests/               # 226 件 (2026-04-16 時点)
├── scripts/
│   ├── fmcli_smoke.sh                        # fmcli の自動スモーク (31 項目)
│   └── control_api_smoke.sh                  # 実 GUI プロセス + curl での E2E (78 項目)
└── docs/
    ├── manual_test.md                        # 人による目視確認リスト
    └── AI_PROTOCOL.md                        # AI エージェント向け接続マニュアル
```

**設計原則**:
- `FloatingMacroCore` は UI / AppKit に依存しない。`import AppKit` は `Platform/` 以下に限定
- すべての Executor は DI 可能な static singleton (`synthesizer`, `clipboard`, `launcher`, `scriptRunner`) を持ち、テスト時にモック差し替え可能
- `FloatingMacroCLI` から全ロジックをテストできる
- ユニットテスト + `fmcli` スモーク + 制御 API スモーク + 手動テストの 4 層テスト

---

## 6. 設定ファイル仕様

### 6.1 配置場所

```
~/Library/Application Support/FloatingMacro/
├── config.json        # プリセット一覧と選択状態 + ウィンドウ設定 + controlAPI 設定
├── presets/
│   ├── default.json
│   ├── dev.json
│   └── writing.json
└── logs/
    ├── floatingmacro.log
    └── floatingmacro.log.old   # 10MB 超でローテーション
```

環境変数 `FLOATINGMACRO_CONFIG_DIR` で上書き可能 (テスト / 外部ディスク運用向け)。

### 6.2 `config.json` スキーマ

```json
{
  "version": 1,
  "activePreset": "default",
  "window": {
    "x": 100,
    "y": 100,
    "width": 200,
    "height": 300,
    "orientation": "vertical",
    "alwaysOnTop": true,
    "hideAfterAction": false,
    "opacity": 1.0
  },
  "controlAPI": {
    "enabled": false,
    "port": 17430
  }
}
```

後方互換性のため、存在しないフィールドはすべて既定値にフォールバックする (`decodeIfPresent` ベース)。

### 6.3 プリセットファイル (`presets/*.json`) スキーマ

```json
{
  "version": 1,
  "name": "default",
  "displayName": "デフォルト",
  "groups": [
    {
      "id": "group-1",
      "label": "AI",
      "collapsed": false,
      "buttons": [
        {
          "id": "btn-ultrathink",
          "label": "ultrathink",
          "icon": null,
          "iconText": "🧠",
          "backgroundColor": "#FF6B00",
          "width": 140,
          "height": 36,
          "action": {
            "type": "text",
            "content": "ultrathink で次のタスクに取り組んでください。"
          }
        }
      ]
    }
  ]
}
```

### 6.4 ボタン (`buttons[]`) フィールド

| フィールド | 型 | 必須 | 説明 |
|---|---|---|---|
| `id` | string | ◯ | プリセット内ユニーク |
| `label` | string | ◯ | 表示文字列 |
| `icon` | string? | × | 画像ファイルパス (PNG/ICO/ICNS/JPEG) OR アプリ bundle id OR `.app` 絶対パス |
| `iconText` | string? | × | 絵文字 / 1〜2 文字の表示アイコン |
| `backgroundColor` | string? | × | `#RRGGBB` または `#RRGGBBAA` hex |
| `width` | number? | × | 明示幅 (points)。null で自動 |
| `height` | number? | × | 明示高さ。null で自動 |
| `action` | Action | ◯ | クリック時の動作 |

#### icon の自動解決
`icon` が設定されていない場合でも、`action.type == "launch"` で `target` がアプリパス / bundle id なら、**その target を icon として自動推論** し `NSWorkspace.icon(forFile:)` でアプリアイコンを取得する。結果はプロセス内キャッシュに保存。

### 6.5 グループ (`groups[]`) フィールド

| フィールド | 型 | 必須 | 説明 |
|---|---|---|---|
| `id` | string | ◯ | プリセット内ユニーク |
| `label` | string | ◯ | グループ見出し |
| `collapsed` | boolean | × | 折りたたみ状態 (既定 false) |
| `buttons` | Button[] | ◯ | ボタン配列 |

---

## 7. アクション型仕様

全アクションは JSON の `type` フィールドで判別する tagged union。Swift 側では `enum Action` として表現。(変更なし — §7.1〜7.6 の詳細は元仕様に準拠)

### 7.1 `key` — キーコンボ送出

```json
{ "type": "key", "combo": "cmd+v" }
```

`CGEventCreateKeyboardEvent` で keyDown + keyUp を合成、`CGEventPost(.cghidEventTap, event)` で送出。

### 7.2 `text` — テキスト注入

```json
{
  "type": "text",
  "content": "ultrathink で考えて",
  "pasteDelayMs": 120,
  "restoreClipboard": true
}
```

実行フロー:
1. クリップボードの全アイテム (全 UTI 型) を保存
2. `defer` で復元を保証 (synth 失敗時も元に戻る — 機密漏洩防止)
3. text を setString
4. `pasteDelayMs` 待機
5. Cmd+V を CGEvent 合成で送出

### 7.3 `launch` — アプリ / ファイル / URL 起動

```json
{ "type": "launch", "target": "..." }
```

target の解釈 (優先順):
1. `shell:` prefix → `/bin/sh -c` で実行
2. `://` 含む → `NSWorkspace.open(URL)`
3. `com.xxx.xxx` 形式 → bundle identifier 経由
4. 絶対パス or `~/` → ファイル/フォルダ/アプリ
5. それ以外 → `launchTargetNotFound`

### 7.4 `terminal` — ターミナル起動 + コマンド投入

Terminal.app / iTerm2 は AppleScript、それ以外は NSWorkspace + クリップボード経由貼付。

### 7.5 `delay` — 待機

```json
{ "type": "delay", "ms": 500 }
```

### 7.6 `macro` — アクション配列の順次実行

ネストは禁止 (パーサで reject)。`stopOnError` で中断/続行を制御。

---

## 8. ウィンドウ仕様

### 8.1 基本性質

| 項目 | 仕様 |
|---|---|
| ウィンドウクラス | `NSPanel` のサブクラス |
| style mask | `.nonactivatingPanel`, `.titled`, `.closable`, `.resizable`, `.fullSizeContentView` |
| level | `.floating` |
| collection behavior | `.canJoinAllSpaces`, `.stationary`, `.fullScreenAuxiliary` |
| フォーカス奪取 | 奪わない (canBecomeKey/canBecomeMain = false) |
| ドラッグ移動 | 空白部分を長押しで自由移動 |
| 常時最前面 | 既定 ON |
| 透明度 | 既定 1.0、0.25〜1.0 で可変 (menuで 4段階、API で任意値) |
| 位置/サイズの永続化 | `applicationWillTerminate` で `config.json` に書き戻し |

### 8.2 レイアウト

- **方向**: 縦積み (v0.1)、横並びは将来
- **グループ化**: グループごとに小さなヘッダ + ボタン列
- **折りたたみ**: グループヘッダクリックで折りたたみ
- **幅/高さ**: 既定 200×300、ユーザーがドラッグでリサイズ可能、API で変更可能

### 8.3 メニューバー

- `NSStatusItem` でメニューバーに常駐
- メニュー項目:
  - 表示 / 非表示
  - プリセット切替 (サブメニュー)
  - **透明度** (25% / 50% / 75% / 100% サブメニュー、現在値に ✓)
  - **ボタン編集...** (`Cmd+E` で設定ウィンドウ)
  - 設定フォルダを開く
  - 再読み込み
  - 終了
- Dock アイコンは表示しない (`LSUIElement = YES`)

---

## 9. 権限要件

### 9.1 Accessibility 権限
`CGEventPost` によるキーイベント合成に必要。`AXIsProcessTrustedWithOptions` で常時チェック。未許可時は `AccessibilityChecker.openSystemPreferences()` で設定画面へ誘導。

### 9.2 Automation 権限
Terminal / iTerm への AppleScript 送信に必要。`AutomationChecker.check(bundleIdentifier:)` で `.authorized / .denied / .notDetermined / .targetUnavailable` の 4 状態を取得可能。

### 9.3 コード署名
- MVP: 自己署名で動作確認できる状態
- v2: Developer ID 署名 + notarization

---

## 10. ロギング

### 10.1 設計目的

**AI 観察性の基盤**。ログは「ユーザーが目で確認する」ではなく「**AI が tail して自動判定する**」ことを第一目的にする。

- 形式: JSON 1 行 1 イベント (JSONL / ndjson 準拠)
- 場所: `<ConfigDir>/logs/floatingmacro.log`
- ローテーション: 10MB 超で `.old` にリネーム
- `fmcli log tail --json` で AI がパイプで読める

### 10.2 LogEvent スキーマ

```json
{
  "timestamp": "2026-04-16T00:30:00.123Z",
  "level": "info",
  "category": "MacroRunner",
  "message": "Starting macro",
  "metadata": {
    "count": "3",
    "stopOnError": "true"
  }
}
```

タイムスタンプは ISO 8601 + fractional seconds (UTC)。キーは sorted output で stable (diff 可能)。`metadata` は空の場合 `null`。

### 10.3 LogLevel

`debug` < `info` < `warn` < `error` (Comparable で severity 順)。各 Logger は `minimumLevel` を持ち、それ未満は drop。

### 10.4 Logger 種別

| 実装 | 用途 |
|---|---|
| `NullLogger` | デフォルト、本番で明示的に他を設定するまで使う静かな実装 |
| `InMemoryLogger` | テスト用、`contains(category:messageContains:)` で assertion |
| `FileLogWriter` | 本番、DispatchQueue でシリアル化 + ローテーション + `flush()` |
| `ConsoleLogWriter` | fmcli 用、stderr に人間可読テキスト |
| `ComposedLogger` | 複数 Logger への fan-out (file + console) |

グローバル差し替え: `LoggerContext.shared = ...`。テストでは setUp/tearDown で InMemoryLogger を差し込む。

### 10.5 ログ出力箇所

- `MacroRunner`: マクロ開始 / 完了 / エラー / 中断
- 各 `*ActionExecutor`: dispatch / 失敗ごとにエラー詳細
- `ConfigLoader`: 読み込み成功 / 失敗
- `ControlServer`: 接続 / バインド失敗
- `ControlAPI` 各ハンドラ: 失敗時のみ

### 10.6 環境変数

- `FLOATINGMACRO_CONFIG_DIR` — 設定/ログディレクトリを上書き
- `FLOATINGMACRO_LOG_LEVEL` — `debug|info|warn|error` (CLI `--log-level` と同等)

---

## 11. CLI (`fmcli`)

UI を起動せずロジックを検証するためのコマンドラインツール。

```
fmcli action key "cmd+shift+4"
fmcli action text "こんにちは世界"
fmcli action launch "/Applications/Slack.app"
fmcli action terminal --app iTerm --command "ls -la"
fmcli preset list
fmcli preset run default btn-ultrathink
fmcli permissions check
fmcli config path
fmcli config init
fmcli log path
fmcli log tail [--level LEVEL] [--since DUR] [--limit N] [--json]
fmcli --log-level debug action key "cmd+v"
```

**目的**:
- UI 依存なしでアクション単体のテスト
- **AI が bash 経由で全機能を叩ける最小経路**
- CI での smoke test
- ログのクエリによる事後分析 (`--since 5m --level warn --json | jq`)

---

## 12. HTTP 制御 API

### 12.1 設計目的

**AI (Claude / Gemini / 他) がアプリの内部状態を観察し、全機能を実行できる** こと。MCP / A2A / ACP 相当のエージェント間プロトコルとの互換性を保ちつつ、外部依存ゼロで実装する。

### 12.2 基本性質

| 項目 | 仕様 |
|---|---|
| 実装 | `Network.framework` の `NWListener` (外部依存なし) |
| バインド | `127.0.0.1` (loopback) のみ、`requiredInterfaceType: .loopback` |
| 認証 | なし (localhost 限定のため) |
| プロトコル | HTTP/1.1、Keep-Alive なし (1 接続 1 リクエスト) |
| 形式 | JSON in / JSON out (UTF-8) |
| ポート | 既定 17430、重複時は +1 ずつ最大 10 回 fallback |
| 起動 | `controlAPI.enabled` 設定時のみ、別スレッドで **1〜2 秒以内**に bind |

### 12.3 起動の指針 (MCP サーバー化の罠回避)

既存 MCP サーバー実装の経験則から次を厳守する:
- メインスレッドをブロックしない (DispatchQueue.global で起動)
- 初期化は 1〜2 秒以内に完了 (`start(timeout: 2.0)`)
- 失敗してもアプリ本体は通常起動を継続する (ログのみ残す)
- ウィンドウの新規生成は行わない (既存アプリに "貼る" モデル)

### 12.4 エンドポイント一覧

#### 自己紹介 / ディスカバリ
| Method | Path | 目的 |
|---|---|---|
| GET | `/manifest` | AI が最初に読む自己紹介 + 全ツール一覧 + systemPrompt |
| GET | `/help` | `/manifest` のエイリアス |
| GET | `/ping` | 生存確認 |
| GET | `/openapi.json` | **OpenAPI 3.1** ドキュメント自動生成 (ACP / REST 互換) |
| GET | `/.well-known/agent.json` | **A2A Agent Card** (Google 互換) |
| GET | `/tools?format=mcp\|openai\|anthropic` | ツール定義を 3 方言で提供 |

#### 統一ディスパッチ
| Method | Path | 目的 |
|---|---|---|
| POST | `/tools/call` | `{name, arguments}` で任意ツールを呼び出し |
| POST | `/mcp` | **JSON-RPC 2.0 / MCP HTTP transport** (Anthropic 互換) |

#### ウィンドウ操作
- `POST /window/show | hide | toggle`
- `POST /window/opacity` — `{value: 0.25..1.0}`
- `POST /window/move` — `{x, y}`
- `POST /window/resize` — `{width, height}`

#### 観察系
- `GET /state` — パネル可視性 + アクティブプリセット + ウィンドウ座標 + エラー
- `GET /log/tail?level=&since=&limit=` — JSON 1 行 1 イベント
- `GET /icon/for-app?bundleId= | path=` — base64 PNG

#### プリセット / グループ / ボタンの CRUD
- `GET /preset/list`, `GET /preset/current`
- `POST /preset/switch | reload | create | rename | delete`
- `POST /group/add | update | delete`
- `POST /button/add | update | delete | reorder | move`

#### アクション実行
- `POST /action` — Action JSON を送って即実行 (202 Accepted)

### 12.5 MCP JSON-RPC 対応 (`/mcp`)

`POST /mcp` に JSON-RPC 2.0 envelope で以下のメソッドを送れる:
- `initialize` — serverInfo + capabilities + protocolVersion を返す
- `tools/list` — 全ツール定義
- `tools/call` — REST ハンドラにディスパッチ、結果を `content[].text` に JSON 文字列で包んで返す
- `ping` — 生存確認

エラーは標準 JSON-RPC コード: `-32700/-32600/-32601/-32602/-32603` + アプリ固有 `-32000`。

### 12.6 セキュリティ

- **loopback のみ** — 他ホストから到達不可
- 危険な操作 (`/action` の `terminal` など) はユーザーのコンテキストに依存する点を呼び出し元が配慮
- `restoreClipboard: true` のテキスト貼付は失敗時もクリップボードを復元 (パスワード等の流出防止)

---

## 13. アイコンシステム

### 13.1 `IconResolver` (Core)

文字列参照 (`icon` フィールド) を 3 種類のケースに解決する純粋ロジック:

| ケース | 判定 | 結果 |
|---|---|---|
| 画像ファイル | `.png / .jpg / .icns / .ico / ...` 拡張子 + 存在 | `.imageFile(URL)` |
| `.app` バンドル | `.app` 拡張子 + 存在 | `.appBundle(URL)` |
| Bundle ID | `com.xxx.yyy` パターン、スラッシュなし | `.bundleIdentifier(String)` |

### 13.2 `IconLoader` (App)

`IconResolver` の結果を `NSImage` に変換:
- `.imageFile` → `NSImage(contentsOf: URL)`
- `.appBundle` → `NSWorkspace.icon(forFile:)`
- `.bundleIdentifier` → `NSWorkspace.urlForApplication(withBundleIdentifier:)` + icon

プロセス内キャッシュ付き。API 経由 (`/icon/for-app`) で base64 PNG として外部からも取得可能。

### 13.3 ボタン描画時の優先順位

`MacroButtonView` は次の順序でアイコンを表示:
1. 明示設定された `icon`
2. `action.type == "launch"` の `target` から自動推論
3. `iconText` (絵文字)
4. なし

### 13.4 `icon` フィールドのプレフィックス仕様

| プレフィックス | 例 | 解決方法 |
|---|---|---|
| `sf:` | `sf:star.fill` | SF Symbol (Apple 提供、`NSImage(systemSymbolName:)`) |
| `lucide:` | `lucide:folder` | **同梱 Lucide SVG** (`Bundle.module`、1695 アイコン、ISC) |
| `com.xxx.yyy` | `com.apple.Safari` | macOS アプリ bundle identifier (`NSWorkspace`) |
| `/` や `~/` 始まり | `/Applications/Slack.app` | 絶対パスまたは tilde 展開 |

### 13.5 Lucide 同梱

`Sources/FloatingMacroApp/Resources/lucide/` に **Lucide 1695 SVG アイコン**
を同梱（**ISC ライセンス**、`LICENSE` ファイルも同ディレクトリに配置）。

- 合計 約 0.65 MB
- macOS 13+ の `NSImage(contentsOf:)` は SVG をネイティブ解釈する (外部ライブラリ不要)
- クレジット: `DESIGN.md` §10 参照

---

## 14. GUI 設定画面

### 14.1 呼び出し

メニューバー → 「ボタン編集...」または `Cmd+E`。`SettingsWindowController.shared.show(presetManager:)` で単一の NSWindow をシェア。

### 14.2 構成

2 カラムの HSplitView:

**左カラム** (`SettingsSidebar`):
- プリセット選択 Picker + 追加 (+) / 削除 (-)
- グループ・ボタンツリー (フォルダアイコン + 選択ハイライト)
- グループ追加テキストフィールド
- ボタン追加ボタン (選択中グループに追加)

**右カラム** (`SettingsDetail`):
- 選択ボタンの詳細編集フォーム:
  - ラベル
  - iconText (絵文字)
  - icon 画像 / アプリ (`NSOpenPanel` で参照、クリア)
  - 背景色 (SwiftUI `ColorPicker` + hex 文字列の双方向バインド)
  - 幅 / 高さ (auto or 数値)
  - アクション (segmented picker: text/key/launch/terminal)
- 削除ボタン / 保存ボタン (Enter で確定)

### 14.3 一貫性保証

GUI 編集は **内部的に PresetManager の CRUD メソッドを呼び出す** ため、HTTP API / fmcli からの編集と完全に同じ経路を通る。

---

## 15. テスタビリティ

### 15.1 4 層テスト構成

| 層 | 対象 | 件数 (2026-04-16) | 実行コマンド |
|---|---|---|---|
| ユニット | `FloatingMacroCore` の全ロジック | **226** | `swift test` |
| fmcli スモーク | CLI の権限不要 surface | **31** | `bash scripts/fmcli_smoke.sh` |
| 制御 API スモーク | 実 GUI プロセス + curl E2E | **78** | `bash scripts/control_api_smoke.sh` |
| 手動 | GUI の視覚確認 | — | `docs/manual_test.md` |

### 15.2 DI パターン

すべての外部依存 (`EventSynthesizer` / `Clipboard` / `AppleScriptRunner` / `WorkspaceLauncher`) は `Protocol` + `static var` で実装。テスト時は `TestMocks` で一括差し替え:

```swift
override func setUp() {
    mocks = TestMocks()  // 全 Executor の static var を mock に差し替え
}
override func tearDown() {
    mocks.restore()
}
```

### 15.3 ロガー差し替え

`LoggerContext.shared = InMemoryLogger()` でログを buffer に捕捉。`contains(category:messageContains:)` で発火確認。

### 15.4 HTTP API テスト

- **ユニット**: `HTTPParser` / `ToolCatalog` / `MCPAdapter` / `OpenAPIGenerator` / `AgentCard` の純粋ロジック
- **integration**: `ControlServer` を random port で立ち上げ URLSession で実アクセス
- **E2E**: `scripts/control_api_smoke.sh` で実 GUI バイナリを起動して curl 経由で全エンドポイントを検証

---

## 16. 実行環境と環境変数

| 変数 | 用途 |
|---|---|
| `FLOATINGMACRO_CONFIG_DIR` | 設定/ログディレクトリを上書き |
| `FLOATINGMACRO_LOG_LEVEL` | ログ最低レベル (CLI `--log-level` と同等) |
| `DEVELOPER_DIR` | `swift test` 実行時に Xcode.app を参照 (CommandLineTools だけだと XCTest 不足) |

---

## 17. マイルストーン (2026-04-16 時点の実装状況)

### MVP (v0.1) — 実装済み ✅

- [x] `Package.swift` + 3 ターゲット (Core / CLI / App)
- [x] `Action` enum + JSON パーサ + ネスト禁止
- [x] `KeyCombo` パーサ + CGEvent 送出
- [x] `TextActionExecutor` (クリップボード save/restore + defer での確実な復元)
- [x] `LaunchActionExecutor` (shell/URL/bundle/path 分岐)
- [x] `TerminalActionExecutor` (Terminal / iTerm / generic)
- [x] `MacroRunner` + ログ
- [x] `ConfigLoader` / `ConfigWriter` + FLOATINGMACRO_CONFIG_DIR
- [x] `AccessibilityChecker` + `AutomationChecker`
- [x] `fmcli` (action / preset / permissions / config / log)
- [x] SwiftUI + NSPanel フローティング窓
- [x] 縦積みボタンレンダリング + ドラッグ移動
- [x] メニューバー常駐 (`NSStatusItem`)
- [x] プリセット切替メニュー
- [x] 透明度メニュー (4 段階)
- [x] ボタン編集 GUI (プリセット/グループ/ボタン CRUD + アイコン/色ピッカー)
- [x] 位置・サイズの自動保存/復元
- [x] バナー通知 (エラー時 3 秒)
- [x] アイコン表示 (画像ファイル / アプリ自動推論)
- [x] 構造化ロギング (JSON 1 行 1 イベント + ローテーション)
- [x] HTTP 制御 API (REST + /tools + /tools/call)
- [x] AI 自己紹介 `/manifest` + `/help`
- [x] OpenAPI 3.1 自動生成 (`/openapi.json`)
- [x] A2A Agent Card (`/.well-known/agent.json`)
- [x] MCP JSON-RPC 2.0 HTTP transport (`POST /mcp`)

### v0.2 (UI 補強)
- [ ] ドラッグ並べ替え (SwiftUI `.onDrop`)
- [ ] 横並びレイアウト切替
- [ ] プリセットのインポート / エクスポート
- [ ] ウィンドウ形状プリセット (小/中/大)
- [ ] マクロ (複合アクション) の GUI エディタ

### v0.3 (ターミナル強化)
- [ ] iTerm のペイン分割マクロ
- [ ] Warp / Ghostty の貼付経路最適化
- [ ] ターミナルプロファイル指定
- [ ] tmux 連携

### v0.4 (AI 協調強化)
- [ ] A2A Task API + SSE streaming (長時間実行マクロ向け)
- [ ] MCP stdio transport (`fm-mcp` バイナリ)
- [ ] `fmcli remote` サブコマンド (制御 API の薄いラッパ)
- [ ] ログの OpenTelemetry OTLP エクスポート

### v1.0
- [ ] Developer ID 署名 + notarization
- [ ] 配布用 DMG
- [ ] 自動アップデート

---

## 18. 設計上の既知の判断

### Tauri ではなく Swift を選んだ理由
- Mac 専用で割り切るためクロスプラットフォーム性が不要
- `NSPanel` の非アクティブ化挙動が Swift なら 1 行、Tauri だと objc ブリッジが必要
- `NSAppleScript` / `NSWorkspace` / `CGEvent` / `AXIsProcessTrusted` / `NWListener` の全てがネイティブで即時アクセス

### swift-nio / Vapor を入れない理由
- 常駐ツールの起動時間を増やしたくない
- 依存を増やすとメンテが複雑化
- `NWListener` で HTTP/1.1 localhost サーバーは十分実装可能

### キーボード入力は keycode 送出、テキストはクリップボード貼付
- 日本語 / 記号で化けない
- IME 状態に依存しない
- キーリピート事故が起きない

### ログは JSON 1 行 1 イベント
- AI が `tail -f | jq` でパイプ処理できる
- 行単位なのでローテーションが単純
- OTLP 移行も容易

### HTTP 制御 API はプロトコル仕様を複数対応
- ACP (OpenAPI): REST ネイティブ、Postman / curl で即使える
- A2A (Agent Card): Google / ADK エコシステムから discovery 可能
- MCP (JSON-RPC 2.0): Claude Desktop / Claude Code から MCP サーバーとして登録可能
- すべて同じ `ToolCatalog` から自動生成されるので、実装は 1 セット / 配布は複数形式

---

## 19. クリーンルーム設計ポリシー

本プロジェクトは Windows 用 FloatingButton (Trifolium Studio) の Mac 版相当を作ることを目的とするが、以下を厳守する:

- 元ソフトのコード / バイナリを **見ない**
- 元ソフトを逆アセンブル / リバースエンジニアリング **しない**
- 参照元は **公式サイトのスクリーンショットと機能説明のみ**
- 名称 / UI 配色 / アイコンデザインは **意図的に別物**

名称を `FloatingMacro` に変更したのも、元ソフトとの差別化の一環。

---

## 20. 用語集

| 用語 | 定義 |
|---|---|
| プリセット | ボタン群の 1 セット。シーン別に切り替える |
| グループ | プリセット内でボタンをまとめる単位 |
| アクション | ボタンが実行する 1 つの動作 |
| マクロ | 複数アクションの順次実行 |
| コンボ | 修飾キー + 本体キーの組み合わせ文字列 |
| 制御 API | localhost HTTP サーバー経由の操作インターフェース |
| ツールカタログ | MCP/OpenAI/Anthropic の 3 方言で表現可能な機能定義一覧 |
| Agent Card | A2A 仕様の自己紹介 JSON (`/.well-known/agent.json`) |
| MCP | Model Context Protocol (Anthropic 提唱) |
| A2A | Agent-to-Agent protocol (Google 提唱) |
| ACP | Agent Communication Protocol (IBM / BeeAI、REST ベース) |

---

## 21. 参考情報

### Apple Documentation
- [NSPanel](https://developer.apple.com/documentation/appkit/nspanel)
- [CGEvent](https://developer.apple.com/documentation/coregraphics/cgevent)
- [NSAppleScript](https://developer.apple.com/documentation/foundation/nsapplescript)
- [NSWorkspace](https://developer.apple.com/documentation/appkit/nsworkspace)
- [NSPasteboard](https://developer.apple.com/documentation/appkit/nspasteboard)
- [NWListener](https://developer.apple.com/documentation/network/nwlistener)

### Protocol Specs
- MCP (Anthropic): https://modelcontextprotocol.io/specification
- A2A (Google): https://a2aproject.github.io/A2A/specification/
- OpenAPI 3.1: https://spec.openapis.org/oas/v3.1.0
- JSON-RPC 2.0: https://www.jsonrpc.org/specification

### 関連ツール (inspiration, not implementation reference)
- Keyboard Maestro / BetterTouchTool / Hammerspoon
- FloatingButton (Windows, Trifolium Studio) — 外部機能仕様のみ参考
