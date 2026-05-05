# Changelog

## v0.12.0 (2026-05-05)

ビジュアル拡張ロードマップ **Phase 3 — マルチパネル**。1 枚のフローティングパネルを「複数の独立したフローティングパネル」へ拡張。各パネルは別々のプリセットを表示でき、ユーザー / AI / 設定画面のいずれからも追加・切替・削除を一元的に操作できる。詳細は [docs/plans/visual-expansion-roadmap.md](docs/plans/visual-expansion-roadmap.md) の Phase 3 章。

### 機能追加 — 複数フローティングパネルの同時表示

`AppConfig.panels: [PanelConfig]` を新設。1 つの `PanelConfig` は永続 id・preset 名・ウィンドウ形状 (位置/サイズ/透明度)・表示状態・「縁にドック」フラグを持つ。

旧 v1 形式 (`activePreset` + 単一 `window`) は decoder が自動的に 1 件の `PanelConfig` に移行して書き戻すので、既存ユーザーの設定ファイルを壊さない。移行期間中は legacy `activePreset` / `window` フィールドも `panels[0]` と同期して書き出され、まだそれらを参照する古いコードパスでも動く。

### 機能追加 — メニューバー「パネル」サブメニュー

ステータスバー / ミニアイコン右クリックメニューに **「パネル」サブメニュー** を新設。

- 「新しいパネルを追加」: プライマリパネルと同じプリセットで新規ウィンドウ生成
- 各パネル名のクリックで表示/非表示トグル (チェックマーク状態)
- パネルが 2 件以上のとき「↳ ⋯ を閉じて削除」項目で個別削除 (最後の 1 件は Core 側で削除拒否)

### 機能追加 — 設定画面「パネル」タブ

設定 window に **「パネル」タブ** を追加。各パネルの行が以下を表示:

- プリセット displayName + 現在位置・サイズ
- 永続 id (短縮表示) — Control API のリクエストで使うときの参考
- プリセット切替メニュー
- 削除ボタン (最後の 1 件は disabled)

### 機能追加 — Control API: panel_* ツール

複数パネルを AI から制御するための 5 ツールを追加:

- `panel_list` — 全パネルの id / presetName / displayName / visible / window 形状を返す
- `panel_create` — 新規パネル追加 (presetName 必須、x/y/width/height/opacity 任意)
- `panel_close` — 指定 id のパネルを閉じて削除 (最後の 1 件は拒否)
- `panel_show` — 指定 id を orderFront (ミニアイコン化されていれば展開)
- `panel_hide` — 指定 id を orderOut

既存 `window_*` ツールは「DEPRECATED: prefer panel_*」表記に切り替え、プライマリパネル (panels[0]) への作用に意味付け直した。後方互換のため引き続き動作するが、新規 AI 連携コードは panel_* を使うこと。

### 機能追加 — Control API: id 指定でパネルを完全制御 (Phase 3.6)

Phase 3 で導入した複数パネルを **AI 経由で id 指定して操作する** ためのツール 4 件を追加。マウス・トラックパッドのドラッグ操作が困難なユーザーが、自然言語の指示（「右上のパネルを左下に移動」「Claude Code のパネルを画面の右半分に広げて」など）でレイアウトを完結できるようにする。

- `panel_move` `{id, x, y}` — id 指定でパネルを絶対座標に移動
- `panel_resize` `{id, width, height}` — id 指定でリサイズ (min 120×80 にクランプ)
- `panel_opacity` `{id, opacity}` — id 指定で透明度変更 ([0.25, 1.0] にクランプ)
- `panel_set_preset` `{id, presetName}` — そのパネルが表示するプリセットを切替

いずれも `config.json` に永続化され、再起動後も保持される。Control API のディスパッチを足しただけの薄い実装で、純粋関数 (`AppConfig.updatingPanelFrame` / `updatingPanelOpacity` / `settingPanelPreset`) は Phase 3 ステージ 2A で導入済みのものを共有。

### 内部リファクタ — PanelManager と reconcile sink

複数 NSWindow を id ベースで管理する `PanelManager` クラスを新設。`AppDelegate` の単数 `panel` / `miniIcon` フィールドを置き換え、`floatingPanelWantsCollapse` 通知の購読も内部に閉じ込めた。

