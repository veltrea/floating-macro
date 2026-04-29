# Changelog

## v0.5 (2026-04-29)

### 新機能 — アクセシビリティ権限の自動リカバリ

これまで、リビルド・アップデート・時間経過などをきっかけに macOS が **アクセシビリティ権限を音もなく無効化する** 問題があり、アプリがログ上は「Text injected」と出すのに対象アプリには 1 文字も貼られない、という謎の故障モードに陥ることがありました (ad-hoc 署名 + `com.apple.provenance` xattr による TCC 再検証が原因)。本リリースで、これを **自動検出 + ワンクリックリカバリ** できるようにしました。

- **バイナリ ID 比較による起動時自動 reset**
  - 起動時に SHA-256 で前回バイナリと比較し、変化していたら `tccutil reset Accessibility` を自動発火
  - 状態は `~/Library/Application Support/FloatingMacro/last_binary_hash.txt` に記録
  - 初回起動と通常の再起動 (バイナリ変化なし) では何もしない
- **権限喪失バッジ**
  - パネル下部に常時警告バッジを表示 (権限が無効なときのみ)
  - クリックすると `tccutil reset` + システム設定オープンを一発で実行 → ユーザーは `+` で `.app` を再追加するだけで復旧
- **AccessibilityChecker probe の改善**
  - `AXIsProcessTrusted` のキャッシュ罠 (剥奪されても true を返し続ける) を、AX API probe で補う 2 段構えに
  - probe の counter-signal は `.apiDisabled` のみに限定 (フォーカスアプリが AX に応答しないだけで untrust 判定するフリッカー bug を解消)
- **ワンクリックの「アクセシビリティ設定を開く」ボタン**
  - default プリセット先頭に追加。System Settings → プライバシーとセキュリティ → アクセシビリティへ直接ジャンプ

### 新機能 — GUI E2E テスト基盤

ハーネスアプリ (`fm-test-target`) と E2E スクリプトを追加し、テキスト挿入の挙動を**自動で**検証可能にしました。

- **fm-test-target** (`Sources/FMTestTarget/`)
  - 専用の macOS GUI アプリ (NSWindow + NSTextView)
  - smart-substitution を全切り、UTF-8 NSPasteboard 直接、spin-wait で IME や LC_CTYPE の罠に対応
  - ローカル HTTP API (`/focus` `/clear` `/text` `/events` `/quit`) で外部からテスト駆動
- **scripts/text_inject_e2e.sh**
  - 実行前に baseline 8 ケース (paste / copy / cut / select-all / 日本語 / smart-sub / 長文) で「ハーネスが現実のテキストエディタとして動作するか」を検証
  - 7 ケース (ASCII / 日本語 / 改行 / `/compact` / 記号 / 600 文字 / restoreClipboard=false) を `[key✓/✗ text✓/✗]` の 2 軸で報告
  - 失敗時は CGEvent.post の silent drop と paste race の切り分けを自動診断

### 新機能 — Synthesized Real Click による button_press

`button_press` ツールが、各ボタンに付与した `accessibilityIdentifier` を AX で解決し、その screen rect の中心に **CGEvent で実際にマウスクリックを発射** するよう変更されました。

- 同一プロセスの SwiftUI Button の **ネイティブ press 視覚効果** が走るので、人間の観察者にも「ボタンが押された」のがはっきり見える
- window 隠蔽 / hit-test 破損 / disabled view 等、`executeButton` 直叩きでは見逃される失敗モードを検出可能
- カーソルが button center に物理的に移動 → click → 元位置に復帰

### 新機能 — プリセット同梱 / インポート / エクスポート

- **同梱プリセット** (`SeedPresetInstaller`)
  - `midjourney` / `note-hashtags` を初回起動時にユーザーディレクトリへインストール
- **API**: `preset_export` / `preset_export_bundle` / `preset_import` / `preset_install_seeds`
- **PresetDirectoryWatcher**: `~/Library/Application Support/FloatingMacro/presets/` の外部変更 (Finder からのドラッグ等) を検知して UI に反映
- **`preset_create`**: name 省略時に `preset-N` で自動採番

### 改善

- `rebuild-and-relaunch.sh`: launch 直前に `tccutil reset` ステップを追加
- `scripts/reset_accessibility.sh`: 単独で TCC reset + System Settings オープンするスタンドアロンツール
- `scripts/seed_install_smoke.sh`: 同梱プリセットの初回インストール疎通確認

### 既知の制限

