import XCTest
import ImageIO
import CoreGraphics
@testable import FloatingMacroCore

final class IconContentValidatorTests: XCTestCase {

    func testRejectsEmptyData() {
        XCTAssertFalse(IconContentValidator.hasMeaningfulContent(pngData: Data()))
    }

    func testRejectsGarbageBytes() {
        let bogus = Data([0x00, 0x01, 0x02, 0x03, 0x04, 0x05])
        XCTAssertFalse(IconContentValidator.hasMeaningfulContent(pngData: bogus))
    }

    func testAcceptsRealPNGWithContent() throws {
        // Create a 16x16 red opaque PNG
        let png = try makeSolidColorPNG(width: 16, height: 16, r: 255, g: 0, b: 0, a: 255)
        XCTAssertTrue(IconContentValidator.hasMeaningfulContent(pngData: png))
    }

    func testRejectsFullyTransparentPNG() throws {
        // All pixels are alpha=0 transparent PNGs (equivalent to Books' icns internal representation).
        let png = try makeSolidColorPNG(width: 32, height: 32, r: 0, g: 0, b: 0, a: 0)
        XCTAssertFalse(IconContentValidator.hasMeaningfulContent(pngData: png))
    }

    func testAcceptsPNGWithSinglePixel() throws {
        // almost transparent but just one with alpha=255
        let cgImage = try makeCGImageWithSingleOpaquePixel(width: 32, height: 32)
        XCTAssertTrue(IconContentValidator.hasMeaningfulContent(cgImage: cgImage))
    }

    func testThresholdCaptures1And2AsEmpty() throws {
        // All pixels with alpha=1 (antialias remnants) are treated as empty at threshold=8.
        let png = try makeSolidColorPNG(width: 16, height: 16, r: 0, g: 0, b: 0, a: 1)
        XCTAssertFalse(IconContentValidator.hasMeaningfulContent(pngData: png))
    }

    func testRealCalculatorIconHasContent() throws {
        let calc = URL(fileURLWithPath: "/System/Applications/Calculator.app")
        guard FileManager.default.fileExists(atPath: calc.path) else {
            throw XCTSkip("Calculator.app not present")
        }
        let png = try ImageIOIconExtractor().extractPNG(from: calc, size: 128)
        XCTAssertTrue(IconContentValidator.hasMeaningfulContent(pngData: png))
    }

    func testRealBooksIconIsRejectedAsEmpty() throws {
        let books = URL(fileURLWithPath: "/System/Applications/Books.app")
        guard FileManager.default.fileExists(atPath: books.path) else {
            throw XCTSkip("Books.app not present")
        }
        // PNG obtained via ImageIO is fully transparent (verified on device: alpha=0, RGB=0).
        let png = try ImageIOIconExtractor().extractPNG(from: books, size: 128)
        XCTAssertFalse(IconContentValidator.hasMeaningfulContent(pngData: png),
                       "Books.app の icns は空プレースホルダ → validator が reject すべき")
    }

    // MARK: - Helpers

    private func makeSolidColorPNG(width: Int, height: Int,
                                   r: UInt8, g: UInt8, b: UInt8, a: UInt8) throws -> Data {
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            // premultipliedLast: bytes are RGBA with R/G/B premultiplied by alpha
            let af = Double(a) / 255.0
            pixels[i]     = UInt8(Double(r) * af)
            pixels[i + 1] = UInt8(Double(g) * af)
            pixels[i + 2] = UInt8(Double(b) * af)
            pixels[i + 3] = a
        }
        return try encodePNG(pixels: &pixels, width: width, height: height)
    }

    private func makeCGImageWithSingleOpaquePixel(width: Int, height: Int) throws -> CGImage {
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        // completely opaque white at exactly one pixel in the center
        let centerY = height / 2
        let centerX = width / 2
        let base = (centerY * width + centerX) * 4
        pixels[base] = 255; pixels[base + 1] = 255; pixels[base + 2] = 255; pixels[base + 3] = 255
        return try makeCGImage(pixels: &pixels, width: width, height: height)
    }

    private func encodePNG(pixels: inout [UInt8], width: Int, height: Int) throws -> Data {
        let cgImage = try makeCGImage(pixels: &pixels, width: width, height: height)
        let outData = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            outData, "public.png" as CFString, 1, nil
        ) else {
            throw NSError(domain: "TestPNG", code: 1)
        }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw NSError(domain: "TestPNG", code: 2)
        }
        return outData as Data
    }

    private func makeCGImage(pixels: inout [UInt8], width: Int, height: Int) throws -> CGImage {
        let bytesPerRow = width * 4
        guard let cs = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                  data: &pixels,
                  width: width, height: height,
                  bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                  space: cs,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let img = ctx.makeImage()
        else {
            throw NSError(domain: "TestPNG", code: 3)
        }
        return img
    }
}
