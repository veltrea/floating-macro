import Foundation

/// Thin helper to retrieve static assets from the bundle for Web Panel.
///
/// The asset is placed in `Sources/FloatingMacroCore/Resources/webpanel/`.
/// `.copy("Resources/webpanel")` declared in `Package.swift`.
/// Use `.copy` to preserve directory structure (flattened with `.process`)
/// Bundle.module.url(forResource:subdirectory:) is no longer available.)。
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

    /// Read the bytes of an asset from a bundle. Return nil if not found.
    public static func data(_ kind: AssetKind) -> Data? {
        // Background notes:
        // Initially `Bundle.module.url(forResource:withExtension:subdirectory:)` to
        // Using the one that was running, AppKit application execution context (= ControlServer of )
        // The phenomenon of becoming unresponsive when calling from a handler via main was reproduced.
        // The bundle's own URL also stops. SwiftPM automatic generation
        // The first access to the lazy-loaded `.module` by `resource_bundle_accessor`.
        // caused by that.
        //
        // Avoidance strategy: Directly search for candidate directories. Do not use `Bundle.module` at all.
        for url in resolveAssetURLs(fileName: kind.fileName) {
            if FileManager.default.fileExists(atPath: url.path) {
                return try? Data(contentsOf: url)
            }
        }
        return nil
    }

    /// Return asset candidate URLs in priority order: .app, /CLI/, /xctest/, Linux SwiftPM.
    /// Absorb layout differences all at once.
    private static func resolveAssetURLs(fileName: String) -> [URL] {
        let bundleName = "FloatingMacro_FloatingMacroCore.bundle"
        var candidateBundles: [URL] = [
            // The regular configuration of .app: <App>.app/Contents/Resources/<bundle>
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/\(bundleName)"),
            // Default CLI / SwiftPM: <main>/<bundle>
            Bundle.main.bundleURL.appendingPathComponent(bundleName),
            // XCTest, etc., patterns in the parent directory of Bundle.main's bundle.
            Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent(bundleName),
        ]
        // Add bundles that have the same suffix as bundleName by looking at Bundle.allBundles.
        // In XCTest, the test target loads the core module that contains the tests.
        // The resource bundle is registered here.
        for b in Bundle.allBundles where b.bundleURL.lastPathComponent == bundleName {
            candidateBundles.append(b.bundleURL)
        }
        return candidateBundles.map {
            $0.appendingPathComponent("webpanel", isDirectory: true)
              .appendingPathComponent(fileName)
        }
    }

    /// Old signature. Leave for cases where you want to replace the bundle in tests.
    static func data(_ kind: AssetKind, from bundle: Bundle) -> Data? {
        let url = bundle.bundleURL
            .appendingPathComponent("webpanel", isDirectory: true)
            .appendingPathComponent(kind.fileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return try? Data(contentsOf: url)
    }

    /// Replace placeholders with the following HTML content:
    /// Ephemeral LAN token (JavaScript literal-safe)
    /// `{{PRESET_JSON}}` preset full JSON literal (can be read directly from JS)
    /// Display name of the preset (HTML escaped)
    /// `skeleton group + initial button DOM`
    ///
    /// Completing the initial HTML with SSR allows JS to fetch `preset_get`.
    /// Can delete one round trip. Header and card layout reach HTML.
    /// Immediately painted afterwards.
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

    /// Test for specifying any bundle.
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

    /// Minimum escaping to embed text directly into the HTML <body>.
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

    /// To insert into a JS string literal, escape only the minimum: " \ newline.
    /// ephemeral token is only in hex, so even if bypassed there's no real damage, but future different formats may pose issues.
    /// When switching to tokens, make sure to sanitize and ensure it falls on the safe side.
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
            case "<":  out.append("\\u003c") // Precautions against XSS
            case ">":  out.append("\\u003e")
            case "&":  out.append("\\u0026")
            default:   out.append(ch)
            }
        }
        return out
    }
}