`AppDelegate` は `PresetManager.$appConfig.panels` を Combine sink で監視し、追加/削除を検知すると自動的に `PanelManager.openNew` / `close` を呼ぶ **reconcile** 機構を導入。これにより menu bar・設定画面・Control API のいずれから panel を操作しても NSWindow の生成・破棄が一元化された。

### 機能追加 — `PresetManager.loadedPresets` 複数プリセットキャッシュ

`@Published var loadedPresets: [String: Preset]` を追加し、複数パネルがそれぞれ別のプリセットを表示しても全パネルが reactive に再描画される。`preset(named:)` がディスクから読み込みつつキャッシュし、`panelPreset(forPanelID:)` が convenience getter として動く。

`switchPanelPreset(panelID:to:)` で指定パネルだけプリセットを切り替えられる。プライマリパネルを切り替えた場合は legacy `activePreset` と編集ターゲット `currentPreset` も自動同期。

## v0.11.0 (2026-05-04)

ビジュアル拡張ロードマップ **Phase 2 — 表現力の拡張**。「アイコンのパネル」から「用途別パネル」に進化させるための土台として、グループ単位の表示タイプ切替・サムネイル・状態フィードバックを追加した。詳細は [docs/plans/visual-expansion-roadmap.md](docs/plans/visual-expansion-roadmap.md) の Phase 2 章。

### 機能追加 — グループの表示タイプ (icon / wide / card)

`ButtonGroup.displayType` を新設し、グループ単位でボタンの描画スタイルを 3 種類から選べるようになった。

- **icon (既定)**: 既存の小型アイコン+ラベル。コンパクト用途・既定の挙動を維持
- **wide**: 全幅・大きめアイコン+ラベル中心の横長セル。長いタイトルや視認性重視のボタンに
- **card**: サムネイル + タイトルを 2 列のグリッドに配置。プロンプトギャラリー (Midjourney 等) 向け

設定画面のグループ編集タブに表示タイプの segmented picker を追加。Control API では `group_add` / `group_update` の `displayType` フィールドで制御可能。後方互換のため、フィールドが欠落している既存プリセット JSON は自動的に `icon` でロードされ、エンコード時にも `displayType=icon` はファイルに書き出さない。

### 機能追加 — サムネイル画像 (`ButtonDefinition.thumbnail`)

card タイプで使う大判画像を保持する `thumbnail` フィールドを追加。設定画面のボタン編集タブに「サムネイル」入力 + ファイル参照 + プレビュー枠を新設。`presets/<name>/images/<button-id>.{ext}` への保存規約を `IconAssetSaver.saveThumbnail` / `imagesDirectory(presetName:)` で提供する。Phase 4 (AI 画像生成) もこのパスに書き出す前提。

### UI 改善 — 編集ウィンドウのアイコン / サムネイル欄を DnD 枠に刷新

ボタン / グループ編集タブの「アイコン」「サムネイル」入力を、テキストパス入力欄から **ビジュアルな DnD 枠** (`ImageDropZone`) に置き換えた。中身が空のときは点線枠+SF Symbol+ガイダンス、画像 / 絵文字があればプレビュー、ドラッグオーバー中はアクセントカラー枠で feedback。クリックすると `NSOpenPanel` が立ち上がるので、キーボード派・DnD を使えないユーザーにもフォールバックがある。

### UI 改善 — アプリアイコンピッカーをハードコード撤廃 + Launchpad 風に統一

設定画面からアプリアイコンを選ぶシート (`AppIconPicker`) を全面書き換え。旧実装は `AppIconCatalog` の **ハードコードした bundle id リスト + 4 ジャンル分類** だったため、リストにないアプリは候補に出てこなかった。新実装は `FileSystemAppListProvider` でインストール済み `.app` を再帰列挙し、`AppLauncherPickerSheet` と同じ Launchpad 風グリッド (`AppGridCell` を共有) で表示。Bundle ID 検索もそのまま動く。`AppIconCatalog.swift` は撤廃。

### 機能追加 — seed プリセット「MidJourney プロンプトギャラリー」

card 表示タイプ + `text` action の `appendMode` を組み合わせた使用例として `midjourney-gallery` を seed 同梱。「画風 → ポーズ → 服装 → 背景」の順にカードを押すとクリップボードに断片が連結されていき、最後に Discord で `Cmd+V` する流れを示す。サムネイル未設定でも絵文字フォールバックで動く。

