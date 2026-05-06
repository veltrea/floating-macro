import Foundation

/// Phase 5: Web Panel の初期 HTML を**サーバー側で完成形まで描画**する。
///
/// なぜ SSR か:
/// - JS が `preset_get` を fetch するまで何も画面に出ないと「30 秒間真っ白」
///   問題が起きる。
/// - 初期 HTML に preset 構造を埋め込めば、ブラウザは HTML 到達と同時に
///   ヘッダー・グループラベル・skeleton カードを paint できる。
/// - その後 JS が読み込まれて、画像 URL を skeleton に差し込みつつ
///   shimmer から本物に置換する。
public enum WebPanelSSR {

    /// `<section id="panels">` 内に展開する HTML 文字列を組み立てる。
    /// preset が nil のときは generic な 6 個の skeleton カードを返す
    /// (= 「読み込み中」感を出すための fallback)。
    public static func renderInnerHTML(preset: Preset?) -> String {
        guard let preset = preset else {
            return repeatString(generic: 6)
        }
        var out = ""
        for group in preset.groups {
            out += renderGroup(group)
        }
        return out
    }

    /// 1 グループの HTML。skeleton + ボタンラベルを含む。
    /// 画像 src は **ここでは入れない** (JS が token / size 算出後に注入)。
    /// ラベルとレイアウトだけは入れることで初期 paint で見える。
    private static func renderGroup(_ group: ButtonGroup) -> String {
        let dt = group.displayType
        let dtClass: String
        switch dt {
        case .icon: dtClass = "icon"
        case .wide: dtClass = "wide"
        case .card: dtClass = "card"
        }
        var html = "<div class=\"group \(dtClass)\" data-group-id=\"\(WebPanelAssets.htmlEscape(group.id))\">"
        let label = group.label
        if !label.isEmpty {
            html += "<h2>\(WebPanelAssets.htmlEscape(label))</h2>"
        }
        html += "<div class=\"buttons\">"
        for button in group.buttons {
            html += renderButton(button, displayType: dt)
        }
        html += "</div></div>"
        return html
    }

    /// 1 ボタンの HTML。画像 src は data-src 属性に入れず、ボタン id だけ
    /// 持たせる。JS が button.id ベースで window.__FM_PRESET__ から元データを
    /// 引いて画像 URL / クリックハンドラを差し込む。
    private static func renderButton(_ b: ButtonDefinition,
                                     displayType: GroupDisplayType) -> String {
        let id = WebPanelAssets.htmlEscape(b.id)
        let label = WebPanelAssets.htmlEscape(b.label ?? "")
        let hasImage = (b.icon?.isEmpty == false) || (b.thumbnail?.isEmpty == false) || isLaunchAction(b.action)
        let hasIconText = (b.iconText?.isEmpty == false)

        switch displayType {
        case .card:
            // card は thumb 領域 (skeleton) + body label を出しておく。
            // 画像が後から差し込まれるとき thumb の class に loaded を加えて
            // shimmer を止める。
            return """
            <button class="btn" data-id="\(id)">\
            <div class="thumb"></div>\
            <div class="body"><div class="label">\(label)</div></div>\
            </button>
            """
        case .wide, .icon:
            // 画像があるとき: skeleton icon 領域 (32x32) を確保
            // iconText のとき: そのまま絵文字を出す (即 paint されるしカワイイ)
            // どちらも無いとき: text-only クラスでラベルだけ
            if hasImage {
                return """
                <button class="btn" data-id="\(id)">\
                <div class="icon skeleton" style="width:32px;height:32px;border-radius:6px"></div>\
                <div class="label">\(label)</div>\
                </button>
                """
            } else if hasIconText {
                let icon = WebPanelAssets.htmlEscape(b.iconText ?? "")
                return """
                <button class="btn" data-id="\(id)">\
                <div class="icon">\(icon)</div>\
                <div class="label">\(label)</div>\
                </button>
                """
            } else {
                return """
                <button class="btn text-only" data-id="\(id)">\
                <div class="label">\(label)</div>\
                </button>
                """
            }
        }
    }

    /// preset が無いときの fallback skeleton。N 個のボタンを並べる。
    private static func repeatString(generic n: Int) -> String {
        let card = """
        <div class="group icon"><div class="buttons">\
        \(String(repeating: "<button class=\"btn skeleton\"><div class=\"label\">\u{200B}</div></button>", count: n))\
        </div></div>
        """
        return card
    }

    private static func isLaunchAction(_ action: Action) -> Bool {
        if case .launch = action { return true }
        return false
    }
}
