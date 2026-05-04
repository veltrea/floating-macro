import XCTest
@testable import FloatingMacroCore

final class IconAssetSaverTests: XCTestCase {

    /// Tests use a tmp `applicationSupportDirectory` so the real user
    /// `~/Library/Application Support/FloatingMacro` is never touched.

    func testSaveDataWritesToExpectedLocation() throws {
        let support = try makeTempSupportDir()
        defer { try? FileManager.default.removeItem(at: support) }

        let pngBytes = makePngHeader()
        let savedPath = try IconAssetSaver.saveData(
            pngBytes,
            buttonId: "btn-001",
            presetName: "test-preset",
            applicationSupportDirectory: support
        )

        let expected = support
            .appendingPathComponent("FloatingMacro/presets/test-preset/icons/btn-001.png")
        XCTAssertEqual(savedPath, expected.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: savedPath))

        let readBack = try Data(contentsOf: URL(fileURLWithPath: savedPath))
        XCTAssertEqual(readBack, pngBytes)
    }

    func testSaveDataCreatesIntermediateDirectories() throws {
        let support = try makeTempSupportDir()
        defer { try? FileManager.default.removeItem(at: support) }
        // No FloatingMacro/presets/... yet — saver must mkdir -p.

        _ = try IconAssetSaver.saveData(
            makePngHeader(),
            buttonId: "btn-mkdirs",
            presetName: "deep/preset/name",
            applicationSupportDirectory: support
        )

        let dir = IconAssetSaver.iconsDirectory(
            presetName: "deep/preset/name",
            applicationSupportDirectory: support
        )
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)
    }

    func testSaveAppIconForCalculator() throws {
        let calc = URL(fileURLWithPath: "/System/Applications/Calculator.app")
        guard FileManager.default.fileExists(atPath: calc.path) else {
            throw XCTSkip("Calculator.app not present")
        }
        let support = try makeTempSupportDir()
        defer { try? FileManager.default.removeItem(at: support) }

        let savedPath = try IconAssetSaver.saveAppIcon(
            appURL: calc,
            buttonId: "btn-calc",
            presetName: "smoke",
            size: 64,
            applicationSupportDirectory: support
        )
        let data = try Data(contentsOf: URL(fileURLWithPath: savedPath))
        XCTAssertGreaterThan(data.count, 1000)
        XCTAssertEqual(Array(data.prefix(4)), [0x89, 0x50, 0x4E, 0x47],
                       "saved file should be a real PNG")
    }

    func testSaveAppIconBubblesExtractFailureForBogusApp() throws {
        let bogus = URL(fileURLWithPath: "/Applications/__no_such_app_for_iconassetsaver__.app")
        let support = try makeTempSupportDir()
        defer { try? FileManager.default.removeItem(at: support) }

        XCTAssertThrowsError(try IconAssetSaver.saveAppIcon(
            appURL: bogus,
            buttonId: "btn-x",
            presetName: "p",
            applicationSupportDirectory: support
        )) { err in
            guard case IconAssetSaver.SaveError.extractFailed = err else {
                XCTFail("expected .extractFailed, got: \(err)")
                return
            }
        }
    }

    // MARK: - Helpers

    private func makeTempSupportDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FmIconSaver-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Returns a tiny byte sequence with the PNG magic header. Not a
    /// valid full PNG, just enough to verify round-trip writes.
    private func makePngHeader() -> Data {
        Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
              // dummy payload
              0x00, 0x01, 0x02, 0x03])
    }
}
