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

            // Recursive scan. Subfolders like `/Applications/Utilities/`.
            // Use `enumerator` to include apps in the category/type of.
            // Skips package descendants, does not include within .app bundle
            // Do not mistakenly include nested .apps under helper or frameworks.
            // Skip hidden folders starting with a dot using `.skipsHiddenFiles`.
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in
                    // Ignore unreadable subfolders and continue (permissions/race condition)
                    // Returning what can be obtained is better for UX than stopping the entire enumeration.)。
                    return true
                }
            ) else { continue }

            // The scan results are not stable in the order of directories enumerated by the OS, so it is done at the root level.
            // Once collected, sort by file name in ascending order and deterministically determine the dedup-winner.
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
