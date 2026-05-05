# FloatingMacro ビジュアル拡張ロードマップ

最終更新: 2026-05-03
状態: **Phase 1 完了 (v0.10.0) / Phase 1.5 着手中 (v0.10.5 予定)**

---

## 0. このドキュメントの位置づけ

FloatingMacro は現状 **「絵文字+テキストラベルの小さなボタンを並べたフローティングパネル」** という形で完成している。本ロードマップは、その完成形の上に **Stream Deck 競合領域 + プロンプトギャラリー + マルチデバイス（スマホ/タブレット）** という三方向の拡張を、既存コードに無理を強いない順番で段階的に積む計画である。

**最終ゴール（一文で）**

> Stream Deck よりも柔軟で、Quadro / Touch Portal よりも導入が簡単で、AI プロンプト管理にも使える、無料 OSS のフローティングコントロールパネル。

**設計上の最重要原則**

- 既存の Preset / ButtonGroup / ButtonDefinition のスキーマを **後方互換のまま** 拡張する（新フィールドは optional + デフォルト値）。
- 既存の Control API ツール（`button_add` など）は壊さない。新機能は新しいツールとして追加する。
- 各 Phase は単独でリリース可能。途中で止めても破綻しない。

---

## 1. ライバル分析（要約）

| カテゴリ | 代表 | 強み | FloatingMacro の差別化余地 |
|---|---|---|---|
| ハードボタン | Stream Deck | 美しいアイコン、豊富なエコシステム | ハード不要、無料、複数パネル同時 |
| ソフトボタン | Touch Portal, Quadro | スマホ/タブレットを使える | QR ワンタップ接続、無料 OSS |
| Mac マクロ | Keyboard Maestro, BTT | 強力なマクロ言語、Mac 統合 | フローティング常駐、AI プロンプト前提 |
| ランチャー | Raycast, Alfred | 高速起動、AI 拡張 | パネル常駐、視覚的なボタン配置 |
| プロンプト管理 | （ほぼ空白） | — | **画像サムネイル付き断片合成は独自領域** |

最大の競合は **Stream Deck（ソフト単体モード）**。最大の差別化は **プロンプトギャラリー（カードタイプ）+ マルチパネル + Web/QR 配信**。

---

## 2. 機能カタログ（実装単位）

| ID | 機能 | 既存への影響 | 難易度 |
|---|---|---|---|
| F1 | アイコン画像（PNG/JPEG）対応 UI | 既に内部実装あり、UI 追加のみ | 低 |
| F2 | SF Symbols ピッカー内蔵 | UI 追加のみ | 低 |
| F3 | ドラッグ&ドロップでボタン作成 | パネル/設定画面に DnD ハンドラ追加 | 低 |
| F4 | `text` action の append モード | Action スキーマ拡張 | 低 |
| F5 | ボタン表示タイプ（icon / wide / card） | `ButtonGroup.displayType` を追加 | 中 |
| F6 | カード用サムネイル画像保存パス | Preset 配下に `images/` 規約追加 | 低 |
| F7 | 状態反映アイコン（実行中/成功/失敗） | レンダラー + アクション結果連携 | 中 |
| F8 | Panel 概念導入（複数フローティング） | `AppConfig` の単一 window → 複数 panel | 高 |
| F9 | プリセット切替 UI を Panel リストに変更 | UI 大改修 | 中 |
| F10 | AI 画像生成（BYOK） | API クライアント + 鍵管理 | 中 |
| F11 | LAN バインドモード（明示トグル） | Control API ネットワーク設定 | 中 |
| F12 | Web Panel レンダラー（HTML/CSS/JS） | 静的アセット + API ルート | 中 |
| F13 | QR コード発行 + 短期トークン | 認証拡張 + UI | 低 |
| F14 | mDNS / Bonjour 広報 | NetService 統合 | 低 |

---

## 3. データモデルの段階的拡張

### 3.1 ButtonDefinition への追加（Phase 1〜2）

```swift
public struct ButtonDefinition {
    // 既存フィールドは無変更

    /// カードタイプで表示するときのサムネイル画像パス（preset 相対 or 絶対）。
    /// nil なら icon / iconText にフォールバック。
    public var thumbnail: String?

    /// 生成元プロンプト（記録用）。AI 生成アイコン/サムネイルで「これ何で作ったか」を保存する。
    public var generationPrompt: String?
}
```

`Action` 側：

```swift
public enum Action {
    case text(content: String,
              pasteDelayMs: Int = 100,
              restoreClipboard: Bool = true,
              appendMode: Bool = false)   // 新規。true なら既存クリップボードに追記
    // 他は無変更
}
```

### 3.2 ButtonGroup への追加（Phase 2）

```swift
public struct ButtonGroup {
    // 既存フィールドは無変更

    /// グループ内のボタンをどう描画するか。デフォルト .icon は既存挙動。
    public var displayType: GroupDisplayType = .icon
}

public enum GroupDisplayType: String, Codable {
    case icon    // 現状の小アイコン（正方形・絵文字 or 画像）
    case wide    // 横長（ラベル中心、長文タイトル可）
    case card    // 大カード（サムネイル + タイトル）
}
```