### 文言整理 — seed プリセット「♿ アクセシビリティ」を「⏻ 電源・ロック」にリネーム

「アクセシビリティ」というラベルは、当事者(視線入力 / Switch Control ユーザー等)にも非当事者にも意図が伝わりづらく、絵文字 ♿ から「色覚・弱視向けの配色プリセット」と誤読される副作用もあった。中身(画面ロック / スリープ / 再起動 / 強制終了 等) から想像できる名前 `⏻ 電源・ロック` に変更し、対象ユーザーの説明はプリセット memo の冒頭に残した。内部 `name` (= ファイル名) は `accessibility` のまま据え置き、既存ユーザーの編集を尊重する。

### 機能追加 — 状態反映インジケーター

ボタン押下時の枠線色アニメーション (実行中=黄、成功=緑 1 秒) を追加。アクションが現状 fire-and-forget なので「押された＝成功扱い」の軽量実装で、失敗 (赤) 表示は将来 `executeButton` の戻り値を整理してから配線する。確認ダイアログ経由でも feedback が起きる。

### バグ修正 — `applyPatch` で confirm / thumbnail を素通し

設定画面の「実行前の確認」トグルが保存されない既存バグ (`applyPatch` が confirm 系を `updateButton` に渡していなかった) を修正。Phase 2 で増えた `thumbnail` も同じ経路で素通しするように整備した。

### Control API 変更

- `group_add` / `group_update`: `displayType` (`icon` | `wide` | `card`) を受け付け
- `button_add` / `button_update`: `thumbnail` (絶対パスまたは相対パス、null で消去) を受け付け
- 既存ツールの後方互換は維持。フィールド未指定時の挙動は従来通り

### バージョン

Info.plist `CFBundleShortVersionString` を `0.11.0`、`CFBundleVersion` を `19` に更新。`SystemPrompt.version` も同期。Tests 317 件全合格。

## v0.10.6 (2026-05-04)

v0.10.5 で導入したアプリピッカーの UI 仕上げと、内部テストの安定化。機能面の追加はなく、見た目と裏方の調整のみ。

### UI 改善 — アプリピッカーを Launchpad 風グリッドに刷新

「アプリから追加…」シートを **リスト + 右側プレビュー欄** から **Launchpad 風の格子表示** に再構成。各セルにアイコンとアプリ名が並び、シングルクリックで選択、ダブルクリック (または「追加」ボタン) で即追加。選択中アプリの bundle id は下部 footer にコンパクトに表示し、独立プレビュー欄は撤廃した。

- セルサイズ 96px、`LazyVGrid` で 8〜9 列の表示。シートサイズは 640×500 → 880×620 に拡大
- `LazyVGrid` のため画面外セルはアイコン抽出を走らせない (起動時 prewarm キャッシュ前提の設計)
- 各セルの async loadIcon は v0.10.5 で導入したカスケード (キャッシュ → ImageIO → NSWorkspace) と `IconContentValidator` をそのまま流用

### バグ修正 — AppIconCache の mtime 比較を tolerance 込みに

`setAttributes(.modificationDate:)` で書き込んだ mtime を `attributesOfItem` で読み戻すと、APFS の sub-second 精度切り捨てや時計のジッタで nanosecond オーダーの誤差が出る。素朴な `cached >= app` 比較ではこの誤差で「アプリが更新された」と誤判定してキャッシュを無効化してしまい、`testDiskCachePromotesToMemoryAcrossInstances` が flaky になっていた。`mtimeStillValid(cached:app:)` で 1.0 秒以内の差は同世代として扱うように `get()` / `contains()` を修正。

### テスト修正 — ConfigIOTests のデフォルトプリセット期待値を更新

`testWriteDefaultConfigCreatesConfigAndDefaultPreset` の期待ボタン id が古いままだったので最新のデフォルトプリセット (`btn-ai-copy-prompt` 先頭) に合わせた。

### バージョン

Info.plist `CFBundleShortVersionString` を `0.10.6`、`CFBundleVersion` を `18` に更新。`SystemPrompt.version` も同期。

## v0.10.5 (2026-05-03)