- **Developer ID 署名・notarization は未対応**。ad-hoc 署名 + `com.apple.provenance` の組み合わせで TCC が定期的に trust を剥奪する根本問題は解消できていません。本リリースは「壊れた瞬間にバッジで気付ける + ワンクリックで直せる」ことで運用上のダメージを最小化する戦略です。本格配布には Developer ID 移行が必要 (v1.0 予定)。

---

## v0.4 (2026-04-27)

### 新機能

- **AI 連携ウィンドウの対応クライアント拡張**
  - v0.3 では Claude Code のみだったワンクリック登録を、Cursor / Gemini CLI / VS Code / Windsurf にも拡張
  - 各クライアントごとに「CLI 登録」「HTTP 登録」の 2 系統ボタンを用意
  - 設定ファイルの書き込み先: Cursor (`~/.cursor/mcp.json`)、Gemini CLI (`~/.gemini/settings.json`)、VS Code / Windsurf (各 `mcp.json`)
- **CLI (stdio) 接続用の MCP サーバを同梱**
  - `npm/` ディレクトリに Node.js 製の薄い MCP server (`floatingmacro-mcp` パッケージ) を追加
  - DMG ビルド時にアプリバンドル内 (`Contents/Resources/npm`) に同梱
  - macOS の codesign / Gatekeeper / Keychain ACL を経由しない安定経路を提供
  - 「CLI 登録」ボタンが裏でこのパッケージを `npx -y file:...` 形式で参照する設定を書き込む
- **ACP (Agent-Centric Protocol) マニフェスト対応**
  - `GET /agents` / `GET /agents/floatingmacro` / `POST /runs` を追加
  - MCP に対応していない AI（素の ChatGPT 等）でも `curl` で `/tools/call` を叩いて操作可能
  - 接続用プロンプトは AI 連携ウィンドウから Bearer 埋め込み済みでコピー

### 改善

- **API 自己報告バージョンを更新**
  - `/manifest`、`/mcp` (initialize)、`/.well-known/agent.json`、`/openapi.json` が返す `version` を `0.1` → `0.4`
  - v0.2 / v0.3 の bump 時に取り残されていたものを修正

### ドキュメント

- **クライアント別 MCP 接続ガイドを `docs/mcp/` に新設**
  - `setup.md` (共通)、`claude-code.md`、`claude-desktop.md`、`cursor.md`、`gemini-cli.md`、`acp.md`
  - 各クライアントの設定ファイル形式・登録名規則・トラブルシューティングを集約
- **README を実態に同期**
  - 認証必須を反映、`/tools/call` 経由の例に統一、AI 連携ウィンドウのワンクリック登録を一推し
- **Manifest 経由の AI 接続フロー** を `CLAUDE.md` に整理

## v0.3 (2026-04-27)

### 新機能

- **AI 連携専用ウィンドウ**
  - メニューバー「AI に接続...」とフローティングパネル右上の ⚙ ボタンから起動
  - 接続用プロンプトを Bearer トークン埋め込み済みで一発コピー（Claude Code / Cursor / Gemini CLI / ChatGPT などに貼り付ければ FloatingMacro を操作可能になる）
  - Claude Code (`~/.claude.json`) に MCP エントリをワンクリック登録（既存の `mcpServers` を壊さず追記）
  - エンドポイント URL とトークン取得コマンドにインラインのコピー ✓ ボタン
  - 設計判断: ボタン編集（オブジェクト単位）と AI 連携（アプリ全体の初期セットアップ）は粒度が違うため Settings のタブにせず独立ウィンドウとした
- **デフォルトプリセットに「AI に接続」グループ**
  - 「接続用プロンプトをコピー」「Claude Code に MCP として登録」の2ボタンを最初から同梱
  - 新規インストール直後でもパネル上のボタンだけで AI 連携が完結
- **DMG に AI ブートストラップ手順書を同梱**
  - `AIに渡す手順書.md`（リポジトリ直下の `CLAUDE.md` のコピー）として Finder マウント時に並ぶ
  - リポジトリを見ない DMG ユーザーでも AI 連携の存在と手順を発見できる

### 改善

- **ディスカバリー系エンドポイントを認証除外**
  - `/manifest`、`/help`、`/.well-known/agent.json`、`/openapi.json` を Bearer 認証から除外
  - AI が「認証が必要だと知る」入口は無認証で開けないとニワトリと卵の問題になるため
- **`systemPrompt` を実態に合わせて修正**
  - 旧記述「認証はありません」を撤廃し、Bearer トークン取得手順と `/tools/call` 経由で叩くべき旨を明記
  - AI 接続時の最初の動作ガイドとして整合性を確保
