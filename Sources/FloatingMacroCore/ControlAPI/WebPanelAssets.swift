import Foundation

/// Phase 5 (P5-4): Web Panel 用の静的アセットをバンドルから取り出す薄いヘルパ。
///
/// アセットは `Sources/FloatingMacroCore/Resources/webpanel/` に置かれ、
/// `Package.swift` で `.copy("Resources/webpanel")` 宣言されている。
/// `.copy` を使うのはディレクトリ構造を保つため (`.process` だとフラット化
/// されて Bundle.module.url(forResource:subdirectory:) で取り出せなくなる)。
public enum WebPanelAssets {

    public enum AssetKind {
        case html
        case css
        case js

        public var fileName: String {
            switch self {
            case .html: return "panel.html"
            case .css:  return "style.css"
            case .js:   return "app.js"
            }
        }

        public var contentType: String {
            switch self {
            case .html: return "text/html; charset=utf-8"
            case .css:  return "text/css; charset=utf-8"
            case .js:   return "application/javascript; charset=utf-8"
            }
        }
    }

    /// バンドルからアセットの bytes を読み出す。見つからなければ nil。
    public static func data(_ kind: AssetKind) -> Data? {
        // 経緯メモ:
        // 当初 `Bundle.module.url(forResource:withExtension:subdirectory:)` を
        // 使っていたが、AppKit アプリ実行コンテキスト (= ControlServer の
        // ハンドラから main 経由で呼ぶ) で無応答になる現象が再現した。
        // `bundle.bundleURL` 自体も止まる。SwiftPM 自動生成
        // resource_bundle_accessor が遅延ロードする `.module` の初回アクセス
        // が原因と思われる。
        //
        // 回避策: 候補ディレクトリを直接探す。`Bundle.module` を一切踏まない。
        for url in resolveAssetURLs(fileName: kind.fileName) {
            if FileManager.default.fileExists(atPath: url.path) {
                return try? Data(contentsOf: url)
            }
        }
        return nil
    }

    /// アセット候補 URL を優先順位順に返す。.app / CLI / xctest / Linux SwiftPM
    /// などのレイアウト差異を一度に吸収する。
    private static func resolveAssetURLs(fileName: String) -> [URL] {
        let bundleName = "FloatingMacro_FloatingMacroCore.bundle"
        var candidateBundles: [URL] = [
            // .app の正規配置: <App>.app/Contents/Resources/<bundle>
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/\(bundleName)"),
            // CLI / SwiftPM 既定: <main>/<bundle>
            Bundle.main.bundleURL.appendingPathComponent(bundleName),
            // xctest 等、Bundle.main の親ディレクトリにあるパターン
            Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent(bundleName),
        ]
        // Bundle.allBundles を覗いて bundleName と同じ末尾を持つものを追加。
        // xctest ではテストターゲットがロードしている Core モジュールの
        // resource bundle がここに登録されている。
        for b in Bundle.allBundles where b.bundleURL.lastPathComponent == bundleName {
            candidateBundles.append(b.bundleURL)
        }
        return candidateBundles.map {
            $0.appendingPathComponent("webpanel", isDirectory: true)
              .appendingPathComponent(fileName)
        }
    }

    /// 旧シグネチャ。テストで bundle 差し替えしたいケース用に残す。
    static func data(_ kind: AssetKind, from bundle: Bundle) -> Data? {
        let url = bundle.bundleURL
            .appendingPathComponent("webpanel", isDirectory: true)
            .appendingPathComponent(kind.fileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return try? Data(contentsOf: url)
    }

    /// HTML を読み出して以下のプレースホルダを置換する:
    ///   - `{{TOKEN}}`           ephemeral LAN token (JS リテラル安全化済み)
    ///   - `{{PRESET_JSON}}`     preset 全体の JSON literal (JS から直接読める)
    ///   - `{{PRESET_DISPLAY}}`  preset の表示名 (HTML エスケープ済み)
    ///   - `{{SSR_HTML}}`        skeleton グループ + ボタンの初期 DOM
    ///
    /// SSR で初期 HTML を完成させることで、JS が `preset_get` を fetch しに
    /// 行く round trip を 1 つ削れる。ヘッダーとカードレイアウトは HTML 到達
    /// 直後に paint される。
    public static func renderHTML(token: String,
                                  presetJSON: String,
                                  presetDisplay: String,
                                  ssrHTML: String) -> Data? {
        guard let raw = data(.html),
              let template = String(data: raw, encoding: .utf8) else {
            return nil
        }
        return substitute(template: template,
                          token: token,
                          presetJSON: presetJSON,
                          presetDisplay: presetDisplay,
                          ssrHTML: ssrHTML)
            .data(using: .utf8)
    }

    /// テスト用: 任意の bundle を指定する形。
    static func renderHTML(token: String,
                           presetJSON: String,
                           presetDisplay: String,
                           ssrHTML: String,
                           from bundle: Bundle) -> Data? {
        guard let raw = data(.html, from: bundle),
              let template = String(data: raw, encoding: .utf8) else {
            return nil
        }
        return substitute(template: template,
                          token: token,
                          presetJSON: presetJSON,
                          presetDisplay: presetDisplay,
                          ssrHTML: ssrHTML)
            .data(using: .utf8)
    }

    private static func substitute(template: String,
                                   token: String,
                                   presetJSON: String,
                                   presetDisplay: String,
                                   ssrHTML: String) -> String {
        return template
            .replacingOccurrences(of: "{{TOKEN}}", with: sanitizeForJSON(token))
            .replacingOccurrences(of: "{{PRESET_JSON}}",
                                  with: presetJSON.isEmpty ? "null" : presetJSON)
            .replacingOccurrences(of: "{{PRESET_DISPLAY}}", with: htmlEscape(presetDisplay))
            .replacingOccurrences(of: "{{SSR_HTML}}", with: ssrHTML)
    }

    /// テキストを HTML body に直接埋め込むための最小エスケープ。
    static func htmlEscape(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for ch in s {
            switch ch {
            case "&":  out.append("&amp;")
            case "<":  out.append("&lt;")
            case ">":  out.append("&gt;")
            case "\"": out.append("&quot;")
            case "'":  out.append("&#39;")
            default:   out.append(ch)
            }
        }
        return out
    }

    /// JS の文字列リテラルに差し込むため、`"` `\` 改行を最低限エスケープする。
    /// ephemeral token は hex のみなので素通しでも実害は無いが、将来別形式の
    /// トークンに切り替えたとき安全側に倒れるよう sanitize しておく。
    static func sanitizeForJSON(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for ch in s {
            switch ch {
            case "\\": out.append("\\\\")
            case "\"": out.append("\\\"")
            case "\n": out.append("\\n")
            case "\r": out.append("\\r")
            case "\t": out.append("\\t")
            case "<":  out.append("\\u003c") // </script> 対策
            case ">":  out.append("\\u003e")
            case "&":  out.append("\\u0026")
            default:   out.append(ch)
            }
        }
        return out
    }
}
