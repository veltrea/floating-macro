# Changelog

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
