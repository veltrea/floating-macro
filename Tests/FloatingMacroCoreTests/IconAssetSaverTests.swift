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

    /// Thumbnail saving for added card tabs in Phase 2.
    /// Returns the absolute path to `<name>/<buttonId>.<ext>` in `presets/`.
    func testSaveThumbnailWritesToImagesDirectory() throws {
        let support = try makeTempSupportDir()
        defer { try? FileManager.default.removeItem(at: support) }

        let payload = Data([0xFF, 0xD8, 0xFF, 0xE0]) // JPEG magic
        let savedPath = try IconAssetSaver.saveThumbnail(
            payload,
            buttonId: "btn-card-1",
            presetName: "midjourney",
            ext: "jpg",
            applicationSupportDirectory: support
        )

        let expected = support
            .appendingPathComponent("FloatingMacro/presets/midjourney/images/btn-card-1.jpg")
        XCTAssertEqual(savedPath, expected.path)
        let readBack = try Data(contentsOf: URL(fileURLWithPath: savedPath))
        XCTAssertEqual(readBack, payload)
    }

    /// Pure function `imagesDirectory(presetName:)`. Parallel path to `icons/`.
    func testImagesDirectoryPath() throws {
        let support = URL(fileURLWithPath: "/tmp/fm-saver-fake")
        let dir = IconAssetSaver.imagesDirectory(
            presetName: "demo",
            applicationSupportDirectory: support
        )
        XCTAssertEqual(
            dir.path,
            "/tmp/fm-saver-fake/FloatingMacro/presets/demo/images"
        )
    }

    /// File picker import: Copy original file to management directory
    /// Save under the preset folder and return the absolute path. The original file is preserved.
    func testCopyImageDuplicatesIntoPresetDirectory() throws {
        let support = try makeTempSupportDir()
        defer { try? FileManager.default.removeItem(at: support) }

        let source = support.appendingPathComponent("user-pic.png")
        let payload = makePngHeader()
        try payload.write(to: source)

        let savedPath = try IconAssetSaver.copyImage(
            from: source,
            into: .images,
            assetId: "btn-card-1",
            presetName: "gallery",
            applicationSupportDirectory: support
        )
        let expected = support
            .appendingPathComponent("FloatingMacro/presets/gallery/images/btn-card-1.png")
        XCTAssertEqual(savedPath, expected.path)
        // The original file is not deleted (it's a copy, not moved).
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        // The byte sequence of the destination matches exactly
        let copied = try Data(contentsOf: URL(fileURLWithPath: savedPath))
        XCTAssertEqual(copied, payload)
    }

    /// Extension is inherited from the original file. Do not re-encode PNG to PNG, JPEG to JPEG.
    func testCopyImagePreservesSourceExtension() throws {
        let support = try makeTempSupportDir()
        defer { try? FileManager.default.removeItem(at: support) }

        let source = support.appendingPathComponent("photo.JPG")
        let payload = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00])
        try payload.write(to: source)

        let saved = try IconAssetSaver.copyImage(
            from: source, into: .icons,
            assetId: "btn-photo",
            presetName: "p",
            applicationSupportDirectory: support
        )
        // The uppercase extension is normalized to lowercase.
        XCTAssertTrue(saved.hasSuffix("/icons/btn-photo.jpg"),
                      "expected .jpg suffix, got \(saved)")
    }

    /// If the same assetId is selected again, orphan files with the old extension will be deleted.
    /// Use case to replace PNG with JPEG.
    func testCopyImageRemovesPreviousAssetWithDifferentExtension() throws {
        let support = try makeTempSupportDir()
        defer { try? FileManager.default.removeItem(at: support) }

        let pngSource = support.appendingPathComponent("a.png")
        try makePngHeader().write(to: pngSource)
        let firstPath = try IconAssetSaver.copyImage(
            from: pngSource, into: .images,
            assetId: "btn-X", presetName: "p",
            applicationSupportDirectory: support
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstPath))

        let jpgSource = support.appendingPathComponent("b.jpg")
        try Data([0xFF, 0xD8, 0xFF, 0xE0]).write(to: jpgSource)
        let secondPath = try IconAssetSaver.copyImage(
            from: jpgSource, into: .images,
            assetId: "btn-X", presetName: "p",
            applicationSupportDirectory: support
        )
        XCTAssertTrue(secondPath.hasSuffix("btn-X.jpg"))
        // Old PNGs are no longer left as orphans and are removed.
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstPath),
                       "previous PNG should be removed when replaced by JPEG")
    }

    /// If the file has already been re-selected within the management directory, it is a no-op.
    /// To avoid failing to copy oneself onto oneself.
    func testCopyImageIsNoOpWhenSourceAlreadyInDestination() throws {
        let support = try makeTempSupportDir()
        defer { try? FileManager.default.removeItem(at: support) }

        // Create a file in the management directory for the first copy.
        let original = support.appendingPathComponent("orig.png")
        try makePngHeader().write(to: original)
        let saved = try IconAssetSaver.copyImage(
            from: original, into: .icons,
            assetId: "btn-loop", presetName: "p",
            applicationSupportDirectory: support
        )
        // Second time: Re-select copy as source in management directory
        let savedURL = URL(fileURLWithPath: saved)
        let again = try IconAssetSaver.copyImage(
            from: savedURL, into: .icons,
            assetId: "btn-loop", presetName: "p",
            applicationSupportDirectory: support
        )
        XCTAssertEqual(again, saved)
        XCTAssertTrue(FileManager.default.fileExists(atPath: again),
                      "no-op should not delete the file")
    }

    /// External absolute path → automatic migration to preset under SF Symbol / bundle id /.
    /// Already returns the path as-is if it exists in the management directory, does not exist, or is empty.
    func testMigrateExternalImagePathCopiesExternalAndKeepsManaged() throws {
        let support = try makeTempSupportDir()
        defer { try? FileManager.default.removeItem(at: support) }

        // Image file outside
        let external = support.appendingPathComponent("external.png")
        try makePngHeader().write(to: external)

        // External path → New path is returned after copying
        let migrated = IconAssetSaver.migrateExternalImagePath(
            external.path,
            into: .icons, assetId: "btn-1", presetName: "p",
            applicationSupportDirectory: support
        )
        XCTAssertNotNil(migrated)
        XCTAssertNotEqual(migrated, external.path,
                          "external path should have been migrated")
        XCTAssertTrue(migrated?.contains("/icons/btn-1") ?? false)

        // 2. Paths already in the management directory pass through unchanged.
        let again = IconAssetSaver.migrateExternalImagePath(
            migrated,
            into: .icons, assetId: "btn-1", presetName: "p",
            applicationSupportDirectory: support
        )
        XCTAssertEqual(again, migrated, "managed paths must be a no-op")

        // 3. SF Symbol bypasses
        let sf = IconAssetSaver.migrateExternalImagePath(
            "sf:star.fill",
            into: .icons, assetId: "btn-2", presetName: "p",
            applicationSupportDirectory: support
        )
        XCTAssertEqual(sf, "sf:star.fill")

        // 4. bundle id is skipped
        let bid = IconAssetSaver.migrateExternalImagePath(
            "com.apple.Safari",
            into: .icons, assetId: "btn-3", presetName: "p",
            applicationSupportDirectory: support
        )
        XCTAssertEqual(bid, "com.apple.Safari")

        // 5. Non-existent paths are skipped (without tampering with broken links)
        let missing = IconAssetSaver.migrateExternalImagePath(
            "/tmp/does-not-exist-fm.png",
            into: .icons, assetId: "btn-4", presetName: "p",
            applicationSupportDirectory: support
        )
        XCTAssertEqual(missing, "/tmp/does-not-exist-fm.png")

        // 6. nil / empty string as-is
        XCTAssertNil(IconAssetSaver.migrateExternalImagePath(
            nil, into: .icons, assetId: "btn-5", presetName: "p",
            applicationSupportDirectory: support))
        XCTAssertEqual(IconAssetSaver.migrateExternalImagePath(
            "", into: .icons, assetId: "btn-5", presetName: "p",
            applicationSupportDirectory: support), "")
    }

    func testCopyImageThrowsWhenSourceDoesNotExist() throws {
        let support = try makeTempSupportDir()
        defer { try? FileManager.default.removeItem(at: support) }

        let bogus = support.appendingPathComponent("nonexistent.png")
        XCTAssertThrowsError(try IconAssetSaver.copyImage(
            from: bogus, into: .icons,
            assetId: "btn-x", presetName: "p",
            applicationSupportDirectory: support
        )) { err in
            guard case IconAssetSaver.SaveError.sourceNotReadable = err else {
                XCTFail("expected .sourceNotReadable, got: \(err)")
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