### 3.3 AppConfig の Panel 化（Phase 3）

```swift
public struct PanelConfig: Codable, Equatable {
    public let id: String
    public var presetName: String           // 表示するプリセット
    public var window: WindowConfig         // 既存の WindowConfig をそのまま流用
    public var minimizedToEdge: Bool        // 縁にドック
    public var visible: Bool
}

public struct AppConfig {
    // 既存:
    // public var activePreset: String
    // public var window: WindowConfig

    /// v2: 複数パネル対応。空配列なら旧 window + activePreset から自動移行。
    public var panels: [PanelConfig] = []
}
```

**移行戦略**：起動時に `panels` が空なら `[PanelConfig(id: UUID, presetName: activePreset, window: window, ...)]` を1つ作って書き戻す。旧フィールドは数バージョン残してから削除。

### 3.4 ControlAPIConfig 拡張（Phase 5）

```swift
public struct ControlAPIConfig {
    // 既存無変更

    /// LAN 公開モード。true で 0.0.0.0 にもバインドし、Web Panel へのアクセスを許可。
    public var lanExposureEnabled: Bool = false

    /// LAN 公開時に有効な短期トークン（QR に埋め込む値）。再起動で失効。
    public var ephemeralLanToken: String? = nil

    /// mDNS で広報する名前。デフォルトはホスト名から生成。
    public var bonjourName: String? = nil
}
```

---

## 4. 段階的リリース計画

各 Phase は **独立してリリース可能**。前 Phase が無くても次 Phase に進める設計だが、推奨順は依存関係に従う。

### Phase 1：見た目の足場（v0.10）

**目的**：Stream Deck に対するアイコン品質ギャップを埋める。リスク最小、効果大。

- F1: アイコン画像（PNG/JPEG）UI ピッカー
- F2: SF Symbols ピッカー
- F3: ドラッグ&ドロップでボタン作成（アプリ/ファイル/URL）
- F4: `text` action の append モード

**理由**：すべて既存スキーマを壊さず、独立実装できる。F1 と F4 は内部実装は既にある（UI の問題）。F3 はパネルへのファイル DnD イベントを拾うだけ。

**完了条件**：

- 設定画面のアイコン欄に「画像を選択 / SF Symbol を選択 / 絵文字」の3タブが出る
- パネルにアプリをドロップ → 確認ダイアログ → ボタン化
- text 系ボタンに「追記モード」チェックボックスが出る、押すごとに連結される

### Phase 1.5：アイコン抽出基盤と App Picker（v0.10.5）

**目的**：Phase 1 で発見した「AppKit 依存コードがテスト不能」という壁の回収と、DnD のみだったアプリ追加導線への補完。Phase 2 (表現力拡張) の前段として、以降の機能追加が常に「ロジックは Core / 依存は App」のパターンに乗るための足場を整える。

**新方針の柱**：

- アイコン抽出を `NSWorkspace.icon`（AppKit）ではなく **`qlmanage` + `ImageIO` + `CoreImage`** で行う → `FloatingMacroCore` に置けて全工程が単体テスト可能。Assets.car しか持たないモダンアプリ (SwiftUI 製等) も Quick Look daemon が裏でレンダリングするので全 .app に対応
- `PanelDropHandler` の classify ロジックを Core に切り出し、新基盤と共有 → P1-12 の壁が消え、ロジック側のテストカバレッジが取れる
- 「アプリから追加…」ピッカー UI を Settings に新設 → DnD と並列の導線。キーボード派・身体的にマウスドラッグが難しいユーザーへの代替手段
- 背景色の後処理 (白固定 / 透過 / カスタム色) を CoreImage で行う → ユーザーの好みに合わせたアイコン仕上げ

**完了条件**：

- アプリのアイコンが AppKit 依存なしで PNG として取れる（traditional .icns 持ちアプリも、Assets.car のみのモダンアプリも両対応）
- アプリピッカーで `/Applications` 配下から検索 → 選択 → ボタン化が可能
- 既存の DnD 経路も同じ基盤に乗っており、`PanelDropHandler` 内の純粋ロジックが単体テスト可能（P1-12 の壁解消）
- アイコン背景の後処理オプション（少なくとも白固定 / 透過）が Settings から選べる

### Phase 2：表現力の拡張（v0.11）

**目的**：「アイコンのパネル」から「**用途別パネル**」に進化。プロンプトギャラリーが成立する最小形。

- F5: `ButtonGroup.displayType`（icon / wide / card）
- F6: サムネイル画像の保存規約（`presets/<name>/images/<button-id>.{png,jpg}`）
- F7: 状態反映アイコン（実行中/成功/失敗の枠線色変化、軽量実装）

**理由**：Phase 1 で画像が貼れるようになっているので、`displayType: card` が初めて意味を持つ。F7 は AI 連携の差別化で、軽量に始める。

**完了条件**：

- 設定画面でグループの表示タイプを切り替えられる
- card タイプではサムネイル + タイトル が大きく表示される
- ボタン押下中は枠線が黄色、成功で緑1秒、失敗で赤1秒

