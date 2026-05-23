import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Pure functions to convert strings to QR code PNGs.
///
/// Distribution policy without in-product AI, same philosophy as.
/// Use only the `CIFilter.qrCodeGenerator` foundation API. AppKit and
/// Testable with Core without depending on SwiftUI.
public enum QRCodeGenerator {

    /// Error correction level of QR codes. L ≈ 7%, M ≈ 15%, Q ≈ 25%, H ≈ 30%. Restorable.
    /// The LAN URL should be short and readable within close proximity, so M is sufficient.
    public enum CorrectionLevel: String {
        case L, M, Q, H
    }

    public enum Error: Swift.Error, Equatable {
        case emptyContent
        case filterUnavailable
        case ciImageRenderFailed
        case pngEncodeFailed
    }

    /// Returns PNG bytes after encoding the string.
    /// - Parameters:
    /// Embed string (URL assumed). Encode in UTF-8.
    /// sizeInPixels: Output the side length of the PNG in pixels. Minimum 64, recommended above 320.
    /// correction: error level.
    public static func pngData(content: String,
                               sizeInPixels: Int = 480,
                               correction: CorrectionLevel = .M) throws -> Data {
        guard !content.isEmpty else { throw Error.emptyContent }
        let size = max(64, sizeInPixels)

        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(content.utf8)
        filter.correctionLevel = correction.rawValue
        guard let raw = filter.outputImage else { throw Error.filterUnavailable }

        // The CIFilter returns a small image, typically around 23x23 pixels in size, for the purpose of...
        // Scaling with integer scaling ratios for size. Keeping it as an integer ratio preserves the quality of the QR code.
        // Module boundaries remain clear and sharp (smartphone camera reading)
        // Success rate increases).
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
