import AppKit
import Foundation
import CryptoKit
import ImageIO
import UniformTypeIdentifiers
import FloatingMacroCore
// libwebp (BSD-3-clause)。macOS の ImageIO は WebP encode 非対応なので、
// SwiftPM 経由で公式 C ライブラリを直接呼ぶ。
import libwebp

/// Phase 5: Web Panel から要求されるアイコン / サムネイル画像を **必要なサイズに
/// リサイズしてから PNG エンコードして** 返すレンダラ。in-memory キャッシュ
/// 付き。
///
/// なぜ必要か:
/// - ボタンの thumbnail に 1456×816 の生 PNG (2.4MB) が指定されているケースがあり、
///   そのまま LAN 配信するとスマホで読み込みが体感できるほど遅い。
/// - `IconLoader.image(for:)` は NSImage 単位ではキャッシュしているが、
///   `pngData(_:)` が呼ばれるたびに毎回 NSBitmapImageRep を経由して PNG
///   再エンコードしていた。
///
/// 設計:
/// - キャッシュキー = `(ref, maxSize)` の組。同じ icon を 128px と 512px に
///   別々のキャッシュエントリで持つ。
/// - エンコードは PNG 固定 (透過保持のため)。JPEG は alpha が落ちるので採用せず。
/// - LRU っぽい単純な上限管理 (256 エントリ超で古いものから捨てる)。
/// - ETag は SHA-256 の先頭 16 hex で生成して HTTP の If-None-Match 経路に
///   使う。
final class WebPanelIconRenderer: @unchecked Sendable {

    static let shared = WebPanelIconRenderer()

    struct Entry {
        let data: Data
        let etag: String
        let contentType: String
    }

    /// 出力フォーマット。
    /// - png  : alpha 保持。アイコン用 (lossless WebP 不可環境用)。
    /// - jpeg : alpha 落ちるが体積 1/5〜1/10。サムネイル (写真ライク) 用。
    /// - webp : iOS 14+ Safari 対応。同品質 JPEG より 25〜35% 小さい。
    ///          alpha 保持できるのでアイコンの白背景問題も無い。
    enum Format: String {
        case png
        case jpeg
        case webp

        var contentType: String {
            switch self {
            case .png:  return "image/png"
            case .jpeg: return "image/jpeg"
            case .webp: return "image/webp"
            }
        }
    }

    private let lock = NSLock()
    /// `(maxSize, format, ref)` をキーとしたエンコード済みバイト列キャッシュ。
    private var cache: [String: Entry] = [:]
    /// 簡易 LRU 用の挿入順 (古い → 新しい)。capacity 超過時に先頭を捨てる。
    private var insertionOrder: [String] = []
    private let capacity = 512

    /// `ref` を `maxSize` 以下にリサイズして指定 format にエンコードし、Entry を返す。
    /// ref が解決できないときは nil。
    func render(ref: String, maxSize: Int, format: Format = .png) -> Entry? {
        let key = cacheKey(ref: ref, maxSize: maxSize, format: format)

        lock.lock()
        if let hit = cache[key] {
            lock.unlock()
            return hit
        }
        lock.unlock()

        guard let image = IconLoader.image(for: ref) else { return nil }
        guard let bytes = encodeResized(image: image,
                                        maxSize: CGFloat(maxSize),
                                        format: format) else { return nil }
        let etag = etagFor(bytes)
        let entry = Entry(data: bytes, etag: etag, contentType: format.contentType)

        lock.lock()
        cache[key] = entry
        insertionOrder.append(key)
        if insertionOrder.count > capacity {
            let drop = insertionOrder.removeFirst()
            cache.removeValue(forKey: drop)
        }
        lock.unlock()
        return entry
    }

    /// 単一プリセットだけ先回りエンコードする。HTML 配信のタイミングで
    /// 「これから iPhone がこの preset を見にくる」と分かったときに呼ぶ。
    /// PresetManager 全体スキャンより早く終わるし、無駄な encode をしない。
    func prewarm(preset: Preset) {
        var iconRefs: Set<String> = []
        var thumbRefs: Set<String> = []
        for group in preset.groups {
            for btn in group.buttons {
                if let i = btn.icon, !i.isEmpty { iconRefs.insert(i) }
                if let t = btn.thumbnail, !t.isEmpty { thumbRefs.insert(t) }
                // launch アクションの target も画像参照源になる。
                if case .launch(let target) = btn.action, !target.isEmpty {
                    iconRefs.insert(target)
                }
            }
        }
        prewarmRefs(iconRefs: iconRefs, thumbRefs: thumbRefs)
    }

