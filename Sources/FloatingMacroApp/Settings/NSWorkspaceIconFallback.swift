import AppKit
import Foundation

/// AppKit を使ったアイコン取得フォールバック。
///
/// 主路線は `FloatingMacroCore.ImageIOIconExtractor` (`.icns` 直読み) だが、
/// SwiftUI 製のモダンアプリ (例: UTM) など `Contents/Resources/` に
/// `.icns` を持たず `Assets.car` のみで配布されているケースが現実に存在する。
/// この場合 ImageIO は失敗するので、`NSWorkspace.icon(forFile:)` で取得する。
///
/// - `NSWorkspace` は AppKit 依存だが、Apple 公式の長寿命 API (10.0 以来)。
///   Quick Look daemon のような外部プロセス依存もない。
/// - 出力速度は ms オーダー、Assets.car 内の AppIcon もシステムが解決して返す。
/// - このフォールバックは UI 層 (`FloatingMacroApp`) に閉じている。
///   `FloatingMacroCore` は Foundation + ImageIO のみのまま。
enum NSWorkspaceIconFallback {

    /// `appURL` のアイコンを正方形 PNG として取得する。
    /// nil を返すのは NSWorkspace 自体が失敗した場合のみ（事実上ほぼ起きない）。
    static func extractPNG(appURL: URL, size: Int) -> Data? {
        let nsImage = NSWorkspace.shared.icon(forFile: appURL.path)
        nsImage.size = NSSize(width: size, height: size)
        guard let tiff = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else { return nil }
        return png
    }
}
