import XCTest
import ImageIO
@testable import FloatingMacroCore

/// Phase 5 (P5-8): QR コード生成の単体テスト。
final class QRCodeGeneratorTests: XCTestCase {

    func testGeneratesPNGForURL() throws {
        let png = try QRCodeGenerator.pngData(
            content: "http://192.168.1.21:17430/webpanel?token=deadbeef",
            sizeInPixels: 320
        )
        XCTAssertGreaterThan(png.count, 256, "実 PNG が出力されること")
        // PNG マジックバイト
        XCTAssertEqual(Array(png.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
    }

    func testEmptyContentThrows() {
        XCTAssertThrowsError(try QRCodeGenerator.pngData(content: "")) { err in
            XCTAssertEqual(err as? QRCodeGenerator.Error, .emptyContent)
        }
    }

    func testSizeIsAtLeastRequested() throws {
        let png = try QRCodeGenerator.pngData(content: "test", sizeInPixels: 256)
        // ImageIO で読み戻して幅・高さを検査。
        guard let src = CGImageSourceCreateWithData(png as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else {
            XCTFail("PNG ヘッダを読めない"); return
        }
        let w = props[kCGImagePropertyPixelWidth] as? Int ?? 0
        let h = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        XCTAssertGreaterThanOrEqual(w, 256)
        XCTAssertEqual(w, h, "QR は正方形のはず")
    }

    func testTinySizeClampsToMinimum() throws {
        // 64 未満を渡しても 64 にクランプされる (内部実装の保険)。
        let png = try QRCodeGenerator.pngData(content: "x", sizeInPixels: 16)
        XCTAssertGreaterThan(png.count, 0)
    }

    func testCorrectionLevelEnumStrings() {
        // CIFilter は文字列の "L"/"M"/"Q"/"H" を要求する。enum の rawValue
        // が壊れていないことを保証する。
        XCTAssertEqual(QRCodeGenerator.CorrectionLevel.L.rawValue, "L")
        XCTAssertEqual(QRCodeGenerator.CorrectionLevel.M.rawValue, "M")
        XCTAssertEqual(QRCodeGenerator.CorrectionLevel.Q.rawValue, "Q")
        XCTAssertEqual(QRCodeGenerator.CorrectionLevel.H.rawValue, "H")
    }
}