- **フローティングパネルのリサイズ上限を撤廃**
  - 旧: `maxWidth: 300, maxHeight: 600` のハードキャップで「縮小はできるが拡大できない」現象
  - 新: `.infinity` に変更し、NSPanel のドラッグリサイズに完全追従
- **`pbcopy` の文字化け対策**
  - GUI 起動された macOS アプリの子プロセスは `LANG=""` / `LC_CTYPE="C"` を継承するため、UTF-8 の日本語が `pbcopy` で破損する
  - 該当する `launch` アクションでは `export LC_CTYPE=UTF-8` を先頭で実行するよう修正

### バグ修正

- **`build-app.sh` の SwiftPM リソースバンドルコピー漏れ**
  - これまで `FloatingMacro_FloatingMacroApp.bundle` だけコピーされ、`FloatingMacro_FloatingMacroCore.bundle` が抜け落ちていた
  - 結果 `agent_prompts.json` 等の Core 側リソースが `Bundle.module` で見つからず常にコード内のフォールバックに落ちていた（気付きにくいサイレント不具合）
  - 全 `*.bundle` をコピーするよう修正

### ドキュメント

- リポジトリ直下に `CLAUDE.md` を新設
  - AI（Claude Code 等）が FloatingMacro を ACP 経由で正しく操作するためのブートストラップ
  - `/tools/call` 経由で呼ぶ原則、preset JSON 直接編集禁止、典型的な依頼への対応マッピングなどを記載

## v0.2 (2026-04-26)

### 新機能

- **Control API に Bearer トークン認証を追加**
  - 起動時に Keychain にランダムトークンを保存し、以降全エンドポイントで `Authorization: Bearer <token>` を要求
  - `fmcli token show` でトークンを取得し、Claude Code などの外部ツールに渡して連携可能
  - `controlAPI.requireAuth` で有効/無効切替 (デフォルト ON)
  - 詳細: [docs/auth-spec.md](docs/auth-spec.md)、[docs/keychain-auth.ja.md](docs/keychain-auth.ja.md)
- **アプリアイコンを刷新**
  - Apple HIG 準拠の squircle マスクで再生成 (純粋な数式ベースの境界、ピクセルアーティファクトなし)
  - 透過済み 1024×1024 高解像度版を採用
- **ミニアイコン (パネル折りたたみ時) の視認性向上**
  - 紫グラデ背景 + ブランドカラー (`#ddb7ff`) の ⌘ シンボルに刷新
  - 旧: 暗い灰色背景 + 薄い command.square.fill (視認性低)

### 改善

- **フローティングパネル位置の永続化**
  - パネルを折りたたむ瞬間に位置を `config.json` に保存
  - 次回起動時にその位置から復元 (旧: アプリ終了時のみ保存だった)
- **ミニアイコン位置の永続化**
  - ドラッグで動かした位置を `UserDefaults` に保存
  - 次回 collapse 時、そこから復元
- **Settings ウインドウ大幅刷新** (`SettingsDetail.swift` +413 行)
  - `NSColorWell` を `NSViewRepresentable` でラップして即時プレビュー対応
  - グループエディタ、アプリアイコンピッカーなどの UI 改善

### ビルド・運用

- **`scripts/rebuild-and-relaunch.sh` 新設**: SwiftPM キャッシュを完全クリーン → ビルド → ad-hoc 署名 → 起動 を一括実行
- **`scripts/release.sh` 新設**: バージョンインクリメント + ビルド + DMG 作成 + 公開リポへの publish + GitHub release を一気通貫
- **`scripts/generate_iconset.py` 新設**: 透過処理 + ドロップシャドウ付き iconset を生成
- **`scripts/build-app.sh`**: アイコンソースを v1 squircle (vector) に切替、`@2x` (1024px) サイズも生成
- **App/Info.plist**: バージョン更新 (0.1 → 0.2)

### テスト

- `Tests/FloatingMacroCoreTests/AuthMiddlewareTests.swift` 追加 (Bearer 認証ミドルウェアの単体テスト)
- `Tests/FloatingMacroCoreTests/TokenStoreTests.swift` 追加 (Keychain TokenStore の単体テスト)

### ドキュメント

- `docs/auth-spec.md`: 認証機能の実装仕様書
- `docs/keychain-auth.ja.md`: Keychain 認証のセットアップ・運用ガイド
- `docs/AI_PROTOCOL.md` / `docs/AI_PROTOCOL.ja.md`: 認証フロー対応で更新
- `docs/manual_test.md` / `docs/manual_test.ja.md`: 手動テスト手順を更新

---

## v0.1 (2026-04-18)

初回公開リリース。
