import Foundation

/// Pure-logic classifier that turns a dragged-in URL (from a Finder drop
/// or an "Add from app…" picker selection) into a `Candidate` that the
/// App layer can hand to `PresetManager.addButton`.
///
/// Lives in Core (Foundation only) so its decisions are unit-testable
/// without launching the App. The App layer is reduced to
/// "receive `[URL]` from `.onDrop`, classify, confirm via NSAlert,
/// persist via PresetManager."
public enum AppDropClassifier {

    public enum DropKind: String, Equatable {
        case app
        case file
        case folder
    }

    public struct Candidate: Equatable {
        public let kind: DropKind
        /// Bundle identifier for `.app` (when resolvable), absolute path
        /// for files / folders / unresolvable apps.
        public let target: String
        public let label: String
        public let tooltip: String
        /// Filesystem path to use as the source for icon extraction.
        /// Always an absolute path; for `.app` this points at the bundle
        /// itself, for files/folders it's the same as `target`.
        public let iconSourcePath: String

        public init(kind: DropKind, target: String, label: String,
                    tooltip: String, iconSourcePath: String) {
            self.kind = kind
            self.target = target
            self.label = label
            self.tooltip = tooltip
            self.iconSourcePath = iconSourcePath
        }
    }

    /// Classify a single URL. Returns `nil` for paths that don't exist.
    public static func classify(_ url: URL) -> Candidate? {
        let path = url.path

        // .app バンドル — AppEntryResolver で displayName / bundleId を解決
        if url.pathExtension.lowercased() == "app" {
            if let entry = AppEntryResolver.resolve(at: url) {
                let target = entry.bundleIdentifier ?? path
                let tooltip: String
                if let bid = entry.bundleIdentifier {
                    tooltip = "\(entry.displayName) (\(bid))"
                } else {
                    tooltip = path
                }
                return Candidate(
                    kind: .app,
                    target: target,
                    label: entry.displayName,
                    tooltip: tooltip,
                    iconSourcePath: path
                )
            }
            // .app だが resolve 失敗（存在しない、Info.plist 不正等）→ 下のファイル扱いへ
        }

        // 通常のファイル / フォルダ
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        guard exists else { return nil }

        return Candidate(
            kind: isDir.boolValue ? .folder : .file,
            target: path,
            label: url.lastPathComponent,
            tooltip: path,
            iconSourcePath: path
        )
    }
}
