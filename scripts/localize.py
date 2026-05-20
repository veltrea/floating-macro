#!/usr/bin/env python3
"""
Extract hardcoded Japanese strings from Swift source files and generate
Localizable.strings (ja + en) plus rewrite Swift sources to use String(localized:).

Usage:
    python3 scripts/localize.py --scan          # dry-run: list strings
    python3 scripts/localize.py --generate      # write .strings files only
    python3 scripts/localize.py --rewrite       # rewrite Swift sources + .strings
"""

import re, os, sys, json, hashlib, unicodedata
from pathlib import Path
from collections import OrderedDict

ROOT = Path(__file__).resolve().parent.parent
APP_SRC = ROOT / "Sources" / "FloatingMacroApp"
EN_LPROJ = APP_SRC / "Resources" / "en.lproj"
JA_LPROJ = APP_SRC / "Resources" / "ja.lproj"

# Patterns to skip (log lines, comments, non-UI strings)
SKIP_PATTERNS = [
    r'LoggerContext', r'NSLog\(', r'log\.', r'print\(',
    r'fputs\(', r'\.info\(', r'\.debug\(', r'\.error\(',
    r'\.warning\(', r'#selector',
]

# Regex for Japanese characters
JP_CHARS = r'[ぁ-ゖァ-ヶ一-鿿々〇〻㐀-䶿豈-﫿]'

# Match string literals containing Japanese (no interpolation)
STATIC_JP_STRING = re.compile(r'"([^"\\]*(?:\\.[^"\\]*)*)"')

def has_japanese(s):
    return bool(re.search(JP_CHARS, s))

def has_interpolation(s):
    return '\\(' in s

def is_skip_line(line):
    stripped = line.strip()
    if stripped.startswith('//') or stripped.startswith('///'):
        return True
    for pat in SKIP_PATTERNS:
        if re.search(pat, line):
            return True
    return False

def make_key(text):
    """Generate a stable, readable key from Japanese text."""
    # Use first 40 chars, replace spaces/special chars
    short = text[:60].strip()
    # Create a short hash for uniqueness
    h = hashlib.md5(text.encode()).hexdigest()[:6]
    # Sanitize for .strings key: keep alphanumeric, Japanese, dots, underscores
    safe = re.sub(r'[^\wぁ-ゖァ-ヶ一-鿿]', '_', short)
    safe = re.sub(r'_+', '_', safe).strip('_')
    if len(safe) > 50:
        safe = safe[:50]
    return f"{safe}_{h}"

def scan_file(filepath):
    """Extract static Japanese strings from a Swift file."""
    results = []
    with open(filepath, 'r', encoding='utf-8') as f:
        lines = f.readlines()

    for lineno, line in enumerate(lines, 1):
        if is_skip_line(line):
            continue
        for m in STATIC_JP_STRING.finditer(line):
            text = m.group(1)
            if has_japanese(text) and not has_interpolation(text):
                # Check it's not already localized
                before = line[:m.start()]
                if 'String(localized:' in before or 'NSLocalizedString' in before:
                    continue
                results.append({
                    'file': str(filepath),
                    'line': lineno,
                    'text': text,
                    'col_start': m.start(),
                    'col_end': m.end(),
                    'full_match': m.group(0),
                })
    return results

def scan_all():
    """Scan all Swift files in FloatingMacroApp."""
    all_strings = []
    for swift_file in sorted(APP_SRC.rglob("*.swift")):
        results = scan_file(swift_file)
        all_strings.extend(results)
    return all_strings

