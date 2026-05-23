import Foundation

/// Extract icons of all apps under `/Applications` in the background
/// Keep in the `AppIconCache`. Run only once when FloatingMacro is launched.
/// The icon appears in the state where it is aligned when the app picker is opened.
///
/// Cascade:
/// ImageIO for reading .icns files directly (Foundation only, ms order)
/// 2. If it fails, try the fallback closure passed from the caller to NSWorkspace.
/// (Modern apps only with Assets.car — including UTM and more — are saved)
///
/// To avoid bringing AppKit dependencies into Core, the NSWorkspace fallback is implemented via a closure.
/// Injected design for `FloatingMacroApp`, using `NSWorkspaceIconFallback`.
/// Call by binding.
public struct AppIconPrewarmer {

    public init() {}

    /// Enumerate `/Applications`, extract icons only for apps that are not cached.
    /// - Parameters:
    /// provider: App enumeration source (default: Standard location)
    /// extractor: First attempt Foundation-only extractor
    /// nsWorkspaceFallback: First failure time AppKit fallback closure
    /// (url, size -> Data?)。nil if not fallback (test)
    /// size: The long side of the PNG to be cached in pixels. 128 is the default for UI and CHANGELOG.
    /// maxConcurrent: Parallel extraction count. Control conservatively to avoid overloading CPU.
    /// cache: cache entity (default: shared)
    public func prewarm(
        provider: AppListProvider = FileSystemAppListProvider(),
        extractor: ImageIOIconExtractor = ImageIOIconExtractor(),
        nsWorkspaceFallback: (@Sendable (URL, Int) -> Data?)? = nil,
        size: Int = 128,
        maxConcurrent: Int = 4,
        cache: AppIconCache = .shared
    ) async {
        guard let entries = try? provider.availableApplications() else { return }

        // Achieve parallelism control using semaphores with TaskGroup and a counter.
        // Write in a straightforward manner suitable for Swift 5.9 environment.
        await withTaskGroup(of: Void.self) { group in
            var inflight = 0
            var iterator = entries.makeIterator()

            // Initial investment
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

            // Insert next upon completion
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
        // Self-healing: Already cached, but thin in content (like Books' icns)
        // If ImageIO succeeded but the result was completely transparent, re-extract.
        // Typical apps exit early with a light touch due to IconContentValidator.
        if let existing = await cache.get(for: entry.url),
           IconContentValidator.hasMeaningfulContent(pngData: existing) {
            return
        }

        // 1st: ImageIO + Content Check → Fail Handle Next
        if let data = try? extractor.extractPNG(from: entry.url, size: size),
           IconContentValidator.hasMeaningfulContent(pngData: data) {
            await cache.put(for: entry.url, data: data)
            return
        }
        // 2nd: NSWorkspace fallback (closure method) - content inspection also applied similarly
        if let fb = nsWorkspaceFallback,
           let data = fb(entry.url, size),
           IconContentValidator.hasMeaningfulContent(pngData: data) {
            await cache.put(for: entry.url, data: data)
        }
    }
}
