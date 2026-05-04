import Foundation
import ImageIO
import CoreGraphics

/// アイコン PNG の中身が「空プレースホルダ」かどうかを判定する。
///
/// なぜ必要か:
///   Books.app の `Contents/Resources/AppIcon.icns` のように、見かけは正常な
///   icns だが全 representation が完全に透明 (`alpha=0` かつ `rgb=0`) のケースが
///   存在する。Apple が Catalyst 化や Assets.car 化のときに「ファイル形式は
///   残しつつ中身を空にした」プレースホルダ。ImageIO は素直にそれを decode
///   して 460 バイトの「成功 PNG」を返してしまうので、PNG のバイトサイズだけで
///   失敗判定してもすり抜ける。実画像の **ピクセル内容** を見れば確実に検出できる。
///
/// 検査内容:
///   PNG bytes を `CGImageSource` で decode し、RGBA 8bit の bitmap context に
///   描画してピクセル配列を読む。1 ピクセルでも `alpha > threshold` または
///   `max(R,G,B) > threshold` に当たれば「中身がある」と判定 (early-return)。
///   全ピクセル空なら false を返す。
///
/// 設計判断:
///   - Foundation + ImageIO + CoreGraphics のみ (AppKit 非依存)
///   - 1 つでも色を見つけたら true で抜けるので、通常アプリは 1〜数 px の
///     decode で済む。空アイコン (Books 等) のときだけ全ピクセル走査になるが、
///     128x128 = 16384 pixels の loop で sub-millisecond
public enum IconContentValidator {

    /// 1 ピクセルでもこの値を超える alpha / RGB が見つかれば「中身あり」と判定。
    /// 8 にしているのは antialias 由来の 1〜3 程度の値を「実質空」と扱うため。
    public static let defaultThreshold: UInt8 = 8

    /// PNG bytes を見て、有効な絵が描かれているかどうかを返す。
    /// PNG として decode できない・サイズ 0 等は false (= 空扱い)。
    public static func hasMeaningfulContent(
        pngData: Data,
        threshold: UInt8 = defaultThreshold
    ) -> Bool {
        guard !pngData.isEmpty else { return false }
        guard let source = CGImageSourceCreateWithData(pngData as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return false
        }
        return hasMeaningfulContent(cgImage: cgImage, threshold: threshold)
    }

    /// `CGImage` を直接受け取る版。`ImageIOIconExtractor` の中から呼べるように
    /// 公開してある。
    public static func hasMeaningfulContent(
        cgImage: CGImage,
        threshold: UInt8 = defaultThreshold
    ) -> Bool {
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return false }

        let bytesPerRow = width * 4
        let totalBytes = bytesPerRow * height
        var pixelData = [UInt8](repeating: 0, count: totalBytes)

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            return true  // colorSpace 取得失敗時は誤検出回避で通す
        }
        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return true  // context 作成失敗時も同様
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // 早期 return ループ — 通常アイコンは数ピクセルで抜ける
        let total = width * height
        for i in 0..<total {
            let base = i * 4
            let alpha = pixelData[base + 3]
            if alpha > threshold { return true }
            let maxRGB = max(pixelData[base], pixelData[base + 1], pixelData[base + 2])
            if maxRGB > threshold { return true }
        }
        return false
    }
}
