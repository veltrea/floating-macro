# Changelog

## v0.9.3 (2026-05-03)

v0.9.2 からの差分。ボタン編集 UI で特殊キー設定が反映されない不具合の修正と、key/text 系統の自動検証を担う `fm-test-target` ハーネスの大幅強化。

### 不具合修正 — ショートカットキーボタンの種類インジケーターが追従しない

ボタン編集パネルで「key」セグメントに切り替えて特殊キー（Delete / 矢印 / Tab 等）を選んでも、右上の種類インジケーターが `text` のまま残り、明示的に「この key を有効にする」ボタンを押さない限り保存後も text アクションとして扱われていた問題を修正。

修正後は、キー記録ボタン / 「特殊キー…」メニュー / 手入力のいずれかでキー欄が埋まった瞬間、`actionType` が自動で `key` に昇格してインジケーターも切り替わる。外部 API (`externalKeyComboRequest`) 経由で combo を流し込んだ場合も同様。

### 開発基盤 — `fm-test-target` と `text_inject_e2e.sh` の検証強化

text / key 系のアクションが目的アプリに本当に届いたかを「ログではなく実物」で検証する E2E ハーネスを大幅強化。回帰検出の網が大きく広がる。

- **`/selection` エンドポイント追加**: NSTextView の `selectedRange` (location + length) を JSON で返す。矢印キー / Cmd+A 等の効果を数値で確証できる
- **可視キャレット**: `VisibleCaretTextView` サブクラスで挿入点を 4px 太の赤バーで描画。スクリーンショットレビューで cursor 位置が目視確認できる
- **キーイベント可視ログ**: テストアプリ下半分に `[ms] kc=N mods=⌘⌥⌃⇧ chars="x" name=Delete` 形式で全 keyDown を即時表示
- **`text_inject_e2e.sh` の 3 軸検証**: 各 key ケースで (1) keyDown が届いたか (2) 結果テキストが期待通りか (3) selection 範囲が想定位置か、を同時にアサート
- **自動スクリーンショット**: 各ケース完了時に `/tmp/fm-test-screens/<timestamp>/` へ PNG を保存。UI 異常（ドロップダウンの位置ずれなど）の事後レビュー基盤
- **検証ケース追加**: delete / tab / return / left arrow / down arrow / cmd+A の 6 ケース。pre-paste 用 seed text を伴うので「特殊キーが本当にエディター操作として処理されたか」まで踏み込む
- **テスト基盤の不具合修正**: `osa_set_clipboard` の bash here-string が末尾 \n を勝手に付けていたバグ（pre-text "hi" がクリップボード上で "hi\n" になり全 selection 検証が +1 ズレる原因）を修正。`target_text` も sentinel `X` を付けて bash の `$(...)` による末尾改行ストリップを回避

### 機能追加 — 公開プリセット集からの自動配布