# English translations for known strings
EN_TRANSLATIONS = {
    # Menu items (App.swift)
    "表示 / 非表示": "Show / Hide",
    "プリセット": "Presets",
    "透明度": "Opacity",
    "新しいパネルを追加": "Add New Panel",
    "展開": "Expand",
    "別の辺に移動": "Move to Another Edge",
    "位置をリセット": "Reset Position",
    "縁にドック": "Dock to Edge",
    "ドックバーを集める": "Gather Dock Bars",
    "パネル": "Panels",
    "編集...": "Edit...",
    "ノーマル": "Normal",
    "テスト（自律）": "Test (Autonomous)",
    "AI モード": "AI Mode",
    "AI 接続: オン": "AI Connection: On",
    "AI 接続: オフ": "AI Connection: Off",
    "AI に接続...": "Connect to AI...",
    "📱 デバイスに送信...": "📱 Send to Device...",
    "設定フォルダを開く": "Open Config Folder",
    "再読み込み": "Reload",
    "終了": "Quit",
    "左": "Left",
    "右": "Right",
    "上": "Top",
    "下": "Bottom",

    # Accessibility dialog
    "Accessibility 権限が必要です": "Accessibility Permission Required",
    "FloatingMacro がキーボードショートカットを送出するには、Accessibility 権限が必要です。システム設定で許可してください。": "FloatingMacro requires Accessibility permission to send keyboard shortcuts. Please grant permission in System Settings.",
    "システム設定を開く": "Open System Settings",
    "後で": "Later",

    # Preset operations
    "プリセットを切り替え (右クリックで編集/並べ替え/削除)": "Switch preset (right-click to edit/reorder/delete)",
    "並べ替え...": "Reorder...",
    "削除...": "Delete...",
    "このプリセットを削除しますか?": "Delete this preset?",
    "キャンセル": "Cancel",
    "プリセットが読み込めません": "Cannot load preset",
    "アクセシビリティ権限が無効": "Accessibility permission is disabled",
    "修復": "Repair",
    "編集ウィンドウを開く…": "Open editor…",
    "デバイスに送信…": "Send to device…",
    "AI に接続を設定…": "Configure AI connection…",

    # Color names
    "システム既定": "System Default",
    "ダークネイビー": "Dark Navy",
    "ディープパープル": "Deep Purple",
    "ミッドナイトグリーン": "Midnight Green",
    "チャコール": "Charcoal",
    "スレートブルー": "Slate Blue",
    "ダークレッド": "Dark Red",
    "フォレストグリーン": "Forest Green",
    "カスタム色...": "Custom Color...",
    "背景色": "Background Color",

    # Context menu (panel background)
    "新規グループを追加": "Add New Group",
    "グループを貼り付け": "Paste Group",
    "編集を開く...": "Open Editor...",
    "新規ボタンを追加": "Add New Button",
    "ボタンを貼り付け": "Paste Button",
    "新ボタン": "New Button",
    "新グループ": "New Group",
    "メモ": "Notes",

    # ButtonView context menu
    "複製": "Duplicate",
    "コピー": "Copy",
    "新規ボタンを追加": "Add New Button",
    "このボタンを削除しますか?": "Delete this button?",
    "この操作は元に戻せません。": "This action cannot be undone.",

    # Settings window
    "FloatingMacro 編集": "FloatingMacro Editor",
    "編集": "Edit",
    "セキュリティ": "Security",

    # Settings - Security tab
    "コマンドセーフガード": "Command Safeguard",
    "確認ダイアログを有効にする": "Enable confirmation dialogs",
    "オートパイロットモード": "Autopilot Mode",
    "パスワードを設定する…": "Set password…",
    "オートパイロットを無効にする": "Disable autopilot",
    "オートパイロットを有効にする…": "Enable autopilot…",
    "パスワードを変更する…": "Change password…",
    "確認対象パターン一覧": "Confirmation Pattern List",
    "パターン": "Pattern",
    "確定": "Confirm",
    "パターンを追加": "Add Pattern",
    "追加": "Add",
    "デフォルトパターンに戻す": "Reset to Default Patterns",

    # Settings - Preset management
    "新しいプリセット": "New Preset",
    "現在のプリセットを削除": "Delete Current Preset",
    "名前を変更…": "Rename…",
    "並べ替え…": "Reorder…",
    "エクスポート…": "Export…",
    "全プリセットをエクスポート…": "Export All Presets…",
    "インポート…": "Import…",

    # Settings - AI
    "AI 接続": "AI Connection",
    "ポート": "Port",
    "変更後はアプリの再起動が必要です。": "App restart required after changes.",

    # Settings - Groups
    "グループ追加": "Add Group",
    "ボタン追加": "Add Button",
    "アプリから追加…": "Add from App…",
    "グループ名を変更": "Rename Group",
    "グループ削除": "Delete Group",

    # Settings dialogs
    "プリセット名を入力してください": "Enter preset name",
    "作成": "Create",
    "プリセット名を変更": "Rename Preset",
    "プリセットをエクスポート": "Export Preset",
    "プリセットをインポート": "Import Preset",
    "新グループ": "New Group",
    "新ボタン": "New Button",
    "プリセットの並べ替え": "Reorder Presets",

    # SettingsDetail - Button editing
    "左から編集するボタンまたはグループを選択してください。": "Select a button or group from the left to edit.",
    "プレビュー": "Preview",
    "ラベル": "Label",
    "表示文字列": "Display text",
    "アイコンテキスト (絵文字など)": "Icon text (emoji, etc.)",
    "アイコン": "Icon",
    "サムネイル (card タイプのグループ用)": "Thumbnail (for card-type groups)",
    "文字色": "Text Color",
    "幅": "Width",
    "高さ": "Height",
    "アクション": "Action",
    "種類": "Type",

    # Action types
    "貼り付けテキスト": "Paste Text",
    "追記モード（プロンプトビルダー）": "Append Mode (Prompt Builder)",
    "修飾キー": "Modifier Keys",
    "キー (a〜z / 0〜9 / ...)": "Key (a–z / 0–9 / ...)",
    "起動対象 (パス / URL / bundle id / shell:)": "Launch target (path / URL / bundle id / shell:)",
    "コマンド (Terminal.app に投入)": "Command (sent to Terminal.app)",
    "ステップを追加": "Add Step",
    "エラーで中断": "Stop on Error",
    "ツールチップ (ホバー時に表示)": "Tooltip (shown on hover)",
    "実行前の確認": "Confirm Before Execution",

    # Action type names
    "テキスト貼り付け": "Paste Text",
    "キー入力": "Key Input",
    "アプリ起動": "Launch App",
    "ターミナル": "Terminal",
    "マクロ": "Macro",

    # Group editing
    "グループ名": "Group Name",
    "ボタンの表示タイプ": "Button Display Type",
    "icon (小さなアイコン)": "icon (small icons)",
    "wide (横長セル)": "wide (horizontal cells)",
    "card (大きなサムネイル)": "card (large thumbnails)",

    # Key recording
    "押してください…(Esc で取消)": "Press a key… (Esc to cancel)",
    "特殊キー…": "Special Keys…",

    # Delete confirmation
    "このボタンを削除しますか?": "Delete this button?",

    # CommandConfirmation
    "危険なコマンドが検出されました": "Dangerous command detected",
    "実行する": "Execute",
    "確認": "Confirm",
    "パスワード": "Password",

    # PanelDropHandler
    "ドロップされたアイテムをボタンにしますか?": "Turn dropped items into buttons?",

    # DeviceSend
    "デバイスに送信": "Send to Device",
    "📱 デバイスに送信": "📱 Send to Device",
    "LAN 公開モード": "LAN Sharing Mode",
    "再発行": "Reissue",

    # AIIntegration
    "AI に FloatingMacro を操作させる": "Let AI control FloatingMacro",
    "接続用プロンプトをコピー": "Copy connection prompt",
    "AI クライアントに MCP として登録": "Register as MCP in AI client",
    "接続情報": "Connection Info",
    "CLI 登録": "CLI Registration",
    "HTTP 登録": "HTTP Registration",

    # BinaryIdentity
    "修復": "Repair",

    # SFSymbolCatalog
    "一般": "General",
    "ナビ": "Navigation",
    "ファイル": "Files",
    "メディア": "Media",
    "通信": "Communication",
    "ツール": "Tools",
    "システム": "System",

    # SettingsView AI modes
    "ノーマル": "Normal",
    "テスト（自律）": "Test (Autonomous)",

    # Misc
    "閉じる": "Close",
    "保存": "Save",
    "削除": "Delete",
    "選択": "Select",
    "決定": "Done",
    "未選択": "Not Selected",
    "読み込み中…": "Loading…",
    "現在のプリセット": "Current Preset",
    "有効": "Enabled",
    "無効": "Disabled",

    # PanelsSettings
    "このパネルが表示するプリセットを切り替え": "Switch the preset shown in this panel",
    "このパネルを設定から削除": "Remove this panel from settings",
    "最後の 1 件は削除できません": "Cannot delete the last one",

    # ImageDropZone
    "画像をドロップして登録 / クリックでファイル選択": "Drop an image to register / Click to select a file",

    # Settings detail help texts
    "SF Symbol を一覧から選ぶ": "Choose from SF Symbol list",
    "インストール済みアプリのアイコンから選ぶ": "Choose from installed app icons",
    "再起動・シャットダウン等、取り消しのきかない操作のみ ON にしてください。": "Only enable for irreversible operations like restart or shutdown.",

    # Additional strings from scan
    "例: MidJourney 用": "e.g. For MidJourney",
    "このグループを削除しますか?": "Delete this group?",
    "グループ内のボタンもすべて削除されます。この操作は元に戻せません。": "All buttons in this group will also be deleted. This action cannot be undone.",
    "行をドラッグして順序を変更し「保存」を押してください。": "Drag rows to change order, then click Save.",
    "グループの用途を説明": "Describe the group's purpose",
    "アルファベット順にリセット": "Reset to Alphabetical Order",

    # Missing translations batch
    "(不明)": "(unknown)",
    "(自動: 背景色があれば白、なければ システム既定)": "(auto: white if background color is set, otherwise system default)",
    "(自動: 背景色があれば白、なければシステム既定)": "(auto: white if background color is set, otherwise system default)",
    "/Applications/… または bundle id": "/Applications/… or bundle id",
    "4文字以上のパスワードを設定してください。": "Password must be at least 4 characters.",
    "<トークンを Keychain から取得できませんでした>": "<Could not retrieve token from Keychain>",
    "Bonjour 公開中": "Bonjour broadcasting",
    "Claude Code、Cursor、ChatGPT 等の AI に貼り付けるプロンプトをクリップボードにコピーします。Bearer トークンが埋め込まれた状態で、AI に貼り付けるだけで FloatingMacro を操作できるようになります。": "Copies a prompt with embedded Bearer token to the clipboard. Paste it into your AI (Claude Code, Cursor, ChatGPT, etc.) to let it control FloatingMacro.",
    "Claude Desktop / Trae / Antigravity の登録ボタンは未提供。Claude Desktop は Pro 以上で「設定 → Connectors」から URL を直接登録できます (URL とトークンは下の『接続情報』からコピーしてください)。または手動で claude_desktop_config.json に CLI 経由で登録してください (詳細はマニュアル参照)。": "Registration buttons for Claude Desktop / Trae / Antigravity are not provided. Claude Desktop (Pro+) supports direct URL registration via Settings → Connectors (copy URL and token from Connection Info below). Or manually register via CLI in claude_desktop_config.json (see manual for details).",
    "FloatingMacro AI 連携": "FloatingMacro AI Integration",
    "FloatingMacro — LAN 公開中 (Phase 5)": "FloatingMacro — LAN Sharing Active",
    "GET /manifest で返すシステムプロンプトを切り替えます": "Switches the system prompt returned by GET /manifest",
    "HTTP プロトコルで直接接続。中級者向け。": "Direct connection via HTTP. For intermediate users.",
    "Keychain からトークンを取得できませんでした。": "Could not retrieve token from Keychain.",
    "LAN 公開モードを ON にすると、同じ Wi-Fi にいるスマホ / タブレットからこのパネルを操作できます。": "When LAN sharing is ON, smartphones and tablets on the same Wi-Fi can operate this panel.",
    "LAN 内のスマホ / タブレットの Safari で QR を読むと、上の URL が開きます。再発行すると過去の QR は無効になります。": "Scan the QR code with Safari on a smartphone/tablet on the same LAN to open the URL above. Reissuing invalidates previous QR codes.",
    "ON にすると、ボタンを押してもペーストせず、上のテキストが既存のクリップボードに連結されます。プロンプト断片を組み合わせて作る用途。仕上げに自分で Cmd+V で貼り付けてください。": "When ON, pressing the button does not paste. Instead, the text is appended to the existing clipboard. Use this to build prompts from fragments. Paste manually with Cmd+V when ready.",
    "OS のファイアウォールが初回有効化時に「FloatingMacro が着信接続を受け付けるか」を聞いてくることがあります。許可してください。": "The OS firewall may ask whether FloatingMacro should accept incoming connections when first enabled. Please allow it.",
    "QR を生成できません": "Cannot generate QR code",
    "SF Symbol を選択": "Select SF Symbol",
    "`/Applications`・`/System/Applications`・`~/Applications` をサブフォルダ込みで一覧します。Bundle ID も検索対象です。": "Lists /Applications, /System/Applications, and ~/Applications including subfolders. Bundle IDs are also searchable.",
    "`/Applications`・`/System/Applications`・`~/Applications` を一覧します。Bundle ID も検索対象です。": "Lists /Applications, /System/Applications, and ~/Applications. Bundle IDs are also searchable.",
    "fmcli (CLI ツール) を経由して接続。一般的・推奨。": "Connect via fmcli (CLI tool). Standard and recommended.",
    "tccutil で TCC エントリをリセットし、--prompt-accessibility 付きで自身を再起動します。新プロセスが OS の許可ダイアログを呼び、一覧にエントリを追加するので、ユーザーはスイッチを ON にするだけで済みます。": "Resets the TCC entry with tccutil and relaunches with --prompt-accessibility. The new process triggers the OS permission dialog, adding an entry to the list so the user only needs to flip the switch ON.",
    "↳ 位置をリセット": "↳ Reset Position",
    "↳ 別の辺に移動": "↳ Move to Another Edge",
    "↳ 展開": "↳ Expand",
    "↳ 縁にドック": "↳ Dock to Edge",
    "「CLI 登録」(青) は fmcli というコマンドラインツール経由で接続する方式 (推奨)。「HTTP 登録」(枠) は HTTP 経由で接続する方式 (中級者向け)。両方を同時に登録することも可能です (内部的に別名で登録されるので衝突しません)。": "'CLI Registration' (blue) connects via the fmcli command-line tool (recommended). 'HTTP Registration' (outlined) connects directly via HTTP (intermediate). You can register both simultaneously (they use different internal names, so no conflict).",
    "このプリセットを使う前提条件・注意点を書いておくと、パネル上部のメモアイコンから参照できます。": "Write prerequisites and notes for this preset here. They can be viewed from the notes icon at the top of the panel.",
    "この操作を実行します。": "This action will be executed.",
    "アクティブな preset が見つかりません。": "No active preset found.",
    "アプリから...": "From App...",
    "アプリのアイコンを選択": "Select App Icon",
    "アプリを選んでボタンに追加": "Select an app to add as a button",
    "インストール済みアプリの一覧から起動ボタンを作成": "Create a launch button from installed apps",
    "インポートに失敗: JSON 形式が不正です": "Import failed: invalid JSON format",
    "インポートに失敗: ファイルを読み込めません": "Import failed: cannot read file",
    "インポートに失敗しました": "Import failed",
    "エンドポイント:": "Endpoint:",
    "オン": "On",
    "オンにすると AI や外部ツールがこのアプリを操作できます (HTTP API をポートで公開)。": "When enabled, AI and external tools can control this app (HTTP API exposed on port).",
    "オートパイロットを有効にする": "Enable Autopilot",
    "オートパイロット用パスワードを設定": "Set Autopilot Password",
    "キー (a〜z / 0〜9 / 矢印 / Delete / F1〜 等)": "Key (a–z / 0–9 / Arrow / Delete / F1– etc.)",
    "キーを押して記録": "Press a key to record",
    "クリア": "Clear",
    "クリップボードにコピー": "Copy to Clipboard",
    "クロップ": "Crop",
    "グループの見出し": "Group heading",
    "コマンド": "Command",
    "サムネイル画像 + タイトルを 2 列のグリッドに配置。プロンプトギャラリー向け。": "Thumbnail + title in a 2-column grid. Ideal for prompt galleries.",
    "サムネイル画像をドロップ\\nまたはクリック": "Drop a thumbnail\\nor click to select",
    "テキスト": "Text",
    "トークン取得:": "Token source:",
    "バンドル内に同梱された npm パッケージが見つかりません (Contents/Resources/npm)。build-app.sh で再ビルドしてください。": "Bundled npm package not found (Contents/Resources/npm). Please rebuild with build-app.sh.",
    "パスワードが一致しません。": "Passwords do not match.",
    "パスワードが未設定です。先にパスワードを設定してください。": "No password set. Please set a password first.",
    "パスワードが違います": "Incorrect password",
    "パスワードを入力してください。\\n有効にすると確認ダイアログなしにすべてのコマンドが実行されます。": "Enter your password.\\nWhen enabled, all commands execute without confirmation dialogs.",
    "パスワードを変更": "Change Password",
    "パターンが登録されていません。": "No patterns registered.",
    "パネルが設定されていません。": "No panels configured.",
    "フローティングパネル": "Floating Panel",
    "プリセット名を入力してください（自由入力・あとから変更可）": "Enter a preset name (free text, can be changed later)",
    "プレビューを更新": "Update Preview",
    "プロンプトをコピー": "Copy Prompt",
    "ボタンの用途を説明": "Describe the button's purpose",
    "ランチャー": "Launcher",
    "リネーム / 並べ替え / エクスポート / インポート": "Rename / Reorder / Export / Import",
    "使う前提（OS 設定 / 前面アプリ / クリップボード上書き等）を書いておくと、時間を空けて使い直す時にすぐ思い出せます。": "Write prerequisites (OS settings, foreground app, clipboard overwrite, etc.) so you can quickly recall them when using later.",
    "例: rm -rf": "e.g. rm -rf",
    "全プリセットをエクスポート": "Export All Presets",
    "全体表示": "Full View",
    "全幅の横長セル。長いラベルや、視認性を優先したいボタンに。": "Full-width horizontal cells. For long labels or buttons prioritizing visibility.",
    "危険な操作 (実行ボタンを赤く強調)": "Dangerous action (highlight execute button in red)",
    "参照...": "Browse...",
    "変更": "Change",
    "変更する": "Apply Change",
    "実行する (取り消し不可)": "Execute (irreversible)",
    "実行前に確認ダイアログを出す": "Show confirmation dialog before execution",
    "対応する AI クライアントの設定ファイルに floatingmacro エントリを追記します。クライアントを再起動すると MCP サーバーとして自動接続されます。既存の設定は壊しません。": "Adds a floatingmacro entry to the AI client's config file. Restart the client to auto-connect as an MCP server. Existing settings are preserved.",
    "新しいパスワード": "New Password",
    "新しい名前を入力してください": "Enter a new name",
    "新しい表示名を入力してください": "Enter a new display name",
    "既存の小さなアイコン+ラベルを縦に並べる、コンパクトな表示。": "Compact display with small icons and labels stacked vertically.",
    "有効にすると、パターンに一致するコマンドでも確認ダイアログなしで実行されます。AIに完全に操作を委ねたいときに使います。\\n有効化にはパスワードが必要です。": "When enabled, even commands matching patterns execute without confirmation. Use when you want to fully delegate control to AI.\\nA password is required to enable.",
    "検索 (アプリ名 / bundle id)": "Search (app name / bundle id)",
    "検索 (例: star, mic, lock)": "Search (e.g. star, mic, lock)",
    "特殊キーを選択": "Select Special Key",
    "現在のパスワード": "Current Password",
    "現在のパスワードが違います。": "Current password is incorrect.",
    "画像をドロップ\\nまたはクリック": "Drop an image\\nor click to select",
    "画像をドロップするか枠をクリックすると、preset 配下にコピーして登録します。": "Drop an image or click the frame to copy and register it under the preset.",
    "画像を拡大して正方形を埋める。はみ出す部分は切り取り。": "Enlarge image to fill the square. Excess is cropped.",
    "画像全体をアスペクト比を保って表示。余白あり。": "Display entire image preserving aspect ratio. With padding.",
    "登録したパターンを含むコマンド・テキストをターミナルに送る前に確認ダイアログを表示します。大文字・小文字を区別せず部分一致で判定します。": "Shows a confirmation dialog before sending commands or text containing registered patterns to the terminal. Matches are case-insensitive and partial.",
    "確認のためもう一度": "Confirm again",
    "確認メッセージ (空欄なら自動生成)": "Confirmation message (auto-generated if empty)",
    "表示モード": "Display Mode",
    "表示名": "Display Name",
    "複数のパネルを同時表示し、用途別に違うプリセットを割り当てられます。": "Display multiple panels simultaneously, each assigned to a different preset.",
    "親グループの表示タイプが card のときに大きく表示されます。icon / wide では無視されます。": "Displayed large when parent group type is 'card'. Ignored for icon/wide.",
    "設定する": "Configure",
    "認証不要のディスカバリー: GET /manifest, /help, /.well-known/agent.json, /openapi.json, /ping, /health": "No-auth discovery: GET /manifest, /help, /.well-known/agent.json, /openapi.json, /ping, /health",
    "📱 デバイスに送信": "📱 Send to Device",
    "📱 デバイスに送信...": "📱 Send to Device...",
    "🧠 や ⚡ など": "e.g. 🧠 or ⚡",
    "  ↳ 展開": "  ↳ Expand",
    "  ↳ 別の辺に移動": "  ↳ Move to Another Edge",
    "  ↳ 位置をリセット": "  ↳ Reset Position",
    "  ↳ 縁にドック": "  ↳ Dock to Edge",
    "コピー": "Copy",
}


