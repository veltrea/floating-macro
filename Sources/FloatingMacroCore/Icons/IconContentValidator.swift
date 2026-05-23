import Foundation
import ImageIO
import CoreGraphics

/// Determines if the contents of an icon PNG are a "blank placeholder".
///
/// Why Necessary:
/// As seen in Books.app's `Contents/Resources/AppIcon.icns`, it appears to be normal.
/// icns but fully transparent case (alpha=0 and rgb=0)
/// Exists. When Apple converted to Catalyst and Assets.car, they said "the file format is"
/// Leave it empty while preserving its content. ImageIO decodes it directly as-is.
/// Return a "successful PNG" of only the PNG byte size, so it returns 460 bytes.
/// Even if the failure judgment passes through. The actual pixel content of the real image can be reliably detected.
///
/// Inspection content:
/// Decode PNG bytes using a `CGImageSource`, then place it in an RGBA 8-bit bitmap context.
/// Draw and read pixel array. If any pixel's alpha is greater than the threshold,
/// If max(R, G, B) > threshold, determine that it has content (early-return).
/// Returns false if all pixels are empty.
///
/// Design judgment:
/// Foundation + ImageIO + CoreGraphics only (AppKit-independent)
/// If even one color is found, return true and exit. Normal apps usually have 1 to a few pixels.
/// decode can be used. Only full pixel scanning occurs for empty icons (Books and others), however,
/// 128x128 = 16,384 pixel loop in sub-millisecond
public enum IconContentValidator {

    /// If even one pixel exceeds this value, an "contains content" determination is made.
    /// The reason for setting the value to a level of about 1-3, which is derived from antialias, is to treat it as "essentially empty".
    public static let defaultThreshold: UInt8 = 8

    /// Returns true if a valid image is drawn from the PNG bytes.
    /// Cannot be decoded as PNG; size zero, etc., are treated as empty (false).
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

    /// Directly accepts `CGImage` version. To be callable from within `ImageIOIconExtractor`.
    /// Published
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
            return true  // Pass through when color space acquisition fails for false positive avoidance
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
            return true  // Context creation failure also similar
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Early loop exit - The normal icon usually exits in a few pixels.
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