### Phase 3：マルチパネル（v0.12）

**目的**：「1つのフローティング」を「**用途別に独立した複数のフローティング**」に拡張。Stream Deck 1台では物理的にできない領域。

- F8: `PanelConfig` 導入、`AppConfig.panels` への移行
- F9: メニューバーから Panel リスト（show/hide/close/add）
- 起動時の状態復元（前回開いていた Panel 群を全部出す）
- 「縁にドック（最小化）」の挙動

**理由**：データモデル変更は大きいが、移行スクリプトで旧 → 新を自動変換できる。複数パネルが動き出すと Phase 2 のカードタイプの存在意義が一気に高まる（用途別に窓を分けられるので）。

**完了条件**：

- メニューバーから 2 つ以上のパネルを同時に出せる
- 各パネルは独立に位置・サイズ・常駐・透明度を持つ
- 旧設定ファイル（v1）から自動移行できる
- Control API に `panel_create` `panel_close` `panel_show` `panel_list` を追加

### Phase 4：AI 連携（v0.13）— オプション機能

**目的**：アイコン/サムネイルを自分で描けない人のための補助。**BYOK 必須**（配布物に AI を内蔵しない方針を堅守）。

- F10: AI 画像生成プロバイダー抽象化
  - 対応候補: Recraft（ベクター強い）, OpenAI gpt-image-1, Google Imagen, Replicate（SD 系）
  - 鍵は Keychain に保存
- ボタン編集画面に「アイコン生成」「サムネイル生成」欄
- 生成履歴の保持（同じプロンプトで再生成、別ボタンに流用）

**完了条件**：

- 鍵を入れていないユーザーには UI が出ない（誤って課金トリガーを踏ませない）
- 生成画像はそのままボタンに採用 + Preset の `images/` に保存
- `generationPrompt` フィールドにプロンプトを記録

### Phase 5：マルチデバイス（v0.14）

**目的**：Stream Deck ハードを買う代替として、スマホ/タブレットを QR ワンタップで操作端末化する。

- F11: LAN バインドモード（明示トグル、デフォルト OFF）
- F12: Web Panel レンダラー（静的 HTML+CSS+JS、アプリにバンドル）
- F13: QR コード発行 + 短期トークン
- F14: mDNS 広報（オプション）

**セキュリティ要件**：

- LAN 公開はデフォルト OFF、有効化はメニューバーから明示操作
- 公開中はメニューバーアイコンが赤くなる（視覚警告）
- QR トークンは再起動で失効、再発行ボタンで手動更新可
- Bearer トークンは既存の Control API 認証を流用
- HTTPS は使わない（自己署名証明書の iOS 警告がユーザビリティを破壊する）。LAN + 短期トークン + ユーザー操作で公開、で割り切る
- Web Panel から呼べる API は `tools/call` の安全サブセットに限定（`config_save` など破壊的操作は除外）

**完了条件**：

- メニューバー「📱 デバイスに送信」→ QR モーダル → iPhone でカメラ起動 → Safari でパネル表示 → タップで Mac 側のアクション実行
- LAN 公開中は明確に視認できる
- mDNS で `floatingmacro.local` がブラウザから到達可能

---

## 5. 完成像（Phase 5 まで揃ったとき）

ユーザー「FM」さんの一日：

- 朝、Mac を立ち上げると小さな**アプリランチャーパネル**（icon タイプ）が右下に常駐。
- イラスト制作を始めるとき、メニューバーから「**Midjourney ギャラリー**」パネル（card タイプ）を呼び出す。サムネイル付きで画風・ポーズ・服装・背景の断片が並ぶ。
- 必要な断片をクリックしていく → text append モードで連結された最終プロンプトが Discord にペーストされる。
- 寝室で続きをやりたくなったら、メニューバーの「📱 デバイスに送信」で QR を出して iPad で読む。iPad の Safari にカードギャラリーが表示され、タップで Mac 側の Discord にプロンプトが送られる。
- たまに新しい画風をボタン化したくなったら、「アイコン生成」欄に「water color, soft pastel」と入れて Recraft で生成 → そのままサムネイルに採用。

---

## 6. タスクリスト（Phase 順、実装単位）

### Phase 1 — 見た目の足場 ✅ 完了 (v0.10.0, 2026-05-03)