def generate_strings_files(entries):
    """Generate ja.lproj/Localizable.strings and en.lproj/Localizable.strings."""
    # Deduplicate by text
    seen = OrderedDict()
    for e in entries:
        text = e['text']
        if text not in seen:
            key = make_key(text)
            seen[text] = key

    # ja.lproj
    ja_lines = ['/* Japanese (default) - Localizable.strings */\n']
    for text, key in seen.items():
        escaped_text = text.replace('"', '\\"')
        ja_lines.append(f'"{key}" = "{escaped_text}";\n')

    # en.lproj
    en_lines = ['/* English - Localizable.strings */\n']
    for text, key in seen.items():
        en_text = EN_TRANSLATIONS.get(text, f"[TODO] {text}")
        escaped_en = en_text.replace('"', '\\"')
        en_lines.append(f'"{key}" = "{escaped_en}";\n')

    return ja_lines, en_lines, seen


def rewrite_sources(entries, key_map):
    """Rewrite Swift source files replacing Japanese literals with String(localized:)."""
    # Group by file
    by_file = {}
    for e in entries:
        by_file.setdefault(e['file'], []).append(e)

    changes = 0
    for filepath, file_entries in by_file.items():
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()

        # Sort by position descending so replacements don't shift offsets
        # We need to work line by line instead
        lines = content.split('\n')
        new_lines = []
        entry_map = {}
        for e in file_entries:
            entry_map.setdefault(e['line'], []).append(e)

        for lineno, line in enumerate(lines, 1):
            if lineno in entry_map:
                for e in sorted(entry_map[lineno], key=lambda x: -x['col_start']):
                    text = e['text']
                    key = key_map.get(text)
                    if key is None:
                        continue
                    old = f'"{text}"'
                    # Determine context: if inside Text(), Label(), .help(), .confirmationDialog etc
                    # SwiftUI Text/Label auto-lookup LocalizedStringKey, so we use LocalizedStringKey
                    # For NSMenuItem, NSAlert etc (AppKit), use String(localized:)

                    # Check if this is inside a SwiftUI view builder context
                    stripped = line.strip()

                    # For Text("..."), Label("...", ...), .help("..."),
                    # .confirmationDialog("..."), Button("...") - these accept
                    # LocalizedStringKey, so just changing the string to the key works
                    is_swiftui_auto = False
                    before_quote = line[:line.find(old)]
                    for pattern in ['Text(', 'Label(', '.help(', '.confirmationDialog(',
                                    'Button(', 'Toggle(', 'Section(', 'GroupBox(',
                                    '.navigationTitle(', 'Picker(']:
                        if pattern in before_quote:
                            # Check it's the first string arg
                            idx = before_quote.rfind(pattern)
                            between = before_quote[idx + len(pattern):].strip()
                            if between == '' or between == '"':
                                is_swiftui_auto = True
                                break

                    if is_swiftui_auto:
                        # SwiftUI auto-localizes, just use key as string
                        new = f'"{key}"'
                    else:
                        # AppKit / programmatic: use String(localized:)
                        new = f'String(localized: "{key}")'

                    line = line.replace(old, new, 1)
                    changes += 1
            new_lines.append(line)

        with open(filepath, 'w', encoding='utf-8') as f:
            f.write('\n'.join(new_lines))

    return changes


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else '--scan'

    entries = scan_all()
    print(f"Found {len(entries)} static Japanese strings across {len(set(e['file'] for e in entries))} files")

    if mode == '--scan':
        for e in entries:
            rel = os.path.relpath(e['file'], ROOT)
            print(f"  {rel}:{e['line']}  \"{e['text']}\"")
        # Show unique count
        unique = set(e['text'] for e in entries)
        print(f"\n{len(unique)} unique strings")
        # Show how many have translations
        translated = sum(1 for t in unique if t in EN_TRANSLATIONS)
        print(f"{translated} have English translations, {len(unique) - translated} need translation")
        return

    ja_lines, en_lines, key_map = generate_strings_files(entries)

    if mode in ('--generate', '--rewrite'):
        EN_LPROJ.mkdir(parents=True, exist_ok=True)
        JA_LPROJ.mkdir(parents=True, exist_ok=True)

        with open(JA_LPROJ / "Localizable.strings", 'w', encoding='utf-8') as f:
            f.writelines(ja_lines)
        print(f"Wrote {JA_LPROJ / 'Localizable.strings'} ({len(key_map)} entries)")

        with open(EN_LPROJ / "Localizable.strings", 'w', encoding='utf-8') as f:
            f.writelines(en_lines)
        print(f"Wrote {EN_LPROJ / 'Localizable.strings'} ({len(key_map)} entries)")

    if mode == '--rewrite':
        changes = rewrite_sources(entries, key_map)
        print(f"Rewrote {changes} string literals in source files")

    if mode in ('--generate', '--rewrite'):
        # Report TODO translations
        todos = [text for text in key_map if text not in EN_TRANSLATIONS]
        if todos:
            print(f"\n⚠ {len(todos)} strings need English translation (marked [TODO]):")
            for t in todos[:20]:
                print(f"  \"{t}\"")
            if len(todos) > 20:
                print(f"  ... and {len(todos) - 20} more")


if __name__ == '__main__':
    main()