ビジュアル拡張ロードマップ Phase 1.5。Phase 1 で発見した「AppKit 依存コードがテスト不能」という壁の解消と、DnD のみだったアプリ追加導線への補完。詳細は [docs/plans/visual-expansion-roadmap.md](docs/plans/visual-expansion-roadmap.md) の Phase 1.5 章。

### 機能追加 — 設定画面に「アプリから追加…」ピッカー

ボタン編集タブの「ボタン追加」隣に **「アプリから追加…」** ボタンを新設。`/Applications` / `/System/Applications` / `~/Applications` 配下の `.app` を一覧から検索 → 選択 → 起動ボタンとして即追加できる、DnD と並列の追加導線。キーボード操作だけで完結するため、マウスドラッグが負担になるユーザーへの代替手段にもなる。

- 検索対象はアプリ名と Bundle ID の両方 (substring、大文字小文字無視)
- 選択中アプリのアイコンを async で抽出してプレビュー表示 (UI スレッドをブロックしない)
- ダブルクリック / Enter で即追加。複数 root に同 Bundle ID の `.app` がある場合は最初に見つけたものを残す (`Applications` → `System/Applications` → `~/Applications` の順)
- DnD とまったく同じ Core ロジック (`AppEntryResolver` + `IconAssetSaver`) を共有、追加されるボタンは `launch` action で bundle id を target に持つ

### アーキテクチャ — アイコン抽出のカスケード設計

アプリアイコン抽出を 2 系統のカスケードで構成：

1. **ImageIO で `.icns` 直読み** (Foundation のみ、ms オーダー、AppKit 非依存) — 伝統的なアプリ (Calculator・Slack・VS Code 等) を高速にカバー
2. **`NSWorkspace.shared.icon(forFile:)`** (AppKit、コミュニティ標準) — UTM (Assets.car-only) や Books (空 .icns プレースホルダ) のような Catalyst / モダンアプリを救済

両方が同じ位置づけの主要パスで、上の経路で取れたら使い、ダメなら下に降りる。背景にあるのは「グラフィック / Quick Look 系の OS API は変動しやすいが、`ImageIO` / `CoreGraphics` / `NSWorkspace.icon` のような長寿命 API は安定している」という設計原則 (詳細はメモリ `feedback_prefer_foundation_over_gui_apis`)。NSWorkspace は AppKit 依存だが macOS 10.0 以来の安定 API で、コミュニティでも `NSWorkspace.icon(forFile:)` が標準 (orchetect の Gist 等)。

- 当初検討した `qlmanage` 経由は **Calculator.app に対して 20 秒 hang する致命的挙動** を `scripts/spikes/qlmanage-pipe-spike/` で確認 (Quick Look daemon の問題、daemon 再起動でも改善せず) → 採用却下
- ImageIO は Calculator / Slack / VS Code を 3〜9ms で取得、Foundation のみ
- NSWorkspace は AppKit 依存だが UI 層 (`FloatingMacroApp/Settings/NSWorkspaceIconFallback.swift`) に閉じ込めて Core の純粋性は維持
- async 版 (`Task.detached` + `Task.checkCancellation`) も併設、UI が止まらない
- `PanelDropHandler` (DnD 受け取り) を Core ロジックに乗せ替え、残る AppKit 依存は NSAlert の確認ダイアログのみ — Phase 1 の P1-12「DnD ボタン化の E2E テスト不能」問題を解消

### 機能追加 — 内容検査と自動修復ループ

Books.app のように `.icns` ファイル自体は存在するが **全 representation が完全透明 (`alpha=0`, `RGB=0`)** の空プレースホルダになっているケースが現実に存在する (Apple が Catalyst 化のときに残した抜け殻)。ImageIO はこれを「成功」として 460 バイトの空 PNG を返してしまうため、PNG バイトサイズだけでは判別できない。**ピクセル単位で実内容があるかを検査**する `IconContentValidator` を Core に新設し、抽出経路の各段に組み込んだ:

- `IconContentValidator.hasMeaningfulContent(pngData:)` — `CGImageSource` で decode → RGBA 8bit 配列に展開 → 1 ピクセルでも `alpha > 8` または `max(R,G,B) > 8` を見つけたら早期 return で true。通常アイコンは数 px の loop で抜けるので軽い
- 自動修復ループ: `AppIconPrewarmer` が「既存キャッシュ → ImageIO → NSWorkspace」のカスケードを毎段で validator にかける。空 PNG (薄い `.icns` 由来) はキャッシュにあっても validator が reject → 次段に降りる → NSWorkspace で正しいアイコンを取って上書き
- 起動時 prewarm の優先度を `.background` → `.utility` に上げて、起動から 30〜60 秒以内に prewarm が完走するように調整。実機検証で Books が `460 バイト → 337 KB` に self-heal するのを確認

### 機能追加 — アイコンキャッシュとバックグラウンドプリキャッシング

Finder / Dock / Launchpad と同様、アプリアイコンの取得を **二段キャッシュ (memory + disk)** で覆い、起動時にバックグラウンドで `/Applications` 全アプリのアイコンを事前抽出する。これでアプリピッカーや DnD でアプリを追加するときに「選んだ瞬間」アイコンが表示される。

- ディスクキャッシュ: `~/Library/Caches/FloatingMacro/AppIcons/<bundleId>.png`、ファイル mtime をアプリの mtime に揃えて保存。アプリが更新されたら自動的に再抽出
- メモリキャッシュ: actor で thread-safe、複数の Picker / DnD 同時操作でも整合性が保たれる
- バックグラウンドプリキャッシング: `applicationDidFinishLaunching` から `Task.detached(priority: .background)` で起動。並列度 4、UI を邪魔しない
- カスケード: ImageIO (Foundation, ms オーダー) → NSWorkspace (AppKit, Assets.car-only アプリ救済) の順に試行し、取れたものをキャッシュに保存
- AppLauncherPickerSheet・PanelDropHandler 双方がキャッシュ参照に乗ったので、選択時はディスクキャッシュヒットで即表示・即追加が成立

### 機能追加 — UTM 等 Assets.car-only モダンアプリ対応

UTM のような SwiftUI 製のモダンアプリは `Contents/Resources/` に `.icns` を持たず `Assets.car` のみで配布されている。ImageIO 直読みでは取れないため、**`NSWorkspace.shared.icon(forFile:)` フォールバック**を UI 層 (`FloatingMacroApp`) に追加。NSWorkspace は Apple 公式の長寿命 API (10.0 以来) で Assets.car も内部的に解決する。Core は Foundation + ImageIO のみのまま、AppKit 依存は UI 層に閉じている。

### Core 新設

- `FloatingMacroCore/Icons/ImageIOIconExtractor.swift` — `.icns` 直読みでアプリアイコンを PNG 化 (sync + async)
- `FloatingMacroCore/Apps/AppEntry.swift` — アプリ情報の純粋データ (URL / displayName / bundleIdentifier)
- `FloatingMacroCore/Apps/AppEntryResolver.swift` — `.app` URL → `AppEntry` (Info.plist 直読み、`Bundle(url:)` 不使用で軽量)
- `FloatingMacroCore/Apps/AppListProvider.swift` — `/Applications` 等の列挙、Bundle ID dedup、displayName ソート
- `FloatingMacroCore/Apps/AppDropClassifier.swift` — DnD URL の判別 (`.app` / file / folder)、AppEntryResolver と連携
- `FloatingMacroCore/Apps/IconAssetSaver.swift` — preset 配下に PNG 保存と保存先パス算出。テスト時は `applicationSupportDirectory:` 上書きで一時ディレクトリに書ける
- `FloatingMacroCore/Apps/AppIconCache.swift` — actor ベースの memory + disk 二段キャッシュ。アプリ mtime 比較でキャッシュ無効化、`contains()` で軽量ヒット判定
- `FloatingMacroCore/Apps/AppIconPrewarmer.swift` — 並列 prewarm 実装。各段で `IconContentValidator` を通して「内容あるアイコン」だけキャッシュに入れる自動修復ループ。NSWorkspace fallback は closure で受け取って Core に AppKit を持ち込まない設計
- `FloatingMacroCore/Icons/IconContentValidator.swift` — PNG bytes / CGImage の中身検査 (alpha・RGB のピクセル走査、早期 return で軽量)

### App 層に新設