- [x] **P1-1** `IconPicker` コンポーネント新設：3タブ（画像 / SF Symbol / 絵文字） — [AppIconPicker.swift](../../Sources/FloatingMacroApp/Settings/AppIconPicker.swift) / [SFSymbolPicker.swift](../../Sources/FloatingMacroApp/Settings/SFSymbolPicker.swift)
- [x] **P1-2** SF Symbols 一覧データの埋め込み（よく使う 200〜500 個に絞る） — [SFSymbolCatalog.swift](../../Sources/FloatingMacroCore/Icons/SFSymbolCatalog.swift)
- [x] **P1-3** SF Symbols ピッカーの検索フィールド + プレビュー
- [x] **P1-4** 画像選択時のコピー先決定（preset 配下に `icons/` を作る or 絶対パス保持の選択）
- [x] **P1-5** `ButtonView` で `icon` がファイルパスのとき `IconLoader` 経由で表示（既存）
- [x] **P1-6** パネルへのファイル DnD ハンドラ：`.app` `.url` `.txt` `.png` を判別 — [PanelDropHandler.swift](../../Sources/FloatingMacroApp/PanelDropHandler.swift)
- [x] **P1-7** DnD で受けたアイテムをボタン化する確認ダイアログ
- [x] **P1-8** `Action.text` に `appendMode: Bool` を追加（後方互換 decoder）
- [x] **P1-9** append モード時の挙動：既存クリップボード末尾にスペース区切りで追記
- [x] **P1-10** 設定画面の text action フォームに「追記モード」チェックボックス
- [x] **P1-11** Tests: append モード単体テスト（既存クリップボード保持・追記挙動）
- [x] ~~**P1-12** Tests: ファイル DnD でボタン化される E2E（`scripts/text_inject_e2e.sh` 流儀）~~ → **方針変更により Phase 1.5 (P1.5-6 / P1.5-9) に置換**。元の方針 (DnD UI 自体を E2E でテスト) は `PanelDropHandler` が AppKit 依存のため断念。代わりに classify と icon 抽出ロジックを Core に切り出して単体テストする方向に変更
- [x] **P1-13** SPEC.md 更新（appendMode の仕様追記、IconPicker 章追加）
- [x] **P1-14** CHANGELOG / Info.plist / version bump

### Phase 1.5 — アイコン抽出基盤と App Picker（本セッションで方針決定）

> 元 P1-12 (DnD E2E) の壁回収を起点に、Phase 2 の前段として「ロジックは Core / 依存は App」のテストパターンを確立する。Phase 1 完了後の追加ブロック。
>
> **方針更新メモ (2026-05-03 検証セッション):**
> 当初は qlmanage を主路線にして「Assets.car のみ持つモダンアプリも全対応」する設計を考えたが、`scripts/spikes/qlmanage-pipe-spike/` で実機検証したところ qlmanage が Calculator.app に対して **20 秒 hang し PNG 0 枚** という致命的挙動を確認 (Quick Look daemon の問題、`pkill quicklookd` でも改善せず)。一方 `/Applications` 配下を調査した範囲では Calculator.app・Slack.app・VS Code.app すべてが従来形式の `AppIcon.icns` を保持しており、**ImageIO 直読みで全アプリ 3〜9ms で PNG 取得成功**を確認。よって以下の通り方針変更：
> - **主路線 = ImageIOIconExtractor** (Foundation + ImageIO のみ、AppKit 依存ゼロ、ms オーダー)
> - **qlmanage 路線は撤退**。hang リスク高すぎる
> - **Compound (二段構え) は当面棚上げ**。実運用で `.icns` 無しのアプリに当たったら、その時 `sips` フォールバックを検討
> - **クラッシュ/ハング隔離**：ImageIO は API 自体が nil 安全 (malformed icns でクラッシュしない) なので、現状は in-process + async Task で十分。CoreImage 後処理を導入する時に「別プロセス化が必要か」を再評価
>
> **方針アップデート (実機検証ラウンド)**:
> 実機で UTM (Assets.car-only) と Books (空 .icns プレースホルダ) という 2 つの「ImageIO 単独では取れないパターン」が判明したため、`NSWorkspace.shared.icon(forFile:)` (AppKit、コミュニティ標準) を **対等な主要パス**として併設。ImageIO の AppKit 非依存・高速性は活かしつつ、`NSWorkspace` の網羅性で穴を埋めるカスケード型に。あわせて `IconContentValidator` でピクセル内容を検査し、空 PNG (Books の icns 由来) は次段に降ろす自動修復ループを構成。AppKit 依存は UI 層 (`FloatingMacroApp/Settings/NSWorkspaceIconFallback.swift`) に閉じ込めて Core の純粋性は維持。
>
> **背景にある一般原則 — 基盤系 API > GUI 系 API**:
> 現代の OS では「GUI / グラフィック系のユーザー体験」がビジネス価値を生む中核なので、毎メジャー更新で挙動が変わる宿命がある (Quick Look / Spotlight のアイコン表示 / Launchpad / Stage Manager / SwiftUI 等)。一方で `ImageIO` / `CoreGraphics` / `FileManager` / `Foundation.PropertyListSerialization` のような **基盤系 API は数十年単位で安定** している (アプリ互換性のため変えられない)。アイコン抽出のような「OS が変わっても同じことができてほしい機能」は、**GUI 寄りの API ではなく基盤レイヤに依存させる**のが長期的な健全性につながる。今回 qlmanage を捨てて ImageIO に寄せたのはこの原則に基づく判断。Phase 2 以降 (CoreImage 後処理 / ScreenCaptureKit / SwiftUI 新 API 等) でも同じ基準で判断する。

