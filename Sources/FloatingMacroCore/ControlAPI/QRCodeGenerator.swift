import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Phase 5 (P5-8): 文字列を QR コード PNG に変換する純粋関数群。
///
/// 配布物に AI を内蔵しない方針 (`feedback_no_inproduct_ai`) と同じ思想で、
/// `CIFilter.qrCodeGenerator` という基盤系 API のみを使う。AppKit や
/// SwiftUI には依存せず、Core でテスト可能。
public enum QRCodeGenerator {

    /// QR の誤り訂正レベル。L → 約 7%、M → 15%、Q → 25%、H → 30% 復元可能。
    /// LAN URL は短く、近距離で読まれる前提なので M で十分。
    public enum CorrectionLevel: String {
        case L, M, Q, H
    }

    public enum Error: Swift.Error, Equatable {
        case emptyContent
        case filterUnavailable
        case ciImageRenderFailed
        case pngEncodeFailed
    }

    /// 文字列をエンコードして PNG bytes を返す。
    /// - Parameters:
    ///   - content: 埋め込む文字列 (URL 想定)。UTF-8 でエンコードする。
    ///   - sizeInPixels: 出力 PNG の 1 辺 (px)。最小 64、推奨 320 以上。
    ///   - correction: 誤り訂正レベル。
    public static func pngData(content: String,
                               sizeInPixels: Int = 480,
                               correction: CorrectionLevel = .M) throws -> Data {
        guard !content.isEmpty else { throw Error.emptyContent }
        let size = max(64, sizeInPixels)

        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(content.utf8)
        filter.correctionLevel = correction.rawValue
        guard let raw = filter.outputImage else { throw Error.filterUnavailable }

        // CIFilter は小さい (大体 23×23 ピクセル程度) 画像を返すので、目的
        // サイズに整数倍率でスケーリングする。整数倍率にしておくと QR の
        // モジュール境界がぼやけずシャープになる (= スマホカメラの読み取り
        // 成功率が上がる)。
        let scale = max(1.0, Double(size) / Double(Int(raw.extent.width)))
        let scaled = raw.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let context = CIContext(options: [.outputPremultiplied: true])
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else {
            throw Error.ciImageRenderFailed
        }
        return try encodePNG(cg)
    }

    private static func encodePNG(_ cg: CGImage) throws -> Data {
        let mutable = NSMutableData()
        let utType: CFString
        if #available(macOS 11.0, *) {
            utType = UTType.png.identifier as CFString
        } else {
            utType = "public.png" as CFString
        }
        guard let dest = CGImageDestinationCreateWithData(mutable, utType, 1, nil) else {
            throw Error.pngEncodeFailed
        }
        CGImageDestinationAddImage(dest, cg, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw Error.pngEncodeFailed
        }
        return mutable as Data
    }
}