- `FloatingMacroApp/Settings/NSWorkspaceIconFallback.swift` — Assets.car-only アプリ救済用、AppKit 依存はここに閉じる
- `FloatingMacroApp/Settings/AppLauncherPickerSheet.swift` — アプリ選択ピッカー UI (検索・async プレビュー・キャッシュ参照)

### テストカバレッジ

Phase 1.5 全体で **46 件の単体テスト** を `FloatingMacroCoreTests` に追加 (ImageIO 5・AppEntryResolver 7・FileSystemAppListProvider 7・AppDropClassifier 6・IconAssetSaver 4・AppIconCache 6・AppIconPrewarmer 3・IconContentValidator 8)。フィクスチャ用 stub `.app` をテスト内で動的生成し、実環境の Calculator.app / Slack.app / Books.app は XCTSkip でフォールバック。Books の空 `.icns` プレースホルダを validator が reject するケースも実環境テストでカバー。

### 検証スパイク

`scripts/spikes/qlmanage-pipe-spike/` を新設。qlmanage 経由 4 パターン (anti-pattern / null device / readabilityHandler / background readToEnd) と ImageIO 直読みパターンの挙動比較。将来「やはり qlmanage を使えないか」と再検討する時の参照用に残置。

### バージョン

Info.plist `CFBundleShortVersionString` を `0.10.5`、`CFBundleVersion` を `17` に更新。`SystemPrompt.version` も同期。

## v0.10.0 (2026-05-03)

ビジュアル拡張ロードマップ Phase 1。Stream Deck / プロンプトギャラリー / マルチデバイス対応を見据えた段階的拡張の最初の一歩。詳細は [docs/plans/visual-expansion-roadmap.md](docs/plans/visual-expansion-roadmap.md)。

### 機能追加 — text アクションの「追記モード（プロンプトビルダー）」

`Action.text` に `appendMode: Bool` を追加。ON のとき、ボタンを押すとペーストせず、`content` を**現在のクリップボード末尾に連結**するだけの挙動になる。Midjourney のように画風・ポーズ・服装などの**プロンプト断片**を複数のボタンに分けて持っておき、必要な組み合わせをクリックで積み上げて、最後に自分で Cmd+V で貼り付ける用途を想定。

- ボタン編集パネルの「貼り付けテキスト」直下に **「追記モード（プロンプトビルダー）」** チェックボックスを新設
- 追記モードでは `restoreClipboard` フラグは無視される（連結状態を持続させるため）
- セパレータは入れない仕様（`", "` などは content に含めて制御してもらう。Midjourney は comma 区切り、自由文は空白、など用途で異なるため）
- Control API: `text` アクションの inputSchema に `appendMode` を追加。AI からも `button_add` 経由で 1 リクエストで設定可能
- データ後方互換: 既存プリセット JSON は `appendMode` キーが欠落していてもそのまま読み込める（デフォルト false）。保存時は `appendMode=false` のとき JSON にキー自体を出力しない

### 機能追加 — フローティングパネルへのドラッグ&ドロップでボタン作成

Finder からアプリ (`.app`) やファイル / フォルダをフローティングパネルに**ドロップするだけで起動ボタンが自動生成**される。Stream Deck 同等の入門ハードルを目指す改善。

- `.app` を落とす → bundle id を解決した `launch` アクションのボタンが生成される。ラベルはアプリ名、tooltip は `アプリ名 (com.example.bundleid)`
- ファイル / フォルダを落とす → 絶対パスを保持した `launch` アクションのボタンが生成される。ラベルはファイル名
- アイコンは `NSWorkspace.icon(forFile:)` で自動抽出し、64×64 PNG として `~/Library/Application Support/FloatingMacro/presets/<name>/icons/<button-id>.png` に保存。失敗してもボタン作成は継続（絵文字 fallback）
- 確認ダイアログで「グループ「○○」に N 個追加します」を表示してから一括登録
- 追加先は現在のプリセットの最初のグループ。グループが無ければ「ランチャー」グループを自動作成
- 複数アイテムの同時ドロップに対応
- ドラッグ中はパネル全面に **アクセントカラーの太枠** が出る視覚フィードバック付き

### バージョン

Info.plist `CFBundleShortVersionString` を `0.10.0`、`CFBundleVersion` を `16` に更新。`SystemPrompt.version` も同期。

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