- [x] ~~**P1.5-1** `QlmanageIconExtractor` を Core に新設（Process 経由で `qlmanage` 呼び出し、AppKit 依存ゼロ）~~ → **撤退**。検証結果 qlmanage が hang する (上記方針メモ参照)。実装は削除済み、検証コードは [`scripts/spikes/qlmanage-pipe-spike/`](../../scripts/spikes/qlmanage-pipe-spike/) に保存
- [x] **P1.5-2** `ImageIOIconExtractor` で `.icns` 直読み（Foundation + ImageIO のみ、ms オーダーの高速パス、async 版併設） — [ImageIOIconExtractor.swift](../../Sources/FloatingMacroCore/Icons/ImageIOIconExtractor.swift) + [Tests](../../Tests/FloatingMacroCoreTests/ImageIOIconExtractorTests.swift) 完成、5 テスト全合格 (合計 18ms)
- [x] ~~**P1.5-3** `CompoundIconExtractor`（fast → fallback の二段、モダンアプリ (Assets.car のみ) も全対応）~~ → **棚上げ**。`.icns` 無しのアプリに実運用で遭遇したら sips フォールバックを別途検討
- [ ] **P1.5-4** `IconBackgroundProcessor` プロトコル + `WhiteToTransparentProcessor` / `WhiteToColorProcessor`（CoreImage 後処理、AppKit なし） — qlmanage 撤退により「白背景を後処理で透過化」の必要性は低下。ImageIO で取れる icns はもともと透過 PNG を含むケースが多い。優先度を下げて様子見
- [x] **P1.5-5** `AppEntryResolver` / `AppListProvider` を Core に新設 — [AppEntry.swift](../../Sources/FloatingMacroCore/Apps/AppEntry.swift) / [AppEntryResolver.swift](../../Sources/FloatingMacroCore/Apps/AppEntryResolver.swift) / [AppListProvider.swift](../../Sources/FloatingMacroCore/Apps/AppListProvider.swift)。`Bundle(url:)` ではなく Info.plist 直読みで bundle id 抽出、search root 重複排除、displayName ソート
- [x] **P1.5-6** `PanelDropHandler` の classify を Core (`AppDropClassifier` + `IconAssetSaver` + `ImageIOIconExtractor`) に乗せ替え — **P1-12 の壁を解消**。[PanelDropHandler.swift](../../Sources/FloatingMacroApp/PanelDropHandler.swift) に残る AppKit 依存は NSAlert の確認ダイアログのみ。判別・bundle id 解決・アイコン抽出・保存パス算出はすべて Core 側で単体テスト可能 ([AppDropClassifier.swift](../../Sources/FloatingMacroCore/Apps/AppDropClassifier.swift) + [IconAssetSaver.swift](../../Sources/FloatingMacroCore/Apps/IconAssetSaver.swift), 10 テスト合格)
- [x] **P1.5-7** Settings の「ボタン追加」隣に「**アプリから追加…**」ボタンを新設、専用シート ([AppLauncherPickerSheet.swift](../../Sources/FloatingMacroApp/Settings/AppLauncherPickerSheet.swift)) を実装。検索 (アプリ名 / bundle id)、選択中のアイコンプレビュー (ImageIO の async API 経由)、ダブルクリック / Enter で即追加。Core ロジック (`FileSystemAppListProvider` + `ImageIOIconExtractor` + `IconAssetSaver`) を再利用。実機動作確認は v0.10.5 bump 前にユーザー検証
- [ ] ~~**P1.5-8** Settings に「アイコン背景処理」設定を追加~~ → **P1.5-4 と同根拠で当面棚上げ**
- [x] **P1.5-9** Tests: `/System/Applications/Calculator.app` + `/Applications/Slack.app` + 自作 stub `.app`（icns 無し）で `ImageIOIconExtractor` の単体テスト (sync + async)
- [x] **P1.5-10** Tests: `AppEntryResolver` (7 ケース) と `FileSystemAppListProvider` (7 ケース)。stub `.app` を `Tests/.../*Tests.swift` 内で動的に生成して dedup・ソート・hidden skip・bundle id fallback を検証
- [ ] ~~**P1.5-11** Tests: `IconBackgroundProcessor` の白→透過変換テスト~~ → **P1.5-4 と同根拠で当面棚上げ**
- [x] **P1.5-12** SPEC.md / CHANGELOG / Info.plist / SystemPrompt.swift を v0.10.5 で bump（メモリ `feedback_version_bump_full_sweep` 参照）— ドキュメント更新完了。**実機動作確認はユーザー側で `bash scripts/build-app.sh && bash scripts/rebuild-and-relaunch.sh` 実行後にコミット判断**

---

#### 実機検証で判明した追加項目 (2026-05-03 セッション中)

ユーザーの実機テストで UTM (Assets.car-only モダンアプリ) のアイコンプレビューが空になる問題が発覚。`/Applications` 配下を実調査したところ Phase 1.5 着手時の仮説 (「全アプリが `.icns` を持つ」) が現実に裏切られていた。あわせてユーザーから「アイコン表示はどんな OS でもキャッシュ前提、バックグラウンドで取得しておく」要望。以下を Phase 1.5 内に追加実装:

- [x] **P1.5-13** `NSWorkspaceIconFallback` (App 層) — Assets.car-only アプリ用。`NSWorkspace.shared.icon(forFile:)` 経由で全アプリ確実にカバー。AppKit 依存は UI 層に閉じる ([NSWorkspaceIconFallback.swift](../../Sources/FloatingMacroApp/Settings/NSWorkspaceIconFallback.swift))
- [x] **P1.5-14** `AppIconCache` (Core actor) — memory + disk 二段。`~/Library/Caches/FloatingMacro/AppIcons/<bundleId>.png`、ファイル mtime をアプリ mtime に揃えて自動 invalidation。6 テスト ([AppIconCache.swift](../../Sources/FloatingMacroCore/Apps/AppIconCache.swift) + [AppIconCacheTests.swift](../../Tests/FloatingMacroCoreTests/AppIconCacheTests.swift))
- [x] **P1.5-15** `AppIconPrewarmer` (Core) — `/Applications` 全アプリを並列 prewarm。NSWorkspace fallback は closure で受け取る設計で Core に AppKit を持ち込まない。3 テスト ([AppIconPrewarmer.swift](../../Sources/FloatingMacroCore/Apps/AppIconPrewarmer.swift) + [AppIconPrewarmerTests.swift](../../Tests/FloatingMacroCoreTests/AppIconPrewarmerTests.swift))
- [x] **P1.5-16** `App.swift` の `applicationDidFinishLaunching` から `Task.detached(priority: .background)` で prewarm を起動。並列度 4、size 128 で全アプリのアイコンが裏で取得される
- [x] **P1.5-17** `AppLauncherPickerSheet.commit()` と `PanelDropHandler.handleDroppedURLs` を `async` 化。カスケード: 共有キャッシュ → ImageIO → NSWorkspace fallback。取れたら全部キャッシュに `put()`
- [x] **P1.5-18** Phase 1.5 全体のテスト数を 29 → 38 に増強

#### 実機検証で判明した追加項目 — 第 2 ラウンド (Books の空 .icns プレースホルダ問題)

UTM が NSWorkspace fallback で正しく取れるようになった後、**Books.app は `.icns` ファイル自体は存在するが全 representation が完全透明 (alpha=0, RGB=0) の空プレースホルダ** という別パターンが発覚。ImageIO は「成功」として 460 バイトの空 PNG を返してしまうので、PNG バイトサイズ判定では捕まえられない。`spike` でピクセル走査検査により `Books[0..3] avgAlpha=0.0 avgRGB=0.0` を確認し、ピクセル内容検査と自動修復ループを設計。

- [x] **P1.5-19** `IconContentValidator` (Core) を新設 — PNG bytes / CGImage を decode してピクセル単位で「中身があるか」検査。alpha・RGB のしきい値超過を 1 ピクセルでも見つけたら早期 return で true。`hasMeaningfulContent(pngData:)` と `hasMeaningfulContent(cgImage:)` の 2 オーバーロード ([IconContentValidator.swift](../../Sources/FloatingMacroCore/Icons/IconContentValidator.swift))
- [x] **P1.5-20** `AppIconPrewarmer` を「自動修復ループ」化 — 各段 (既存キャッシュ → ImageIO → NSWorkspace) で `IconContentValidator` を通す。空キャッシュは次段に降りて再抽出 → 上書き。Books の `460 bytes → 337 KB` の self-heal を実機検証で確認
- [x] **P1.5-21** `AppLauncherPickerSheet` と `PanelDropHandler` のカスケードにも validator を組み込み、UI からも内容検査を強制
- [x] **P1.5-22** 起動時 prewarm の優先度を `.background` → `.utility` に上げる — `.background` は OS スロットリングで起動から数十秒以内に完走しないことがあった。`.utility` で 30〜60 秒以内に 175 アプリが揃うように
- [x] **P1.5-23** `IconContentValidatorTests` を 8 ケース追加 (空データ・garbage bytes・全透明 PNG・1px だけ不透明・antialias 残骸 alpha=1・実 Calculator (中身あり)・実 Books (中身なし) を validator が正しく判別)。Phase 1.5 全体のテスト数を 38 → **46** に
- [x] **P1.5-24** ネット検索で確認: コミュニティ標準は `NSWorkspace.shared.icon(forFile:)` 単独 (orchetect の Gist 等)。FloatingMacro のカスケード設計は「ImageIO で取れる伝統アプリは速く・モダンアプリも自動で救済」の両取りで残置することを決定 — ただし表現上は「ImageIO 主路線 / NSWorkspace fallback」ではなく「両者対等な主要パス」と位置づけ直し

### Phase 2 — 表現力の拡張 ✅ 完了 (v0.11.0, 2026-05-04)

> ※ 番号は HandOver.md §2 (P2-1〜P2-14) の項目に対応している。本章では HandOver.md の番号を維持してチェックを入れる。

