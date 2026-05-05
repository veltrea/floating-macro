import Foundation

/// Saves an extracted PNG icon under the FloatingMacro Application
/// Support directory in a deterministic per-preset/per-button location.
///
/// Path layout (under `~/Library/Application Support` by default):
///   ```
///   FloatingMacro/presets/<presetName>/icons/<buttonId>.png
///   ```
///
/// `applicationSupportDirectory` can be overridden in tests so the
/// real user directory is never touched.
public enum IconAssetSaver {

    /// preset 配下の管理ディレクトリ種別。`copyImage` で保存先を指定するときに使う。
    public enum AssetSubdirectory: String {
        /// `presets/<name>/icons/` — ボタン / グループのアイコン
        case icons
        /// `presets/<name>/images/` — card 表示タイプのサムネイル
        case images
    }

    public enum SaveError: Error, Equatable {
        case extractFailed
        case writeFailed(path: String)
        case sourceNotReadable(path: String)
    }

    /// Extract `appURL`'s icon via ImageIO and write it under the preset's
    /// `icons/` directory. Returns the absolute path of the saved PNG.
    ///
    /// The extractor is injected so tests can substitute a deterministic
    /// implementation (e.g. one that returns fixed PNG bytes).
    public static func saveAppIcon(
        appURL: URL,
        buttonId: String,
        presetName: String,
        size: Int = 64,
        extractor: ImageIOIconExtractor = ImageIOIconExtractor(),
        applicationSupportDirectory: URL? = nil
    ) throws -> String {
        let pngData: Data
        do {
            pngData = try extractor.extractPNG(from: appURL, size: size)
        } catch {
            throw SaveError.extractFailed
        }
        return try saveData(
            pngData,
            buttonId: buttonId,
            presetName: presetName,
            applicationSupportDirectory: applicationSupportDirectory
        )
    }

    /// Lower-level: persist arbitrary PNG bytes to the per-preset
    /// `icons/<buttonId>.png` location and return the absolute path.
    public static func saveData(
        _ pngData: Data,
        buttonId: String,
        presetName: String,
        applicationSupportDirectory: URL? = nil
    ) throws -> String {
        let iconsDir = iconsDirectory(
            presetName: presetName,
            applicationSupportDirectory: applicationSupportDirectory
        )
        let dest = iconsDir.appendingPathComponent("\(buttonId).png")
        do {
            try FileManager.default.createDirectory(
                at: iconsDir, withIntermediateDirectories: true)
            try pngData.write(to: dest)
            return dest.path
        } catch {
            throw SaveError.writeFailed(path: dest.path)
        }
    }

    /// Resolve the directory where icons for `presetName` are stored.
    /// Public so tests can read it back; pure path computation, no I/O.
    public static func iconsDirectory(
        presetName: String,
        applicationSupportDirectory: URL? = nil
    ) -> URL {
        return presetSubdirectory(
            presetName: presetName,
            subdirectory: "icons",
            applicationSupportDirectory: applicationSupportDirectory
        )
    }

    /// Persist a card-tab thumbnail under `presets/<name>/images/<buttonId>.<ext>`.
    /// `ext` defaults to "png" but JPEG / WebP files can be passed unchanged so
    /// large photographic thumbnails do not get re-encoded into bloated PNGs.
    /// Returns the saved absolute path. Callers should set
    /// `ButtonDefinition.thumbnail` to the returned string.
    public static func saveThumbnail(
        _ data: Data,
        buttonId: String,
        presetName: String,
        ext: String = "png",
        applicationSupportDirectory: URL? = nil
    ) throws -> String {
        let imagesDir = imagesDirectory(
            presetName: presetName,
            applicationSupportDirectory: applicationSupportDirectory
        )
        let normalizedExt = ext.lowercased().trimmingCharacters(in: .whitespaces)
        let dest = imagesDir.appendingPathComponent("\(buttonId).\(normalizedExt)")
        do {
            try FileManager.default.createDirectory(
                at: imagesDir, withIntermediateDirectories: true)
            try data.write(to: dest)
            return dest.path
        } catch {
            throw SaveError.writeFailed(path: dest.path)
        }
    }

    /// Resolve the directory where card-tab thumbnails for `presetName` live.
    public static func imagesDirectory(
        presetName: String,
        applicationSupportDirectory: URL? = nil
    ) -> URL {
        return presetSubdirectory(
            presetName: presetName,
            subdirectory: "images",
            applicationSupportDirectory: applicationSupportDirectory
        )
    }

