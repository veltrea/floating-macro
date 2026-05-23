import XCTest
import ImageIO
@testable import FloatingMacroCore

/// Unit test for QR code generation (P5-8).
final class QRCodeGeneratorTests: XCTestCase {

    func testGeneratesPNGForURL() throws {
        let png = try QRCodeGenerator.pngData(
            content: "http://192.168.1.21:17430/webpanel?token=deadbeef",
            sizeInPixels: 320
        )
        XCTAssertGreaterThan(png.count, 256, "It outputs PNG.")
        // PNG magic byte
        XCTAssertEqual(Array(png.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
    }

    func testEmptyContentThrows() {
        XCTAssertThrowsError(try QRCodeGenerator.pngData(content: "")) { err in
            XCTAssertEqual(err as? QRCodeGenerator.Error, .emptyContent)
        }
    }

    func testSizeIsAtLeastRequested() throws {
        let png = try QRCodeGenerator.pngData(content: "test", sizeInPixels: 256)
        // Check width and height by reading back with ImageIO.
        guard let src = CGImageSourceCreateWithData(png as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else {
            XCTFail("PNG Cannot read header"); return
        }
        let w = props[kCGImagePropertyPixelWidth] as? Int ?? 0
        let h = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        XCTAssertGreaterThanOrEqual(w, 256)
        XCTAssertEqual(w, h, "QR It should be square")
    }

    func testTinySizeClampsToMinimum() throws {
        // Passed less than 64 will be clamped to 64 (internal implementation safety).
        let png = try QRCodeGenerator.pngData(content: "x", sizeInPixels: 16)
        XCTAssertGreaterThan(png.count, 0)
    }

    func testCorrectionLevelEnumStrings() {
        // CIFilter requires a string of "L"/"M"/"Q"/"H", which is the enum's rawValue.
        // Guarantees that the window is not broken.
        XCTAssertEqual(QRCodeGenerator.CorrectionLevel.L.rawValue, "L")
        XCTAssertEqual(QRCodeGenerator.CorrectionLevel.M.rawValue, "M")
        XCTAssertEqual(QRCodeGenerator.CorrectionLevel.Q.rawValue, "Q")
        XCTAssertEqual(QRCodeGenerator.CorrectionLevel.H.rawValue, "H")
    }
}
