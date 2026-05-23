import Foundation

/// Maintain the app icon PNG in a two-tier cache of memory and disk.
///
/// Background:
/// All OS Explorers/Finder/Dock cache icon retrieval.
/// FloatingMacro, also scan results from /Applications and Assets.car every time
/// Saving extracted PNGs to speed up queries and reduce load on NSWorkspace.
/// Reuse.
///
/// Layout:
/// Memory: Dictionary within the actor. Valid only during process lifetime
/// Disk: `~/Library/Caches/FloatingMacro/AppIcons/<key>.png`
/// Save the file's mtime to match the app's mtime and have the app
/// Update only when mtime changes.
///
/// Key:
/// If there is a bundle ID, use that. Otherwise, replace "/" in the app path with "_" to form the string.
/// Do not use sha256 hash, keep plain. (Prioritize debuggability).
///
/// Concurrency:
/// thread-safe with actor. Multiple `loadPreviewIcon` can run simultaneously without
/// put/get are serialized safely in sequence.
public actor AppIconCache {

    public static let shared = AppIconCache()

    private struct CachedIcon {
        let pngData: Data
        let appMtime: Date
    }

    private var memory: [String: CachedIcon] = [:]
    private let cacheDirectory: URL

    public init(cacheDirectory: URL? = nil) {
        if let dir = cacheDirectory {
            self.cacheDirectory = dir
        } else {
            let cachesURL = (try? FileManager.default.url(
                for: .cachesDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true)) ?? URL(fileURLWithPath: NSHomeDirectory())
                    .appendingPathComponent("Library/Caches")
            self.cacheDirectory = cachesURL
                .appendingPathComponent("FloatingMacro")
                .appendingPathComponent("AppIcons")
        }
        try? FileManager.default.createDirectory(
            at: self.cacheDirectory, withIntermediateDirectories: true)
    }

    /// Returns the cached icon for `appURL`.
    /// Compare the app's mtime and cache mtime, and if the app has been updated,
    /// Return nil (re-fetch at the upper level).
    public func get(for appURL: URL) -> Data? {
        let key = cacheKey(for: appURL)
        guard let appMtime = appMtime(at: appURL) else { return nil }

        if let entry = memory[key], Self.mtimeStillValid(cached: entry.appMtime, app: appMtime) {
            return entry.pngData
        }

        // Upgrade from disk to memory
        let diskFile = self.diskFile(for: key)
        if let attrs = try? FileManager.default.attributesOfItem(atPath: diskFile.path),
           let diskMtime = attrs[.modificationDate] as? Date,
           Self.mtimeStillValid(cached: diskMtime, app: appMtime),
           let data = try? Data(contentsOf: diskFile) {
            memory[key] = CachedIcon(pngData: data, appMtime: appMtime)
            return data
        }
        return nil
    }

    /// Store cached PNG bytes in memory and disk.
    /// Set the disk file's mtime to match the app's mtime later.
    /// Run re-extraction when the app side is updated.
    public func put(for appURL: URL, data: Data) {
        let key = cacheKey(for: appURL)
        guard let appMtime = appMtime(at: appURL) else { return }
        memory[key] = CachedIcon(pngData: data, appMtime: appMtime)

        let diskFile = self.diskFile(for: key)
        do {
            try data.write(to: diskFile)
            try FileManager.default.setAttributes(
                [.modificationDate: appMtime],
                ofItemAtPath: diskFile.path)
        } catch {
            // Disk write failure is acceptable only in memory cache.
        }
    }

    /// Determine if already cached lightly (for background caching).
    /// Return value is true, but the next `get` may return nil (due to mtime invalidation, etc.).
    /// Sufficient to quickly determine whether it is sufficient to skip the re-extraction.
    public func contains(_ appURL: URL) -> Bool {
        let key = cacheKey(for: appURL)
        guard let appMtime = appMtime(at: appURL) else { return false }
        if let entry = memory[key], Self.mtimeStillValid(cached: entry.appMtime, app: appMtime) {
            return true
        }
        let diskFile = self.diskFile(for: key)
        if let attrs = try? FileManager.default.attributesOfItem(atPath: diskFile.path),
           let diskMtime = attrs[.modificationDate] as? Date,
           Self.mtimeStillValid(cached: diskMtime, app: appMtime) {
            return true
        }
        return false
    }

    /// Set the modification date using `.modificationDate:` and retrieve it with `attributesOfItem`.
    /// Reverting to read, APFS's sub-second truncation and clock jitter.
    /// nanosecond order error occurs (cached is slightly smaller than app)
    /// The comment appears to be incomplete and contains a mix of Japanese text with English code identifiers. Here is the translation focusing on the provided portion:

"Comparing `cached >= app` reveals this error, making it seem like 'the app'."
    /// Updated and mistakenly judged as invalid, so the cache is disabled.
    /// Within seconds of `mtimeTolerance`, treat as the same generation.
    ///
    /// 1.0 seconds is a conservative value exceeding the typical mtime resolution of HFS+ and APFS.
    /// The actual updates of the app occur at intervals longer than seconds, so it will not be a problem.
    private static let mtimeTolerance: TimeInterval = 1.0

    private static func mtimeStillValid(cached: Date, app: Date) -> Bool {
        return cached >= app || abs(cached.timeIntervalSince(app)) < mtimeTolerance
    }

    /// Remove all memory and disk cache (for testing/debugging).
    public func clear() {
        memory.removeAll()
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(
            at: cacheDirectory, withIntermediateDirectories: true)
    }

    /// Number of cache entries (for testing).
    public func memoryCount() -> Int { memory.count }

    // MARK: - Private

    private func cacheKey(for appURL: URL) -> String {
        if let entry = AppEntryResolver.resolve(at: appURL),
           let bid = entry.bundleIdentifier, !bid.isEmpty {
            return bid
        }
        // Fallback for apps without bundle ID: Safe string from path
        return appURL.path
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }

    private func diskFile(for key: String) -> URL {
        cacheDirectory.appendingPathComponent("\(key).png")
    }

    private func appMtime(at appURL: URL) -> Date? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: appURL.path) else {
            return nil
        }
        return attrs[.modificationDate] as? Date
    }
}
