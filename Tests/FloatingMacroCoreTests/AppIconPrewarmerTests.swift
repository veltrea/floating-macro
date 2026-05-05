import XCTest
import ImageIO
import CoreGraphics
@testable import FloatingMacroCore

final class AppIconPrewarmerTests: XCTestCase {

    /// 自作 stub `.app` を 3 つ用意し、AppListProvider 経由で
    /// AppIconPrewarmer を回す。ImageIO は icns 不在で失敗するので、
    /// 注入した NSWorkspace fallback closure が呼ばれてキャッシュに入ることを検証。
    func testPrewarmFillsCacheViaFallback() async throws {
        let cacheDir = try makeTempCacheDir()
        defer { try? FileManager.default.removeItem(at: cacheDir) }
        let cache = AppIconCache(cacheDirectory: cacheDir)

        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let bundleIds = ["com.example.pre.alpha", "com.example.pre.beta", "com.example.pre.gamma"]
        for (i, bid) in bundleIds.enumerated() {
            try makeStubApp(in: root, name: "App\(i).app", bundleId: bid)
        }

        let provider = FileSystemAppListProvider(searchRoots: [root])
        let prewarmer = AppIconPrewarmer()

        // fallback closure: アプリごとにマーカー違いの実 PNG (validator 通過用) を返す
        let fallback: @Sendable (URL, Int) -> Data? = { url, _ in
            let marker = UInt8(url.path.count % 250 + 5)  // > validator threshold (8)
            return Self.makeOpaquePNG(width: 8, height: 8, gray: marker)
        }

        await prewarmer.prewarm(
            provider: provider,
            nsWorkspaceFallback: fallback,
            size: 64,
            maxConcurrent: 2,
            cache: cache
        )

        // 全 app がキャッシュに入っているはず
        let entries = try provider.availableApplications()
        for entry in entries {
            let cached = await cache.contains(entry.url)
            XCTAssertTrue(cached,
                          "\(entry.url.lastPathComponent) should be cached")
        }
        let memCount = await cache.memoryCount()
        XCTAssertGreaterThanOrEqual(memCount, 3)
    }

    func testPrewarmSkipsAlreadyCached() async throws {
        let cacheDir = try makeTempCacheDir()
        defer { try? FileManager.default.removeItem(at: cacheDir) }
        let cache = AppIconCache(cacheDirectory: cacheDir)

        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try makeStubApp(in: root, name: "Cached.app", bundleId: "com.example.pre.cached")

        // 事前に手動でキャッシュに入れる (validator が通る本物 PNG)
        let entries = try FileSystemAppListProvider(searchRoots: [root]).availableApplications()
        let firstURL = entries.first!.url
        let preexisting = Self.makeOpaquePNG(width: 8, height: 8, gray: 0xAA)!
        await cache.put(for: firstURL, data: preexisting)

        // fallback が呼ばれたかカウント
        let counter = FallbackCounter()
        let fallback: @Sendable (URL, Int) -> Data? = { _, _ in
            Task { await counter.increment() }
            return Self.makeOpaquePNG(width: 8, height: 8, gray: 0xBB)
        }

        await AppIconPrewarmer().prewarm(
            provider: FileSystemAppListProvider(searchRoots: [root]),
            nsWorkspaceFallback: fallback,
            cache: cache
        )

        let calls = await counter.count
        XCTAssertEqual(calls, 0,
                       "既にキャッシュ済みなら fallback は呼ばれない")
        let after = await cache.get(for: firstURL)
        XCTAssertEqual(after, preexisting,
                       "既存キャッシュは上書きされない")
    }

    func testPrewarmHandlesEmptyProvider() async throws {
        let cacheDir = try makeTempCacheDir()
        defer { try? FileManager.default.removeItem(at: cacheDir) }
        let cache = AppIconCache(cacheDirectory: cacheDir)

        await AppIconPrewarmer().prewarm(
            provider: FileSystemAppListProvider(searchRoots: []),
            nsWorkspaceFallback: { _, _ in nil },
            cache: cache
        )
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

    private func makeTempRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FmPrewarm-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// 不透明グレー単色の本物 PNG bytes を作る (`IconContentValidator` 通過用)。
    /// `marker` は 1 バイトのグレー値で、テストごとに違う中身にしたい時に使う。
    static func makeOpaquePNG(width: Int, height: Int, gray: UInt8) -> Data? {
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            pixels[i]     = gray
            pixels[i + 1] = gray
            pixels[i + 2] = gray
            pixels[i + 3] = 255
        }
        guard let cs = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                  data: &pixels,
                  width: width, height: height,
                  bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                  space: cs,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let img = ctx.makeImage()
        else { return nil }
        let outData = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            outData, "public.png" as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(dest, img, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return outData as Data
    }

    private func makeStubApp(in root: URL, name: String, bundleId: String) throws {
        let url = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(
            at: url.appendingPathComponent("Contents"),
            withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": bundleId, "CFBundleName": name]
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: url.appendingPathComponent("Contents/Info.plist"))
    }
}

/// テスト用のスレッドセーフカウンタ
private actor FallbackCounter {
    private(set) var count: Int = 0
    func increment() { count += 1 }
}