- [x] **P2-1** `GroupDisplayType` enum (`icon` / `wide` / `card`) を追加 — [Preset.swift](../../Sources/FloatingMacroCore/Config/Preset.swift)
- [x] **P2-2** `ButtonGroup.displayType` を追加（既定値 `.icon`、欠落時は `.icon` でロード、`.icon` の場合は encode 時に省略して既存ファイルと差分ゼロ）
- [x] **P2-3** Wide タイプのレンダラー — [ButtonView.swift](../../Sources/FloatingMacroApp/ButtonView.swift) の `wideLayout`。28pt アイコン + 13pt ラベル (2 行まで)
- [x] **P2-4** Card タイプのレンダラー — `cardLayout` + `LazyVGrid(adaptive: 96)`。`button.thumbnail` 優先で fallback は icon → iconText → 破線プレースホルダ
- [x] **P2-5** `ButtonDefinition.thumbnail` フィールド追加 — [ButtonDefinition.swift](../../Sources/FloatingMacroCore/Config/ButtonDefinition.swift)
- [x] **P2-6** サムネイル保存規約 — `IconAssetSaver.imagesDirectory(presetName:)` + `saveThumbnail(_, buttonId:, ext:)`。`presets/<name>/images/<button-id>.<ext>`
- [x] **P2-7** [SettingsDetail.swift](../../Sources/FloatingMacroApp/Settings/SettingsDetail.swift) の `GroupEditor` に表示タイプの segmented picker + ヒント文を追加
- [x] **P2-8** `ButtonEditor` に「サムネイル」入力欄 + 参照ボタン + 120×90 プレビュー枠
- [x] **P2-9** `ExecutionFeedback` ステートマシン (`MacroButtonView` 内) — 押下 → 黄枠 (250ms) → 緑枠 (800ms) → idle のアニメーション。確認ダイアログ経由でも feedback
- [x] **P2-10** 失敗 (赤) は `executeButton` の戻り値整理後に配線予定として現状は「押された＝成功扱い」。テスト 317 件のうち押下フィードバック由来の flaky なし
- [x] **P2-11** Tests: `testButtonGroupDisplayTypeRoundTrip` で `wide` / `card` のラウンドトリップ
- [x] **P2-12** Tests: `testButtonGroupLegacyJSONWithoutDisplayType` (displayType 無しは `.icon`) + `testButtonGroupDefaultDisplayTypeOmittedFromEncoding` (encode 時省略) + `testButtonDefinitionThumbnailRoundTrip` + `testSaveThumbnailWritesToImagesDirectory` + `testImagesDirectoryPath`
- [x] **P2-13** SPEC.md §6.4/§6.5 + §17 v0.11.0 章、CHANGELOG.md v0.11.0、Info.plist (`0.11.0` / build `19`)、SystemPrompt.version、AI_PROTOCOL.md/.ja.md にツール変更を反映
- [x] **P2-14** seed プリセット [`midjourney-gallery.json`](../../Sources/FloatingMacroCore/Resources/seedPresets/midjourney-gallery.json) を追加。画風 / ポーズ / 服装 / 背景の 4 グループを `displayType=card` + `appendMode=true` で構成し、仕上げ用 wide グループも 1 つ同梱。`SeedPresetInstallerTests.testMidjourneyGallerySeedDemonstratesCardAndAppendMode` で構成を CI に固定

### Phase 3 — マルチパネル

- [ ] **P3-1** `PanelConfig` 構造体定義 + `AppConfig.panels` 追加
- [ ] **P3-2** 旧 → 新自動移行：`panels` 空 → activePreset+window から1つ生成 → 書き戻し
- [ ] **P3-3** `PanelManager` 新設：複数 NSWindow を ID で管理
- [ ] **P3-4** メニューバーに「Panels」サブメニュー：Open / Close / List
- [ ] **P3-5** 「縁にドック」最小化挙動（左/右/上/下端にスナップ → 矩形バー化）
- [ ] **P3-6** 起動時の Panel 復元（visible だったものだけ表示）
- [ ] **P3-7** Control API ツール追加：`panel_create` `panel_close` `panel_show` `panel_hide` `panel_list`
- [ ] **P3-8** Control API：既存 `window_*` ツールの非推奨化（呼ばれたら最初の panel に作用）
- [ ] **P3-9** 設定画面：パネル一覧タブ（追加/削除/プリセット変更）
- [ ] **P3-10** Tests: 旧設定ファイル（v1）の自動移行 E2E
- [ ] **P3-11** Tests: 複数パネル同時開閉の状態整合性
- [ ] **P3-12** AI_PROTOCOL.md 更新：Panel 概念の説明と推奨ツール一覧
- [ ] **P3-13** SPEC.md 全面更新

### Phase 4 — AI 連携（オプション）

- [ ] **P4-1** `ImageGenerationProvider` プロトコル定義（generate(prompt, size) -> URL or Data）
- [ ] **P4-2** Recraft プロバイダー実装
- [ ] **P4-3** OpenAI gpt-image-1 プロバイダー実装
- [ ] **P4-4** 鍵管理 UI：プロバイダーごとに Keychain に保存
- [ ] **P4-5** ボタン編集画面に「アイコン生成」セクション（鍵設定済みのときだけ表示）
- [ ] **P4-6** `ButtonDefinition.generationPrompt` フィールド追加
- [ ] **P4-7** 生成画像のローカル保存（preset 配下 images/）
- [ ] **P4-8** 生成失敗時のエラー表示（API 制限、鍵失効）
- [ ] **P4-9** Tests: モックプロバイダーで E2E
- [ ] **P4-10** SPEC.md 更新（BYOK 方針の明示、対応プロバイダー一覧）

