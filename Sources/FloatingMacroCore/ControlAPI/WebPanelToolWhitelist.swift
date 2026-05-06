import Foundation

/// Phase 5 (P5-12 / P5-13): Web Panel から呼び出し可能なツールのホワイトリスト。
///
/// ## なぜホワイトリスト方式か
/// Web Panel はスマホ/タブレットの Safari から LAN 経由でアクセスされる。
/// `/tools/call` はファイル上書きや preset 削除など破壊的操作も含むため、
/// 通常の Bearer トークンが何かの拍子に漏れるシナリオを考えると、
/// 「LAN 公開モード × ephemeral トークン」の経路では破壊的操作を**そもそも
/// 呼べないようにする**のが安全。
///
/// ## 含めた tool / 含めなかった tool
/// - 含める: 読み取り (`ping` / `get_state` / `panel_list` / `preset_list` /
///   `preset_current`) と、ユーザーが画面で押したいボタンの実行 (`button_press`)、
///   プリセット切替 (`preset_switch`)。
/// - 含めない: `*_add` / `*_update` / `*_delete` のような config 変更系、
///   `run_action` (任意のキーストローク/コマンド実行)、`settings_*` (Mac 側
///   ウィンドウ操作)、AI 連携、ログ参照など。
///
/// ## ロードマップ的な位置づけ
/// 「とりあえず動く」段階のホワイトリストで、必要に応じて拡張する。たとえば
/// パネル位置を遠隔調整したい等の要望が出たら `panel_move` / `panel_resize` を
/// 追加する判断はあり得る。
public enum WebPanelToolWhitelist {

    /// Web Panel から呼び出し可能な tool 名の集合。
    public static let allowed: Set<String> = [
        // Discovery & state
        "ping",
        "help",
        "manifest",
        "get_state",

        // Panel discovery (write 系の panel_create / panel_close は含めない)
        "panel_list",

        // Preset 切替系 (mutate 系の preset_create / rename / delete は含めない)
        "preset_list",
        "preset_current",
        "preset_get",     // Phase 5: パネルごとの Web Panel が指定 preset を読む
        "preset_switch",

        // ボタン押下 — Web Panel の主目的
        "button_press",
    ]

    /// 名前が allowed に含まれているか判定する。
    public static func isAllowed(_ name: String) -> Bool {
        return allowed.contains(name)
    }
}