    /// ユーザーが Finder のファイルピッカーで選んだ画像ファイルを preset 配下の
    /// 管理ディレクトリにそのままコピーし、保存先の絶対パスを返す。
    ///
    /// 設計意図:
    /// 元ファイルの絶対パスを `ButtonDefinition.icon` / `.thumbnail` にそのまま
    /// 保存する旧挙動だと、ユーザーが元ファイルを移動・削除・改名した瞬間に
    /// ボタンのアイコンが消える。preset 配下に複製しておけば preset 単体での
    /// 移植性も保たれ、preset.json + icons/ + images/ をまとめてエクスポートして
    /// 別マシンで動かすこともできる。
    ///
    /// 拡張子は元ファイルから引き継ぐ (PNG は PNG のまま、JPEG は JPEG のまま)。
    /// 同一 `assetId` で過去にコピーしたファイル (別拡張子含む) は事前に削除して
    /// から新規コピーするので、orphan が増えない。
    ///
    /// - Note: SF Symbol (`sf:foo`) や bundle id (`com.apple.Safari`) はファイル
    ///   コピーの対象外。これらの参照は `IconLoader` 側で動的に解決されるので
    ///   path として保存する必要がない。本メソッドはローカルの実ファイルを選んだ
    ///   ケースだけを扱う。
    @discardableResult
    public static func copyImage(
        from sourceURL: URL,
        into subdirectory: AssetSubdirectory,
        assetId: String,
        presetName: String,
        applicationSupportDirectory: URL? = nil
    ) throws -> String {
        let dir = presetSubdirectory(
            presetName: presetName,
            subdirectory: subdirectory.rawValue,
            applicationSupportDirectory: applicationSupportDirectory
        )
        let rawExt = sourceURL.pathExtension.lowercased()
            .trimmingCharacters(in: .whitespaces)
        let ext = rawExt.isEmpty ? "png" : rawExt
        let dest = dir.appendingPathComponent("\(assetId).\(ext)")

        // 既に管理ディレクトリ内のファイルを再選択した場合は no-op。
        if sourceURL.standardizedFileURL == dest.standardizedFileURL {
            return dest.path
        }
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw SaveError.sourceNotReadable(path: sourceURL.path)
        }

        do {
            try FileManager.default.createDirectory(
                at: dir, withIntermediateDirectories: true)
            // 同じ assetId で過去にコピーしたファイル (拡張子違い含む) を一掃。
            // たとえば旧 PNG → 新 JPEG に差し替えるとき、PNG が orphan として
            // 残らないようにする。
            if let existing = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil
            ) {
                for url in existing
                where url.deletingPathExtension().lastPathComponent == assetId {
                    try? FileManager.default.removeItem(at: url)
                }
            }
            try FileManager.default.copyItem(at: sourceURL, to: dest)
            return dest.path
        } catch {
            throw SaveError.writeFailed(path: dest.path)
        }
    }

    /// 既存ボタン / グループに格納された外部の絶対画像パスを preset 配下に
    /// コピーし、新しい絶対パスを返す。一括移行 / commit 時の自動修復で使う。
    ///
    /// 何もしないケース (元の `path` をそのまま返す):
    /// - `nil` / 空文字列
    /// - `sf:foo` / `lucide:foo` / bundle id (`com.apple.Safari`) のような参照系
    /// - `.app` バンドル
    /// - 元ファイルがディスク上に存在しない (リンク切れ)
    /// - 既に管理ディレクトリ内 (`presets/<name>/icons|images/`) に置かれている
    /// - コピーが何らかの理由で失敗した
    ///
    /// 移行が成功したときだけ新しいパスが返る。fail-safe な実装で、ユーザーの
    /// 設定を勝手に壊さないことを優先している。
    public static func migrateExternalImagePath(
        _ path: String?,
        into subdirectory: AssetSubdirectory,
        assetId: String,
        presetName: String,
        applicationSupportDirectory: URL? = nil
    ) -> String? {
        guard let path = path,
              !path.trimmingCharacters(in: .whitespaces).isEmpty
        else { return path }

        // IconResolver で実ファイル参照かどうかを分類する。SF Symbol や
        // bundle id は素通り。.app バンドルは画像ファイルではないので素通り。
        let resolved = IconResolver.resolve(path)
        let sourceURL: URL
        switch resolved {
        case .success(.imageFile(let u)):
            sourceURL = u
        default:
            return path
        }

        // 既に管理ディレクトリ配下のファイルなら何もしない (二重コピー回避)。
        let managedDir = presetSubdirectory(
            presetName: presetName,
            subdirectory: subdirectory.rawValue,
            applicationSupportDirectory: applicationSupportDirectory
        ).standardizedFileURL
        let standardSource = sourceURL.standardizedFileURL
        if standardSource.path.hasPrefix(managedDir.path + "/") {
            return path
        }

        do {
            return try copyImage(
                from: sourceURL,
                into: subdirectory,
                assetId: assetId,
                presetName: presetName,
                applicationSupportDirectory: applicationSupportDirectory
            )
        } catch {
            return path
        }
    }

    private static func presetSubdirectory(
        presetName: String,
        subdirectory: String,
        applicationSupportDirectory: URL?
    ) -> URL {
        let supportDir: URL
        if let d = applicationSupportDirectory {
            supportDir = d
        } else {
            supportDir = (try? FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )) ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support")
        }
        return supportDir
            .appendingPathComponent("FloatingMacro")
            .appendingPathComponent("presets")
            .appendingPathComponent(presetName)
            .appendingPathComponent(subdirectory)
    }
}