### Phase 5 — マルチデバイス

- [ ] **P5-1** `ControlAPIConfig.lanExposureEnabled` 追加
- [ ] **P5-2** Control API のバインドアドレスを切替可能に（127.0.0.1 ⇄ 0.0.0.0）
- [ ] **P5-3** `ephemeralLanToken` 生成ロジック（起動時 / 手動再発行）
- [ ] **P5-4** Web Panel 用静的アセット（HTML+CSS+JS、アプリにバンドル）
- [ ] **P5-5** Web Panel から `tools/call` 呼び出し（CORS 設定、安全 tool ホワイトリスト）
- [ ] **P5-6** ルート `GET /panel?token=xxx` 実装：HTML 配信 + トークン検証
- [ ] **P5-7** Web Panel の icon / wide / card レンダラー（タッチ対応 CSS）
- [ ] **P5-8** QR コード生成（CIFilter.qrCodeGenerator）
- [ ] **P5-9** メニューバー「📱 デバイスに送信」モーダル：QR + URL + トークン再発行ボタン
- [ ] **P5-10** LAN 公開中のメニューバーアイコン色変更（赤）
- [ ] **P5-11** mDNS 広報（NetService.publish）
- [ ] **P5-12** 安全 tool ホワイトリスト：`button_press` `panel_show` 等の読取/操作系のみ
- [ ] **P5-13** Web Panel から破壊的 tool を呼ばれたら 403
- [ ] **P5-14** Tests: LAN 公開トグル → 別マシン curl で疎通確認（リモート Mac mini を使う）
- [ ] **P5-15** Tests: Web Panel での button_press → Mac 側にアクション到達
- [ ] **P5-16** SPEC.md / AI_PROTOCOL.md / README 更新（マルチデバイス節追加）
- [ ] **P5-17** ブログ記事下書き：Stream Deck を持っていない人向けの導入ガイド

---

## 7. 各 Phase の意思決定ポイント

実装開始前に必ず合意したい論点：

### Phase 1
- 画像のコピー先：preset ディレクトリに常にコピー（移植性◯、ディスク使用量増） vs 絶対パス参照（移植性✗、ディスク使用量◎） → **コピー推奨。preset 単体エクスポートが画像も含めて完結する**
- SF Symbols のバージョン：macOS 13+ で動くものに限定するか、最新まで含めて未対応 OS でフォールバックするか

### Phase 2
- Card タイプの最小サイズ・アスペクト比：YouTube 16:9 を既定にするか、正方形にするか
- displayType がグループ単位で固定 vs ボタン単位で個別 → **グループ単位推奨**（レイアウト崩れ回避）

### Phase 3
- 旧 `WindowConfig` / `activePreset` フィールドをいつ削除するか（数バージョン共存後）
- Panel 数の上限を設けるか（リソース保護）

### Phase 4
- 既定プロバイダーをどれにするか（推奨：Recraft、ベクター品質が高い）
- 生成画像の自動キャッシュ vs 都度生成

### Phase 5
- Web Panel の認証方式：URL クエリトークン vs Cookie + 別途認証画面
- HTTPS 対応を将来やるか（自己署名 + Let's Encrypt 経由 mkcert 等は複雑すぎるので原則不要）

---

## 8. 想定リスクと回避

| リスク | 影響 | 回避 |
|---|---|---|
| Phase 3 のスキーマ変更でユーザー設定が壊れる | 致命的 | 移行ロジックに E2E テスト必須、変更前にバックアップを書く |
| LAN 公開でローカルネットワーク内の他者から操作される | セキュリティ事故 | 短期トークン必須、明示トグル、視覚警告、安全 tool ホワイトリスト |
| AI 画像生成 API の課金がユーザーに想定外請求 | 信頼失墜 | BYOK 厳守、鍵未登録時は UI を出さない、生成前のコスト表示 |
| 複数パネル + Web Panel でリソース消費が激増 | UX 劣化 | パネル数の事実上の上限（10程度）と Web 接続のアイドルタイムアウト |
| Card タイプ実装でパネルが巨大化、フローティングの意味喪失 | 使い勝手低下 | 縁ドック必須、専用ホットキーでの一時展開も検討 |

---

## 9. 参照

- `SPEC.md` — アプリ全体の仕様。本ロードマップ完了後に各 Phase の内容が反映される
- `docs/AI_PROTOCOL.md` — Control API のツール定義とプロトコル
- `Sources/FloatingMacroCore/Config/ButtonDefinition.swift` — Button モデル
- `Sources/FloatingMacroCore/Config/Preset.swift` — Group / Preset / WindowConfig / AppConfig モデル
- `Sources/FloatingMacroCore/ControlAPI/ToolCatalog.swift` — Control API のツールカタログ
