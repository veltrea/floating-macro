import SwiftUI
import AppKit
import UniformTypeIdentifiers
import FloatingMacroCore

/// 編集ウィンドウで「アイコン」「サムネイル」を登録するためのビジュアルな
/// ドロップ枠。テキスト欄を排してドラッグ&ドロップ + クリックで参照を主導線にする。
///
/// - 中身がある (画像 / 絵文字) ときはそれをプレビューする
/// - 空のときはガイダンステキストと点線枠を出す
/// - ドラッグオーバー中はアクセントカラーの太枠でフィードバック
/// - クリックで `onClickFallback` を起動 (キーボード派・ドロップを使えない人向け)
struct ImageDropZone<Content: View>: View {
    /// 表示倍率を決めるサイズ。アイコン用 = 96 正方、サムネイル用 = 160×120 等。
    let width: CGFloat
    let height: CGFloat
    /// 中身が空かどうか。プレースホルダ表示の判定に使う。
    let isEmpty: Bool
    /// プレースホルダ用のキャプション (例: 「画像をドロップ」)。
    let placeholderCaption: String
    /// プレースホルダ用の SF Symbol 名 (例: "photo.on.rectangle.angled")。
    let placeholderSystemImage: String
    /// 中身。`isEmpty == false` のときに描画される。
    @ViewBuilder let content: () -> Content
    /// 画像ファイル URL がドロップされたら呼ばれる (DnD のメイン経路)。
    let onDropImageURL: (URL) -> Void
    /// 枠をクリックしたときのフォールバック (NSOpenPanel 起動など)。
    let onClickFallback: () -> Void

    @State private var isDropTargeted: Bool = false

    var body: some View {
        ZStack {
            backgroundShape
            if isEmpty {
                placeholder
            } else {
                content()
                    .padding(6)
            }
        }
        .frame(width: width, height: height)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture { onClickFallback() }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
        }
        .help("画像をドロップして登録 / クリックでファイル選択")
    }

    private var backgroundShape: some View {
        RoundedRectangle(cornerRadius: 8)
            .stroke(
                isDropTargeted ? Color.accentColor : Color.gray.opacity(0.4),
                style: StrokeStyle(
                    lineWidth: isDropTargeted ? 2.5 : 1.5,
                    dash: isEmpty ? [5, 3] : []
                )
            )
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        isDropTargeted
                            ? Color.accentColor.opacity(0.12)
                            : Color.secondary.opacity(0.05)
                    )
            )
    }

    private var placeholder: some View {
        VStack(spacing: 4) {
            Image(systemName: placeholderSystemImage)
                .font(.system(size: 22))
            Text(placeholderCaption)
                .font(.caption)
                .multilineTextAlignment(.center)
        }
        .foregroundColor(.secondary)
        .padding(8)
    }

    /// `NSItemProvider` の配列から最初の画像ファイル URL を取り出して
    /// `onDropImageURL` に渡す。受理できれば true を返して SwiftUI に
    /// 「成功した」と知らせる (緑チェック → 通常カーソルへ)。
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier,
                          options: nil) { item, _ in
            let url: URL?
            if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else if let u = item as? URL {
                url = u
            } else {
                url = nil
            }
            guard let resolvedURL = url else { return }
            DispatchQueue.main.async {
                onDropImageURL(resolvedURL)
            }
        }
        return true
    }
}

/// アイコン用ドロップゾーン (96pt 正方)。画像があれば画像を、無ければ絵文字を、
/// それも無ければプレースホルダを出す。
struct IconDropZoneView: View {
    /// 現在のアイコン参照 (file path / sf:foo / bundle id 等)。
    let iconRef: String
    /// 画像参照が無いときのフォールバック絵文字。
    let iconText: String
    let onDropImageURL: (URL) -> Void
    let onClickFallback: () -> Void

    private var resolvedImage: NSImage? {
        IconLoader.image(for: iconRef.isEmpty ? nil : iconRef)
    }

    private var isEmpty: Bool {
        resolvedImage == nil && iconText.isEmpty
    }

    var body: some View {
        ImageDropZone(
            width: 96,
            height: 96,
            isEmpty: isEmpty,
            placeholderCaption: "画像をドロップ\nまたはクリック",
            placeholderSystemImage: "photo.on.rectangle.angled",
            content: {
                if let img = resolvedImage {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else if !iconText.isEmpty {
                    Text(iconText)
                        .font(.system(size: 36))
                }
            },
            onDropImageURL: onDropImageURL,
            onClickFallback: onClickFallback
        )
    }
}

/// サムネイル用ドロップゾーン (160×120)。画像があれば画像を、無ければ
/// プレースホルダを出す。card 表示タイプ用なので絵文字フォールバックは出さない。
struct ThumbnailDropZoneView: View {
    let thumbnailPath: String
    let onDropImageURL: (URL) -> Void
    let onClickFallback: () -> Void

    private var resolvedImage: NSImage? {
        IconLoader.image(for: thumbnailPath.isEmpty ? nil : thumbnailPath)
    }

    var body: some View {
        ImageDropZone(
            width: 160,
            height: 120,
            isEmpty: resolvedImage == nil,
            placeholderCaption: "サムネイル画像をドロップ\nまたはクリック",
            placeholderSystemImage: "photo.fill.on.rectangle.fill",
            content: {
                if let img = resolvedImage {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
            },
            onDropImageURL: onDropImageURL,
            onClickFallback: onClickFallback
        )
    }
}