初回起動時、同梱の seed プリセット 7 本をユーザーフォルダにコピーした後、バックグラウンドで [veltrea/floating-macro-preset](https://github.com/veltrea/floating-macro-preset) リポジトリの `index.json` を取得し、`defaults` に列挙された ID については GitHub 側の最新版で上書きする。ネット未接続・取得失敗時は同梱版がそのまま残るため挙動は退行しない。UI 表面には変更なし (config に `seedInstalled=true` が立つので 2 回目以降は走らない)。

- `PresetCatalogClient` (Core 新規): `https://raw.githubusercontent.com/veltrea/floating-macro-preset/main/` をベースに `index.json` と個別プリセット JSON を fetch する読み取り専用クライアント。タイムアウト既定 5 秒、`FLOATINGMACRO_PRESET_CATALOG_URL` 環境変数で差し替え可
- `SeedPresetInstaller.refreshFromCatalog()` を追加: index 取得 → defaults を順次 fetch → savePreset で上書き。1 件失敗しても他に影響しない best-effort 動作
- `PresetManager.installSeedPresetsIfNeeded()`: 同梱インストール後にバックグラウンドキューで上記 refresh を一度だけ実行

### 機能追加 — ボタンに「実行前の確認」をつけられる

ボタン単位の **実行前確認ダイアログ** を追加。再起動・シャットダウンのような取り返しのつかない操作を 1 クリックで誤発火させないためのガード。視線入力ユーザーや Switch Control 利用者にとっては「押し間違えても助かる仕組み」、AI から自動操作する場合は「人間に最終確認を取らせる安全弁」になる。

- ボタン編集パネルの「ツールチップ」直下に **「実行前の確認」** セクションを新設。チェック ON で確認ダイアログが介在するようになる
- 「確認メッセージ」欄に書いた文言は、ダイアログ本文に表示される（空欄なら「この操作を実行します。」または「この操作は元に戻せません。」を自動表示）
- 「危険な操作」チェック ON で、ダイアログの **「実行する」ボタンが赤い destructive スタイル** になる。再起動・シャットダウン等の取り消し不可能な操作だけ ON にする使い方を想定
- デフォルトボタンはキャンセル側に固定。Return キーや視線停留での誤発火を防ぐ
- ボタン複製（コンテキストメニュー「複製」やグループ複製）で確認設定も一緒にコピーされる。コピー後に confirm 設定が抜けて安全機構が消えることはない

データモデル: `ButtonDefinition` に `confirm: Bool` / `confirmMessage: String?` / `confirmDestructive: Bool` の 3 フィールドを追加。後方互換: 既存プリセット JSON はこれら 3 キーが欠落していても従来どおり読み込める（デフォルトは確認なし）。確認 OFF のときは `confirmMessage` と `confirmDestructive` を保存時に正規化（残骸データがファイルに残らない）。

Control API: `button_add` / `button_update` の inputSchema に `confirm` / `confirmMessage` / `confirmDestructive` を追加。AI からも 1 リクエストでまとめて設定できる。`button_update` は `confirmMessage: null` でクリア、`confirm: true/false` で ON/OFF 切替。

用途想定: 視線入力ユーザーが「再起動」「シャットダウン」「ログアウト」「セッション破棄系シェルコマンド」を誤発火しないためのガード。AI から `button_press` で発火させる前提のボタンに対する **人間最終確認**（重要な mass operation の手前など）にも使える。

### 機能追加 — seed プリセット「♿ アクセシビリティ」

`♿ アクセシビリティ` プリセットを seed として追加。視線入力 / Switch Control / 音声操作で常駐パネルを使うユーザー向けに、押しにくい多指コンビ・電源系操作を 1 ボタン化。

7 ボタン構成:

- **ロック / スリープ**: 画面ロック (`ctrl+cmd+q`) / スリープ (`pmset sleepnow`) / 画面オフ (`pmset displaysleepnow`)
- **電源系 (要確認)**: 再起動 / シャットダウン / ログアウト — すべて確認ダイアログ + 赤い destructive スタイル付き、`osascript` 経由で実行
- **緊急**: 強制終了ダイアログ (`cmd+option+esc`) — フリーズしたアプリを Force Quit リストから終了させる

注意: 再起動 / シャットダウン / ログアウトの初回押下時に macOS が「FloatingMacro が System Events を制御することを許可しますか?」というダイアログを 1 回だけ表示する → 許可してから実用可能になる (本仕様はプリセットの memo に記載)。

回帰テストとして `SeedPresetInstallerTests` を追加: 全 bundled seed が `Preset` として decode できること、destructive 操作 (再起動 / シャットダウン / ログアウト) が `confirm + confirmDestructive` を持つこと、低リスク操作 (画面ロック / スリープ / 強制終了ダイアログ) は逆に `confirm` なしであることを検証。

## v0.9.2 (2026-05-02)

v0.9.1 からの差分。「ショートカットキー」アクションで Delete キーや矢印キー等の特殊キーが登録できなかった問題を修正。

### バグ修正 — 特殊キーが登録できない問題

旧 UI ではキー名を **TextField に手入力** する設計だったため、以下の問題があった:

- ヒント文言が「a〜z / 0〜9 / space / return / esc 等」しか案内しておらず、`delete` `left` `right` `up` `down` `home` `end` `pageup` `pagedown` `forwarddelete` `f1`〜`f20` といった対応キーの存在をユーザーが知る術がなかった (`KeyCombo` パーサ自体は元から対応していた)
- 仮にユーザーがキー名を知っていても、登録のために **実キーを押す**ことができない: TextField にフォーカスがある状態で Delete キーを押せば文字が削除され、矢印キーを押せばキャレットが移動するだけで、キー名を打ち込まされる体験になる

### 機能追加 — キー記録ボタンと特殊キードロップダウン

ボタン編集パネルとマクロステップ編集行の双方に、以下 2 つの入力支援 UI を併設:

- ⌨ **「キーを押して記録」ボタン**: 押すと記録モードに入り、`NSEvent.addLocalMonitorForEvents(matching: .keyDown)` で次の 1 キーを吸い取る (return nil でイベント消費するため、記録対象の Delete キー等が他フィールドに副作用を与えない)。修飾キー (cmd/shift/option/ctrl) と base key を同時に取得して既存トグル＋テキストフィールドに反映。Esc 単独で記録キャンセル
- 📋 **「特殊キー…」プルダウン**: Delete / Forward Delete / 矢印 4 方向 / Home / End / Page Up/Down / Return / Tab / Space / Escape / F1〜F20 を一覧から選んで `baseKey` に流し込む。キーボード操作が困難な場面の代替手段

ヒント文言も「a〜z / 0〜9 / 矢印 / Delete / F1〜 等」に更新。マクロステップ行 (type=key) では combo 文字列に直接書き込む派生コンポーネント (`ComboKeyRecorderButton` / `ComboSpecialKeyMenu`) を用意し、コンパクトなアイコンボタンとして配置。

### Control API 拡張 — ACP からも特殊キー一覧を発見できるように

UI に特殊キー一覧を持たせただけだと、AI 側はどのキー名が使えるか相変わらず暗記でカバーすることになる。これを解消するため正規カタログを core に置き、ACP からも引けるようにした。

- `list_key_codes` ツール (GET `/key-codes`) を追加: `modifiers` / `modifierAliases` / `specialKeys` (name + label) / `functionKeys` / `keyAliases` / `examples` / `notes` をまとめて返す。AI が「特殊キー名を覚えていない」「ユーザーにピッカーを提示したい」場面で参照する想定
- `settings_set_key_combo` の description を更新: 特殊キーリスト (delete, forwarddelete, 矢印, home/end, pageup/pagedown, return, tab, space, escape, f1-f20) を明記し、`list_key_codes` への誘導を追加
- `KeyCombo` (core) に discoverable な静的カタログ (`specialKeys`, `functionKeys`, `modifierNames`, `modifierAliases`, `keyAliases`) を追加。設定 UI の `KeyNameLookup.specialKeys` もこのカタログから合成するため、二重管理を解消

### 内部追加

- `KeyNameLookup` enum を新設: virtual key code → KeyCombo パーサが理解するキー名の正引きを行う (キーキャプチャ専用)。リストデータ自体は `KeyCombo.specialKeys` / `functionKeys` を参照
- `KeyCombo.keyCodeMap` 側はノータッチ (元から十分な対応範囲を持っていた)

## v0.9.1 (2026-05-02)

v0.8 からの差分。プリセット単位のメモ機能を追加。「このプリセットを使う前に何を確認すべきか」を残しておけるようになった。

### 機能追加 — プリセット単位メモ

- `Preset` 構造体に `memo: String?` フィールドを追加。プリセット全体に対する自由記述メモを保存できる（後方互換: 既存 JSON は `memo` キー欠落で OK）
- フローティングパネル上部に **折りたたみメモブロック** を新設。memo が設定されているプリセットでだけ描画、デフォルトは畳まれた状態でタイトル横に1行プレビュー、クリックで全文展開（黄色背景でメモであると一目で分かる）
- 設定ウィンドウのサイドバー（プリセット選択直下）に **メモ編集 TextEditor** を追加。複数行入力可、文字数カウント表示、編集内容は即座にディスクへ保存
- 用途: 「Studio One Pro 用プリセット → F1〜F12 を OS 設定で標準ファンクションキーに」「AI 用プリセット → 対象アプリを前面にしてから押す」のような **時間を空けて使い直すと忘れがちな前提条件** を残せる

### Control API 拡張 — ACP からも memo を読み書き

- `preset_create` の inputSchema に `memo` を追加（プリセット作成と同時にメモを書ける）
- `preset_rename` を `preset_update` 相当に拡張（互換のため tool 名は維持）。`displayName` と `memo` の両方を任意更新できる。`memo: ""` でメモのクリア
- `GET /state` レスポンスに `memo` フィールドを追加（現在のアクティブプリセットのメモを取得）
- `GET /preset/current` / `preset_export` は Preset 構造体の Codable に追従して自動で memo を含む

### システムプロンプト

- `agent_prompts.json` の normal モードに **「プリセットメモ（使う前提を書き残す）」** セクションを追加。AI がプリセット作成時に memo を提案・記入するよう誘導

### 同梱プリセット

- `logic-pro` と `midjourney` の seed プリセットに memo 例を追加（ファンクションキー設定 / クリップボード上書きの注意など）

## v0.8 (2026-05-02)

v0.7 からの差分。アクセシビリティ権限フローの構造的バグを修正、プリセットの並び順をユーザーが調整できるようにした。

### バグ修正 — アクセシビリティ権限ダイアログの無限ループを根絶

- `tccutil reset` を起動時に自動で呼ぶ挙動を撤廃（macOS Sequoia の TCC daemon が「TCC エントリのない AX 使用プロセス」を検知すると OS 許可ダイアログを自動でスポーンする挙動と、こちらの `prompt: true` 呼び出しが衝突して permission request が二重キューに登録され、ダイアログが無限ループする原因だった）
- 起動時の `AXIsProcessTrustedWithOptions(prompt: true)` 呼び出しは `--prompt-accessibility` 引数経由のときのみ実行（[修復] ボタンが self-restart した新プロセスでだけ呼ばれる）
- 0.8 秒後の自前 `openSystemPreferences()` フォールバックと「あと1ステップで完了します」NSAlert を撤廃（OS ダイアログのボタンを focus 取り合いで無反応化させたり、3 ウィンドウ同時表示で混乱を招く副作用があった）
- 結果: リビルド後の通常起動ではバッジで通知するだけ、ユーザーが [修復] ボタンを押すと OS ダイアログが **1 回だけ** 出る、許可後 3 秒以内にバッジが消える、というシンプルなフローに

詳細経緯と Sequoia の罠の一覧は `/Volumes/DISK/dev/knowledge/macos_accessibility_permission.md`（同一マシン外からはリポジトリの SPEC.md 参照）にまとめた。

### 機能追加 — プリセットの並び順をユーザーが変更可能に

- 編集ウィンドウのプリセット行 `…` メニュー、および**フローティングパネルのプリセット名を右クリック**して出るコンテキストメニューに **「並べ替え…」** を追加。DnD シートで順序を変更できる
- 順序は `config.json` の `presetOrder` フィールド (新規) に保存。アルファベット順で固定だった旧挙動から脱却
- 外部から追加されたプリセット (Finder ドロップ等) は末尾にアルファベット順で自動追加され、ファイルが消えたエントリは self-heal で除去
- Control API: `preset_reorder {ids: [String]}` を追加 (`/preset/reorder`)。`/preset/list` のレスポンス順も保存順に追従

## v0.7 (2026-05-02)

v0.6 からの差分。「ボタン編集」だった画面が **複数オブジェクトの統合エディタ**に育ったので、名称・導線・編集体験を全部洗い直した。

### 機能追加 — 編集ウィンドウ左ペインで DnD 並べ替え

- **ボタン**: 同一グループ内の並べ替え／別グループへの移動を、行・ヘッダーへのドロップで実現
- **グループ**: ヘッダー同士のドロップで並べ替え
- 着地点ハイライト: グループは枠線、ボタンは上端ライン
- 旧グループ右クリックメニュー（編集/削除）は撤去し「左で選択 → 右で編集」の流れに一貫化
- `PresetManager.reorderGroups` ラッパーを追加

実装メモ: SwiftUI `Button` が下方向ジェスチャを消費する問題があり、行を `HStack + onTapGesture` に置き換えて `.onDrag/.onDrop` を直付け。`performDrop` は非同期化（同期 `DispatchGroup.wait` + `main.sync` の組み合わせはドロップを途中キャンセルしただけでメインスレッドが固まる）。

### 改善 — 編集ウィンドウへのアクセスと UI 文言を整理

- **ウィンドウ名を「ボタン編集」→「編集」に変更**（タブ・メニュー含む）。実際にはグループ・プリセット・セキュリティも編集できる画面なので、名称を実態に合わせた
- **グループ追加 UI をボタン追加と統一** — ワンクリックで「新グループ」を作成。グループ行の鉛筆ボタンで後からリネーム
- **プリセット／グループの右クリックメニューを「編集...」「削除...」に統一**。プリセットの「編集...」は編集ウィンドウを開く動作に変更（旧「プリセット名を変更」の NSAlert は削除）
- **フローティングパネルの歯車（AI 接続）の左に鉛筆アイコンを追加**し、編集ウィンドウへの導線を明示

### 機能追加 — グループ・ボタンの複製、削除ボタンの再配置

- 編集ウィンドウ左ペインのグループ行・ボタン行を**右クリック → 「複製」**で複製可能に。複製先は元の隣に挿入され、ラベルは「○○ のコピー」、id は新規発行
- `PresetManager.duplicateGroup(id:)` を新規追加（中のボタンも fresh id で複製）
- 右ペインの**削除ボタンを上部から下部の保存ボタン左隣**に移動（ButtonEditor / GroupEditor 両方）
- 右下の「グループ追加」「ボタン追加」を HStack で横並びに配置

## v0.6 (2026-05-01)

v0.5 (DMG 配布版) からここまでの累積変更点。

> **注記 — コミット履歴の一部消失について**
>
> 今回のサイクルでは Claude 側のサーバー障害に巻き込まれ、いくつかのコミットが失われています。**追加された機能・正式に変更された箇所についてはソースコードを根拠に網羅的に記録できています** が、過程で行った試行錯誤的な変更（中間コミットや diff の積み重ね）の履歴は残せていません。CHANGELOG として参照する分には問題ありませんが、「なぜこの実装になったか」の細部を git log から追えない時期がある点だけご承知ください。

### 変更 — Control API トークンの保存先を Keychain からファイルに変更

これまで Control API の認証トークンを macOS Keychain に保存していましたが、本リリースで **`~/Library/Application Support/FloatingMacro/control_api_token` (mode 0600) をトークンの一次保存先**に変更しました。Keychain は `security find-generic-password ...` CLI 互換のためのミラーとして残しています。

なぜこの変更を入れたかを正直に書いておくと:

- **導入の仕方が良くなかった** — Keychain は本来「user が能動的にツール間の信頼関係を許可する」ための仕組みでしたが、当時の実装ではその意図を user に伝えられておらず、結果として「アクセシビリティ設定のためのおまじない」のように受け取られる UX になっていました。
- **セキュリティ上の効果も上がっていなかった** — Control API は loopback (127.0.0.1) のみで、同一ユーザー権限のプロセスからしか到達できません。同一ユーザーで動く別プロセスからの読み出しに対して、Keychain ACL もファイル mode 0600 も実質同等の防御力しか持ちません。Keychain による追加セキュリティの利得はほぼゼロでした。
- **デバッグ・テスト作業の手間ばかり増えていた** — ad-hoc 署名のリビルドのたびにバイナリハッシュが変わると、Keychain ACL は新バイナリを「別アプリ」と判定して読み出し時にパスワード入力ダイアログを毎回要求します。実装の意図と裏腹に、user とテストエージェントの両方にとって作業の障害になっていました。

総合すると **「導入の効果が出ていなくて、その割に手間ばかり増えていた」状態** で、一旦 Keychain ベースのトークン管理は撤廃する判断をしました。AI ⇄ FloatingMacro 間の **能動的な認証ステップ** は別のレイヤー (例: AI 連携ウィンドウでのクライアント別ペアリング、許可中クライアントの可視化と revoke) で再設計する予定です。

トークンの取得方法は以下のどちらでも可能 (ファイル経由がパスワード入力不要で推奨):

```bash
# 推奨
cat ~/Library/Application\ Support/FloatingMacro/control_api_token

# 互換 (Keychain ミラー経由)
security find-generic-password -s FloatingMacro -a ControlAPIToken -w
```

### 改善 — アクセシビリティ修復フローの整理

権限再付与時のダイアログ動作と user 体験を見直しました。

- **自前 NSAlert を削除して OS の `prompt:true` ダイアログに一本化** — 自前 NSAlert は TCC に対して何の効果もない装飾だったため撤廃。
- **`openSystemPreferences()` の 0.8 秒後フォールバック追加** — Sequoia 以降、OS ダイアログの「システム設定を開く」ボタンが効かないケースに備え、保険として自前で System Settings を開く。
- **修復ボタンを self-restart 方式に変更** — `NSWorkspace.openApplication` で `--prompt-accessibility` 引数付き再起動 → 新プロセスで AX キャッシュがクリーンな状態から `prompt:true` を呼ぶ。古いエントリ + stale TRUE で一覧追加が阻害されるケースを回避。
- **`accessibilityTrusted` の初期値を false に変更** — 起動直後の stale TRUE キャッシュ起因で警告バナーが誤って消える事故を防止 (3 秒の polling ですぐ実値に追従)。
- **`AccessibilityChecker.openSystemPreferences()` を `/usr/bin/open` 経由に変更** — `NSWorkspace.shared.open(url)` が System Settings 未起動時に silent fail するケースに対応。失敗時は `NSWorkspace` にフォールバック。実行ログも追加して診断性向上。
- **TCC reset 二重発火の解消** — `scripts/rebuild-and-relaunch.sh` の起動前 `tccutil reset` を撤去し、アプリ側 `BinaryIdentity` の単発 reset に一本化。System Settings 側の挙動と競合する可能性を排除。

### 機能追加 — ミニアイコンに右クリックメニュー

フローティングウィンドウを折りたたんだ時のミニアイコンを右クリックすると、メニューバーと同じメニュー (表示/非表示切替・プリセット切替・透明度・ボタン編集・AI モード・AI 接続・設定フォルダを開く・再読み込み・終了) を表示。ステータスバーアイコンに手を伸ばさずミニアイコンから直接操作できるように。

### 機能追加 — グループヘッダーの右クリックメニュー

- **GroupView の contextMenu に「グループを削除...」(destructive)** — 確認ダイアログ経由で安全に削除。
- **パネル本体の contextMenu に「新規グループを追加」を追加** — 空白部分の右クリックでもグループ追加が可能に。
- **ScrollView の hit-test 領域を全面に拡張** — `GeometryReader` で包んで、ボタンが少ない時の空白部分でも contextMenu が反応するように。

### その他

- `Info.plist` の `CFBundleVersion` を 7 に追従 (`scripts/release.sh` の build 番号 auto-bump 機構との同期)
- 関連ドキュメント (README, npm/README, docs/mcp/*, agent_prompts.json, SystemPrompt.swift, scripts/*.sh) を新トークン保存先に追従して更新

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
