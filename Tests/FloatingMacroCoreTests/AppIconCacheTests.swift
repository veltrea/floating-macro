import XCTest
@testable import FloatingMacroCore

final class AppIconCacheTests: XCTestCase {

    func testPutThenGetReturnsSameBytes() async throws {
        let cacheDir = try makeTempCacheDir()
        defer { try? FileManager.default.removeItem(at: cacheDir) }
        let cache = AppIconCache(cacheDirectory: cacheDir)

        let stub = try makeStubApp(bundleId: "com.example.cache.test1")
        defer { try? FileManager.default.removeItem(at: stub) }

        let payload = makePngBytes(marker: 0x01)
        await cache.put(for: stub, data: payload)

        let got = await cache.get(for: stub)
        XCTAssertEqual(got, payload)
    }

    func testContainsReportsTrueAfterPut() async throws {
        let cacheDir = try makeTempCacheDir()
        defer { try? FileManager.default.removeItem(at: cacheDir) }
        let cache = AppIconCache(cacheDirectory: cacheDir)

        let stub = try makeStubApp(bundleId: "com.example.cache.contains")
        defer { try? FileManager.default.removeItem(at: stub) }

        let before = await cache.contains(stub)
        XCTAssertFalse(before)

        await cache.put(for: stub, data: makePngBytes(marker: 0x02))

        let after = await cache.contains(stub)
        XCTAssertTrue(after)
    }

    func testGetReturnsNilForUnknownApp() async throws {
        let cacheDir = try makeTempCacheDir()
        defer { try? FileManager.default.removeItem(at: cacheDir) }
        let cache = AppIconCache(cacheDirectory: cacheDir)

        let stub = try makeStubApp(bundleId: "com.example.cache.unknown")
        defer { try? FileManager.default.removeItem(at: stub) }

        let result = await cache.get(for: stub)
        XCTAssertNil(result)
    }

    func testMtimeInvalidationForcesReextraction() async throws {
        let cacheDir = try makeTempCacheDir()
        defer { try? FileManager.default.removeItem(at: cacheDir) }
        let cache = AppIconCache(cacheDirectory: cacheDir)

        let stub = try makeStubApp(bundleId: "com.example.cache.mtime")
        defer { try? FileManager.default.removeItem(at: stub) }

        await cache.put(for: stub, data: makePngBytes(marker: 0x03))
        let firstGet = await cache.get(for: stub)
        XCTAssertNotNil(firstGet)

        // アプリの mtime を 1 時間進める = アプリ更新を simulate
        let future = Date().addingTimeInterval(3600)
        try FileManager.default.setAttributes(
            [.modificationDate: future], ofItemAtPath: stub.path)

        let stale = await cache.get(for: stub)
        XCTAssertNil(stale, "アプリ mtime > キャッシュ mtime のとき再抽出を促すため nil を返すべき")
    }

    func testDiskCachePromotesToMemoryAcrossInstances() async throws {
        let cacheDir = try makeTempCacheDir()
        defer { try? FileManager.default.removeItem(at: cacheDir) }
        let stub = try makeStubApp(bundleId: "com.example.cache.disk")
        defer { try? FileManager.default.removeItem(at: stub) }

        let payload = makePngBytes(marker: 0x04)
        do {
            let cache = AppIconCache(cacheDirectory: cacheDir)
            await cache.put(for: stub, data: payload)
        }
        // 別インスタンス (メモリは空) でも、ディスクから読めて昇格する
        let cache2 = AppIconCache(cacheDirectory: cacheDir)
        let countBefore = await cache2.memoryCount()
        XCTAssertEqual(countBefore, 0)
        let got = await cache2.get(for: stub)
        XCTAssertEqual(got, payload)
        let countAfter = await cache2.memoryCount()
        XCTAssertEqual(countAfter, 1, "ディスクヒット後はメモリに昇格")
    }

    func testClearWipesBothMemoryAndDisk() async throws {
        let cacheDir = try makeTempCacheDir()
        defer { try? FileManager.default.removeItem(at: cacheDir) }
        let cache = AppIconCache(cacheDirectory: cacheDir)
        let stub = try makeStubApp(bundleId: "com.example.cache.clear")
        defer { try? FileManager.default.removeItem(at: stub) }

        await cache.put(for: stub, data: makePngBytes(marker: 0x05))
        let beforeClear = await cache.get(for: stub)
        XCTAssertNotNil(beforeClear)

        await cache.clear()

        let afterClear = await cache.get(for: stub)
        XCTAssertNil(afterClear)
        let count = await cache.memoryCount()
        XCTAssertEqual(count, 0)
    }

    // MARK: - Helpers

    private func makeTempCacheDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FmIconCache-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeStubApp(bundleId: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FmCacheStub-\(UUID().uuidString).app")
        try FileManager.default.createDirectory(
            at: url.appendingPathComponent("Contents"),
            withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": bundleId]
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: url.appendingPathComponent("Contents/Info.plist"))
        return url
    }

    /// PNG の magic + 1 バイトのマーカー (テスト用)。実 PNG ではないが
    /// キャッシュは bytes をそのまま透過するので bytes 等価比較に十分。
    private func makePngBytes(marker: UInt8) -> Data {
        Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, marker])
    }
}
