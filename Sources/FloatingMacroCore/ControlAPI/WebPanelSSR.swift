import Foundation

/// Render initial HTML for Web Panel on the server side.
///
/// Why SSR?
/// JS fetches preset_get before anything appears on the screen, resulting in a "30 seconds of pure white".
/// An issue occurs.
/// Embedding the preset structure in initial HTML allows the browser to reach HTML at the same time as loading.
/// Can paint header group label skeleton card.
/// After that, JS is loaded and image URLs are inserted into the skeleton.
/// Replace shimmer with real.
public enum WebPanelSSR {

    /// Construct an HTML string to be assembled within the `<section id="panels">`.
    /// Return six generic skeleton cards when preset is nil.
    /// (fallback to convey a "loading" feel).
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

    /// Group's HTML. Skeleton with button label included.
    /// The image src is not inserted here (JS injects after calculating token/size).
    /// Label and layout are enough to make it visible in initial paint.
    private static func renderGroup(_ group: ButtonGroup) -> String {
        let dt = group.displayType
        let dtClass: String
        switch dt {
        case .icon: dtClass = "icon"
        case .wide: dtClass = "wide"
        case .card: dtClass = "card"
        case .grid: dtClass = "grid"
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

    /// HTML for a button. The image src is not placed in the data-src attribute, only the button id.
    /// Allow. JS that button.id based on window.__FM_PRESET__ from original data
    /// Insert image URL / insert click handler.
    private static func renderButton(_ b: ButtonDefinition,
                                     displayType: GroupDisplayType) -> String {
        let id = WebPanelAssets.htmlEscape(b.id)
        let label = WebPanelAssets.htmlEscape(b.label ?? "")
        let hasImage = (b.icon?.isEmpty == false) || isLaunchAction(b.action)
        let hasIconText = (b.iconText?.isEmpty == false)

        switch displayType {
        case .card:
            return """
            <button class="btn" data-id="\(id)">\
            <div class="thumb"></div>\
            <div class="body"><div class="label">\(label)</div></div>\
            </button>
            """
        case .grid:
            return """
            <button class="btn" data-id="\(id)">\
            <div class="icon skeleton" style="width:48px;height:48px;border-radius:8px"></div>\
            <div class="label">\(label)</div>\
            </button>
            """
        case .wide, .icon:
            // When there is an image: reserve area for skeleton icon (32x32)
            // For iconText: Just output the emoji directly (instantly painted and cute)
            // Only label in text-only class when neither is present
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

    /// Fallback skeleton when no preset is available. Arrange N buttons in a row.
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
