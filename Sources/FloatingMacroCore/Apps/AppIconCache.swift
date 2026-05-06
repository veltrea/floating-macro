import Foundation

/// 二段キャッシュ (memory + disk) でアプリアイコン PNG を保持する。
///
/// Background:
///   どんな OS の Explorer / Finder / Dock もアイコンの取得をキャッシュしている。
///   FloatingMacro でも、`/Applications` のスキャン結果や Assets.car を毎回
///   NSWorkspace に問い合わせると遅いし重いので、抽出済み PNG を保存して
///   再利用する。
///
/// Layout:
///   - メモリ: actor 内の Dictionary。プロセス生存中だけ有効
///   - ディスク: `~/Library/Caches/FloatingMacro/AppIcons/<key>.png`
///     ファイルの mtime をアプリの mtime と一致させて保存し、アプリが
///     更新された (mtime が変わった) ときだけ再抽出するようにする。
///
/// Key:
///   bundle id があればそれ。無ければアプリパスから / を _ に置換した文字列。
///   sha256 hash 等は使わずプレーンに保つ (デバッグしやすさ優先)。
///
/// Concurrency:
///   actor で thread-safe。複数の `loadPreviewIcon` が同時に走っても
///   put/get が安全に直列化される。
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

    /// `appURL` のキャッシュ済みアイコンを返す。
    /// アプリの mtime とキャッシュの mtime を比較し、アプリが更新されていれば
    /// nil を返す (上位で再抽出させる)。
    public func get(for appURL: URL) -> Data? {
        let key = cacheKey(for: appURL)
        guard let appMtime = appMtime(at: appURL) else { return nil }

        if let entry = memory[key], Self.mtimeStillValid(cached: entry.appMtime, app: appMtime) {
            return entry.pngData
        }

        // ディスクからメモリへ昇格
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

    /// 抽出済みの PNG bytes をキャッシュに格納する (memory + disk)。
    /// ディスクファイルの mtime をアプリの mtime に合わせて、後から
    /// アプリ側が更新された場合に再抽出が走るようにする。
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
            // ディスク書き込み失敗はメモリキャッシュだけで許容する
        }
    }

    /// 既にキャッシュ済みかを軽量に判定する (バックグラウンドプリキャッシング用)。
    /// 返り値が true でも次の `get` で nil 返ることがある (mtime invalidation 等) が、
    /// 「再抽出をスキップしてよいか」を高速に判定するのには十分。
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

    /// `setAttributes(.modificationDate:)` で書いた mtime を `attributesOfItem`
    /// で読み戻すと、APFS の sub-second 精度切り捨てや時計のジッタで
    /// nanosecond オーダーの誤差が出る (cached が app よりわずかに小さく
    /// なる)。素朴に `cached >= app` で比較するとこの誤差で「アプリが
    /// 更新された」と誤判定し、キャッシュを無効化してしまうので、
    /// `mtimeTolerance` 秒以内の差は「同じ世代」と扱う。
    ///
    /// 1.0 秒は HFS+/APFS の典型的な mtime 解像度を超える保守的な値。
    /// アプリの本当の更新は秒単位以上で発生するので問題にならない。
    private static let mtimeTolerance: TimeInterval = 1.0

    private static func mtimeStillValid(cached: Date, app: Date) -> Bool {
        return cached >= app || abs(cached.timeIntervalSince(app)) < mtimeTolerance
    }

    /// すべてのメモリ + ディスクキャッシュを削除する (テスト・デバッグ用)。
    public func clear() {
        memory.removeAll()
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(
            at: cacheDirectory, withIntermediateDirectories: true)
    }

    /// キャッシュエントリ数 (テスト用)。
    public func memoryCount() -> Int { memory.count }

    // MARK: - Private

    private func cacheKey(for appURL: URL) -> String {
        if let entry = AppEntryResolver.resolve(at: appURL),
           let bid = entry.bundleIdentifier, !bid.isEmpty {
            return bid
        }
        // bundle id 無しのアプリ向けフォールバック: パスから安全な文字列
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