    /// 全プリセットの全ボタンの icon / thumbnail を先回りエンコードして
    /// キャッシュに乗せる。LAN 公開モードを ON にした直後に呼ぶことで、
    /// 最初の iPhone 接続時の同時並列リクエストを軽くする。
    ///
    /// **パフォーマンス上の配慮:**
    /// - 1 つのサムネイル (1456×816) を 384px JPEG に変換するのは数百ミリ秒の
    ///   CPU を食う。10 個並んでいたらそれだけで数秒の高負荷期間ができる。
    /// - したがって:
    ///   - QoS は `.background` (最低) に固定
    ///   - 1 件処理するごとに **30ms スリープ** で他プロセスに譲歩
    ///   - サイズバケットは「クライアントが最も要求しそうな 1 種類」だけに
    ///     絞る (icon=64 / thumb=384、DPR=2 の iPhone を想定)
    ///   - 残りバケットは初回リクエスト時にオンデマンドで生成 (cache miss は
    ///     1 度だけで、以降は HTTP の Cache-Control + ETag が効く)
    func prewarm(presetManager: PresetManager) {
        let appConfig = presetManager.appConfig
        let presetNames = Set((appConfig?.panels ?? []).map { $0.presetName })
        var iconRefs: Set<String> = []
        var thumbRefs: Set<String> = []
        for name in presetNames {
            guard let preset = presetManager.preset(named: name) else { continue }
            for group in preset.groups {
                for btn in group.buttons {
                    if let icon = btn.icon, !icon.isEmpty { iconRefs.insert(icon) }
                    if let th = btn.thumbnail, !th.isEmpty { thumbRefs.insert(th) }
                }
            }
        }
        let iconSnap = iconRefs
        let thumbSnap = thumbRefs
        prewarmRefs(iconRefs: iconSnap, thumbRefs: thumbSnap)
    }

