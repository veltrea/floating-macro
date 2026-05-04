import Foundation

/// `/Applications` 配下の全アプリのアイコンをバックグラウンドで抽出して
/// `AppIconCache` に放り込んでおく。FloatingMacro 起動時に一度だけ走らせれば
/// 「アプリピッカーを開いた瞬間にアイコンが揃っている」状態になる。
///
/// Cascade:
///   1. ImageIO で `.icns` 直読み (Foundation のみ、ms オーダー)
///   2. 失敗したら呼び出し側から渡された NSWorkspace fallback closure を試す
///      (Assets.car-only のモダンアプリ — UTM など — を救済)
///
/// AppKit 依存を Core に持ち込まないため、NSWorkspace fallback は closure で
/// 注入する設計にしてある。`FloatingMacroApp` 側で `NSWorkspaceIconFallback`
/// を bind して呼ぶ。
public struct AppIconPrewarmer {

    public init() {}

    /// `/Applications` 等を列挙し、未キャッシュのアプリだけアイコン抽出する。
    /// - Parameters:
    ///   - provider: アプリ列挙元 (デフォルト: 標準ロケーション)
    ///   - extractor: 1st 試行の Foundation-only 抽出器
    ///   - nsWorkspaceFallback: 1st 失敗時の AppKit fallback closure
    ///       (`url, size -> Data?`)。nil なら fallback しない (テスト用)
    ///   - size: キャッシュに入れる PNG の長辺 px。128 が UI と CHANGELOG での既定
    ///   - maxConcurrent: 並列抽出数。CPU を食い荒らさないよう控えめに
    ///   - cache: キャッシュ実体 (デフォルト: shared)
    public func prewarm(
        provider: AppListProvider = FileSystemAppListProvider(),
        extractor: ImageIOIconExtractor = ImageIOIconExtractor(),
        nsWorkspaceFallback: (@Sendable (URL, Int) -> Data?)? = nil,
        size: Int = 128,
        maxConcurrent: Int = 4,
        cache: AppIconCache = .shared
    ) async {
        guard let entries = try? provider.availableApplications() else { return }

        // セマフォ的な並列度制御を TaskGroup + counter で実現。
        // Swift 5.9 環境で素直に書ける形。
        await withTaskGroup(of: Void.self) { group in
            var inflight = 0
            var iterator = entries.makeIterator()

            // 初期投入
            while inflight < maxConcurrent, let entry = iterator.next() {
                group.addTask {
                    await Self.prewarmOne(
                        entry: entry,
                        extractor: extractor,
                        nsWorkspaceFallback: nsWorkspaceFallback,
                        size: size,
                        cache: cache)
                }
                inflight += 1
            }

            // 完了するたびに次を投入
            for await _ in group {
                if let entry = iterator.next() {
                    group.addTask {
                        await Self.prewarmOne(
                            entry: entry,
                            extractor: extractor,
                            nsWorkspaceFallback: nsWorkspaceFallback,
                            size: size,
                            cache: cache)
                    }
                }
            }
        }
    }

    private static func prewarmOne(
        entry: AppEntry,
        extractor: ImageIOIconExtractor,
        nsWorkspaceFallback: (@Sendable (URL, Int) -> Data?)?,
        size: Int,
        cache: AppIconCache
    ) async {
        // self-healing: 既にキャッシュ済みでも、中身が薄い (Books の icns のように
        // ImageIO で「成功」したが完全透明だったケース) なら再抽出する。
        // 通常のアプリは IconContentValidator が早期 return で抜けるので軽い。
        if let existing = await cache.get(for: entry.url),
           IconContentValidator.hasMeaningfulContent(pngData: existing) {
            return
        }

        // 1st: ImageIO + 内容検査 → 失敗扱いなら次へ
        if let data = try? extractor.extractPNG(from: entry.url, size: size),
           IconContentValidator.hasMeaningfulContent(pngData: data) {
            await cache.put(for: entry.url, data: data)
            return
        }
        // 2nd: NSWorkspace fallback (closure 経由) — 中身検査も同じく適用
        if let fb = nsWorkspaceFallback,
           let data = fb(entry.url, size),
           IconContentValidator.hasMeaningfulContent(pngData: data) {
            await cache.put(for: entry.url, data: data)
        }
    }
}
