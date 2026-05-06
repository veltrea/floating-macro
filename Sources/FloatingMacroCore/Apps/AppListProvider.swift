import Foundation

/// Source of installed `AppEntry` values for the picker UI.
public protocol AppListProvider {
    func availableApplications() throws -> [AppEntry]
}

/// Default provider that walks one or more filesystem roots
/// (e.g. `/Applications`, `/System/Applications`, `~/Applications`)
/// and returns the `.app` bundles found inside.
///
/// - Bundles with the same `CFBundleIdentifier` are deduplicated;
///   the first occurrence wins (search root order matters).
/// - Bundles without a bundle identifier are kept (they may still
///   be useful as launch targets).
/// - Symlinks are resolved for de-dup but the original URL is
///   preserved in the returned `AppEntry` so paths shown to the
///   user match what they see in Finder.
/// - Sorting is by `displayName`, case-insensitive.
public struct FileSystemAppListProvider: AppListProvider {

    public let searchRoots: [URL]

    public init(searchRoots: [URL]? = nil) {
        self.searchRoots = searchRoots ?? Self.defaultSearchRoots
    }

    /// Default macOS application search locations.
    public static var defaultSearchRoots: [URL] {
        var roots: [URL] = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
        ]
        let userAppsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications")
        roots.append(userAppsDir)
        return roots
    }

    public func availableApplications() throws -> [AppEntry] {
        var results: [AppEntry] = []
        var seenBundleIds = Set<String>()
        var seenResolvedPaths = Set<String>()

        for root in searchRoots {
            guard FileManager.default.fileExists(atPath: root.path) else { continue }

            // 再帰スキャン。`/Applications/Utilities/` のようなサブフォルダ
            // 内のアプリも拾うために `enumerator` を使う。
            // `.skipsPackageDescendants` で `.app` バンドルの中には入らない
            // (helper や Frameworks 配下の入れ子 .app を誤って候補に入れない)。
            // `.skipsHiddenFiles` でドット始まりの隠しフォルダを除外。
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in
                    // 読めないサブフォルダは無視して続行 (権限・race condition
                    // で全体の列挙が止まるより、取れるものを返す方が UX よい)。
                    return true
                }
            ) else { continue }

            // 走査結果は OS のディレクトリ列挙順で安定しないため、root 単位で
            // 一旦集めてからファイル名昇順に並べ、dedup-winner を確定的にする。
            var appURLs: [URL] = []
            while let url = enumerator.nextObject() as? URL {
                guard url.pathExtension.lowercased() == "app" else { continue }
                appURLs.append(url)
            }
            appURLs.sort {
                $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending
            }

            for url in appURLs {
                let resolvedPath = url.resolvingSymlinksInPath().path
                if seenResolvedPaths.contains(resolvedPath) { continue }
                seenResolvedPaths.insert(resolvedPath)

                guard let entry = AppEntryResolver.resolve(at: url) else { continue }

                if let bid = entry.bundleIdentifier {
                    if seenBundleIds.contains(bid) { continue }
                    seenBundleIds.insert(bid)
                }

                results.append(entry)
            }
        }

        results.sort {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
        return results
    }
}