    /// 与えられた ref 集合をバックグラウンドで並列 encode。同じ ref を重複
    /// 起動しないため `inFlight` セットで de-dup する (HTML 配信ごとに preset
    /// prewarm が呼ばれるが、2 度目は何もしない)。
    private func prewarmRefs(iconRefs: Set<String>, thumbRefs: Set<String>) {
        // どちらの ref が今 in-flight かを lock 下で記録 + skip。
        lock.lock()
        let icons  = iconRefs.subtracting(prewarmInFlight)
        let thumbs = thumbRefs.subtracting(prewarmInFlight)
        prewarmInFlight.formUnion(icons)
        prewarmInFlight.formUnion(thumbs)
        lock.unlock()

        guard !icons.isEmpty || !thumbs.isEmpty else { return }

        // TaskGroup で並列 encode。M4 の 8〜10 コアを活かして数百 ms で完了。
        // 重い処理だが LAN 公開時の数秒間限定なので main を圧迫しない範囲で全力。
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            await withTaskGroup(of: Void.self) { group in
                for ref in icons {
                    group.addTask { _ = self.render(ref: ref, maxSize: 64, format: .webp) }
                }
                for ref in thumbs {
                    group.addTask { _ = self.render(ref: ref, maxSize: 384, format: .webp) }
                }
            }
            self.lock.lock()
            self.prewarmInFlight.subtract(icons)
            self.prewarmInFlight.subtract(thumbs)
            self.lock.unlock()
            LoggerContext.shared.info("WebPanelIconRenderer", "prewarm complete", [
                "icons":  String(icons.count),
                "thumbs": String(thumbs.count),
            ])
        }
    }

    /// 同じ ref を二重に prewarm しないためのセット。`prewarm` を複数経路
    /// (LAN ON / HTML 配信 / トグル切替) から呼んでも実質 1 回に集約される。
    private var prewarmInFlight: Set<String> = []

    /// プリセット編集後など、キャッシュを破棄する必要があるときに呼ぶ。
    func invalidate() {
        lock.lock()
        cache.removeAll()
        insertionOrder.removeAll()
        lock.unlock()
    }

    // MARK: - Internal

    private func cacheKey(ref: String, maxSize: Int, format: Format) -> String {
        return "\(format.rawValue):\(maxSize):\(ref)"
    }

    /// NSImage を maxSize 以下にリサイズして format でエンコードする。
    ///
    /// NSImage.lockFocus + draw ベースの実装は Retina ディスプレイで backing
    /// scale (=2x) を内部的に適用してしまい、要求サイズの 2 倍ピクセルが
    /// 出ていた。CGImage / CGContext を直接使って「ピクセル単位で正確に
    /// 意図したサイズ」にする。
    private func encodeResized(image: NSImage,
                               maxSize: CGFloat,
                               format: Format) -> Data? {
        var rect = NSRect(origin: .zero,
                          size: image.size != .zero ? image.size : NSSize(width: 1, height: 1))
        guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
            return nil
        }
        let srcW = cg.width, srcH = cg.height
        guard srcW > 0 && srcH > 0 else { return nil }

        let mx = CGFloat(max(srcW, srcH))
        let scale = min(maxSize / mx, 1.0)
        let outW = Int((CGFloat(srcW) * scale).rounded())
        let outH = Int((CGFloat(srcH) * scale).rounded())
        guard outW > 0 && outH > 0 else { return nil }

        let cs = CGColorSpaceCreateDeviceRGB()
        // JPEG は alpha チャンネルを持てないので noneSkipLast (XRGB) で描画。
        // PNG / WebP は premultipliedLast (RGBA) で描画する。
        let bitmapInfo: UInt32
        switch format {
        case .png, .webp:
            bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
                       | CGBitmapInfo.byteOrder32Big.rawValue
        case .jpeg:
            bitmapInfo = CGImageAlphaInfo.noneSkipLast.rawValue
                       | CGBitmapInfo.byteOrder32Big.rawValue
        }
        guard let ctx = CGContext(data: nil,
                                  width: outW, height: outH,
                                  bitsPerComponent: 8,
                                  bytesPerRow: 0,
                                  space: cs,
                                  bitmapInfo: bitmapInfo) else {
            return nil
        }
        if format == .jpeg {
            // 透過ピクセルが透明から黒く抜けないよう、白で塗ってから描画。
            ctx.setFillColor(CGColor(gray: 1.0, alpha: 1.0))
            ctx.fill(CGRect(x: 0, y: 0, width: outW, height: outH))
        }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: outW, height: outH))
        guard let resized = ctx.makeImage() else { return nil }

        switch format {
        case .png:
            let rep = NSBitmapImageRep(cgImage: resized)
            return rep.representation(using: .png, properties: [:])
        case .jpeg:
            let rep = NSBitmapImageRep(cgImage: resized)
            // 0.78: 写真ライクなサムネイル品質と体積のバランスとしては定石。
            return rep.representation(using: .jpeg,
                                      properties: [.compressionFactor: 0.78])
        case .webp:
            return encodeWebP(resized)
        }
    }

    /// CGImage → WebP bytes via libwebp (`WebPEncodeRGBA`)。
    /// 経緯: macOS 15.5 時点で ImageIO は WebP **decode のみ**で encode 未対応
    /// (`CGImageDestinationCopyTypeIdentifiers()` に WebP UTI が含まれない) なので
    /// libwebp を SwiftPM 経由で直接リンクする (`SDWebImage/libwebp-Xcode`)。
    private func encodeWebP(_ image: CGImage, lossless: Bool = false) -> Data? {
        let w = image.width, h = image.height
        guard w > 0 && h > 0 else { return nil }

        // CGImage を RGBA バイト列に展開する。CGContext で premultipliedLast
        // (= RGBA, alpha 末尾) として描画。WebPEncodeRGBA も同レイアウトを期待。
        let bpr = w * 4
        var rgba = [UInt8](repeating: 0, count: bpr * h)
        let cs = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo: UInt32 = CGImageAlphaInfo.premultipliedLast.rawValue
                               | CGBitmapInfo.byteOrder32Big.rawValue
        guard let ctx = rgba.withUnsafeMutableBytes({ buf -> CGContext? in
            CGContext(data: buf.baseAddress,
                      width: w, height: h,
                      bitsPerComponent: 8,
                      bytesPerRow: bpr,
                      space: cs,
                      bitmapInfo: bitmapInfo)
        }) else {
            return nil
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        // libwebp が malloc した出力バッファ。WebPFree で解放。
        var out: UnsafeMutablePointer<UInt8>? = nil
        let size: Int = rgba.withUnsafeBufferPointer { buf in
            let base = buf.baseAddress!
            if lossless {
                return WebPEncodeLosslessRGBA(base, Int32(w), Int32(h),
                                              Int32(bpr), &out)
            } else {
                return WebPEncodeRGBA(base, Int32(w), Int32(h),
                                      Int32(bpr), 78.0 /* quality 0–100 */, &out)
            }
        }
        guard size > 0, let out = out else { return nil }
        defer { WebPFree(out) }
        return Data(bytes: out, count: size)
    }

    private func etagFor(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "\"" + String(hex.prefix(16)) + "\""
    }
}
