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

    /// Phase 2 で追加された card タブ用サムネイル保存。
    /// `presets/<name>/images/<buttonId>.<ext>` に書き、絶対パスを返す。
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

    /// `imagesDirectory(presetName:)` の純粋関数。`icons/` と並列のパス。
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

    /// ファイルピッカー経由の取り込み: 元ファイルを管理ディレクトリに「コピー」
    /// して preset 配下に保存し、絶対パスを返す。元ファイルは保持される。
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
        // 元ファイルは消えていない (コピーであって移動ではない)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        // コピー先のバイト列が完全一致
        let copied = try Data(contentsOf: URL(fileURLWithPath: savedPath))
        XCTAssertEqual(copied, payload)
    }

    /// 拡張子は元ファイルから引き継ぐ。PNG → PNG、JPEG → JPEG で再エンコードしない。
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
        // 大文字拡張子は小文字に正規化される
        XCTAssertTrue(saved.hasSuffix("/icons/btn-photo.jpg"),
                      "expected .jpg suffix, got \(saved)")
    }

    /// 同じ assetId で再選択すると、旧拡張子の orphan ファイルは削除される。
    /// PNG → JPEG に差し替えるユースケース。
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
        // 旧 PNG は orphan として残らず削除されている
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstPath),
                       "previous PNG should be removed when replaced by JPEG")
    }

    /// 既に管理ディレクトリ内のファイルを再選択した場合は no-op
    /// (自分自身を自分自身にコピーしようとして失敗するのを避ける)。
    func testCopyImageIsNoOpWhenSourceAlreadyInDestination() throws {
        let support = try makeTempSupportDir()
        defer { try? FileManager.default.removeItem(at: support) }

        // 1 回目のコピーで管理ディレクトリ内にファイルを作る
        let original = support.appendingPathComponent("orig.png")
        try makePngHeader().write(to: original)
        let saved = try IconAssetSaver.copyImage(
            from: original, into: .icons,
            assetId: "btn-loop", presetName: "p",
            applicationSupportDirectory: support
        )
        // 2 回目: 管理ディレクトリ内のコピーをソースとして再選択
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

    /// 外部絶対パス → preset 配下へ自動移行。SF Symbol / bundle id /
    /// 既に管理ディレクトリ内のパス / 存在しないパス・空はそのまま返る。
    func testMigrateExternalImagePathCopiesExternalAndKeepsManaged() throws {
        let support = try makeTempSupportDir()
        defer { try? FileManager.default.removeItem(at: support) }

        // 外部にある画像ファイル
        let external = support.appendingPathComponent("external.png")
        try makePngHeader().write(to: external)

        // 1. 外部パス → コピーされて新パスが返る
        let migrated = IconAssetSaver.migrateExternalImagePath(
            external.path,
            into: .icons, assetId: "btn-1", presetName: "p",
            applicationSupportDirectory: support
        )
        XCTAssertNotNil(migrated)
        XCTAssertNotEqual(migrated, external.path,
                          "external path should have been migrated")
        XCTAssertTrue(migrated?.contains("/icons/btn-1") ?? false)

        // 2. 既に管理ディレクトリ内のパスは素通り
        let again = IconAssetSaver.migrateExternalImagePath(
            migrated,
            into: .icons, assetId: "btn-1", presetName: "p",
            applicationSupportDirectory: support
        )
        XCTAssertEqual(again, migrated, "managed paths must be a no-op")

        // 3. SF Symbol は素通り
        let sf = IconAssetSaver.migrateExternalImagePath(
            "sf:star.fill",
            into: .icons, assetId: "btn-2", presetName: "p",
            applicationSupportDirectory: support
        )
        XCTAssertEqual(sf, "sf:star.fill")

        // 4. bundle id は素通り
        let bid = IconAssetSaver.migrateExternalImagePath(
            "com.apple.Safari",
            into: .icons, assetId: "btn-3", presetName: "p",
            applicationSupportDirectory: support
        )
        XCTAssertEqual(bid, "com.apple.Safari")

        // 5. 存在しないパスは素通り (リンク切れを勝手に操作しない)
        let missing = IconAssetSaver.migrateExternalImagePath(
            "/tmp/does-not-exist-fm.png",
            into: .icons, assetId: "btn-4", presetName: "p",
            applicationSupportDirectory: support
        )
        XCTAssertEqual(missing, "/tmp/does-not-exist-fm.png")

        // 6. nil / 空文字列はそのまま
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
