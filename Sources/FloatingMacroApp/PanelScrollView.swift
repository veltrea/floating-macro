import SwiftUI
import AppKit

/// `NSScrollView` を `NSViewRepresentable` でラップしたスクロールビュー。
/// SwiftUI の標準 `ScrollView` だと macOS 13 では現在のスクロール位置を読み書き
/// する公式 API が無く、アプリ再起動後に位置を復元することができない。
/// このラッパーを使うと:
///   - 初期 `initialY` で起動時にスクロール位置を復元
///   - スクロール変化を `onScrollChange` クロージャに通知 (PresetManager 経由で
///     panel ごとに永続化される)
/// 内部の `NSClipView.bounds.didChange` notification で変化を拾い、
/// `documentView` には flipped 座標系の NSView を使うので `bounds.origin.y` が
/// 「上から何ピクセル下にスクロールしているか」になる (Cocoa の標準 bottom-up
/// 座標と一致しない代わりに直感的な値になる)。
struct PanelScrollView<Content: View>: NSViewRepresentable {

    /// 起動時のスクロール位置 (上から下へのピクセル数、非負)。
    let initialY: CGFloat
    /// スクロール位置が変化したときに呼ばれる。引数は現在の `scrollY` (非負)。
    /// メインキューで呼ばれる。
    let onScrollChange: (CGFloat) -> Void
    /// スクロール領域の中身。SwiftUI ビュー。
    let content: Content

    init(initialY: CGFloat,
         onScrollChange: @escaping (CGFloat) -> Void,
         @ViewBuilder content: () -> Content) {
        self.initialY = initialY
        self.onScrollChange = onScrollChange
        self.content = content()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onScrollChange: onScrollChange)
    }

    final class Coordinator: NSObject {
        let onScrollChange: (CGFloat) -> Void
        var hostingView: NSHostingView<Content>?
        var clipObserver: NSObjectProtocol?
        var documentFrameObserver: NSObjectProtocol?
        /// 起動時に反映したい scrollY。SwiftUI のレイアウトが終わって documentView
        /// の高さがこの値+clipView 高さに達するまで `frameDidChangeNotification`
        /// で再試行し続け、反映できたら nil にして購読解除する。
        var pendingInitialY: CGFloat?
        /// スクロール変化を `onScrollChange` に流すかどうか。`scroll(to:)` で
        /// 自分が動かしたときにエコーバックを抑える (= 復元値で上書きされて
        /// 永続化済みの値を破壊するのを防ぐ)。
        var suppressNotify = false

        init(onScrollChange: @escaping (CGFloat) -> Void) {
            self.onScrollChange = onScrollChange
        }

        deinit {
            if let o = clipObserver { NotificationCenter.default.removeObserver(o) }
            if let o = documentFrameObserver { NotificationCenter.default.removeObserver(o) }
        }

        @objc func clipBoundsChanged(_ note: Notification) {
            guard !suppressNotify, let clip = note.object as? NSClipView else { return }
            // documentView は flipped なので origin.y は「上端から何ピクセル下に
            // スクロールしているか」を表す。負値 (バウンス) は 0 にクランプ。
            let y = max(0, clip.bounds.origin.y)
            onScrollChange(y)
        }
    }

    /// `NSView` に直接 hostingView を addSubview すると親の resize に追従しない
    /// ので、autoresizing で幅追従しつつ高さは intrinsic に任せる documentView。
    private final class FlippedDocumentView: NSView {
        override var isFlipped: Bool { true }
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScrollElasticity = .allowed
        scrollView.horizontalScrollElasticity = .none

        let document = FlippedDocumentView()
        document.translatesAutoresizingMaskIntoConstraints = false

        let hosting = NSHostingView(rootView: content)
        context.coordinator.hostingView = hosting
        hosting.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(hosting)

        // 横方向は親 (clipView) の幅にぴったり、縦方向は SwiftUI コンテンツの
        // intrinsic な高さに任せる (= スクロール対象になる長さ)。
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: document.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: document.bottomAnchor),
        ])
        scrollView.documentView = document

        // documentView の幅を clipView の幅と一致させる。これがないと NSHostingView
        // の intrinsic width に引っ張られて横スクロールが発生する。
        scrollView.contentView.postsBoundsChangedNotifications = true
        let widthConstraint = document.widthAnchor.constraint(
            equalTo: scrollView.contentView.widthAnchor)
        widthConstraint.priority = .required
        widthConstraint.isActive = true

        // スクロール位置の変化を監視。
        context.coordinator.clipObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak coord = context.coordinator] note in
            coord?.clipBoundsChanged(note)
        }

        // documentView の高さは SwiftUI のレイアウト完了が非同期なので、
        // 初回 layout 後に伸びてくる。frameDidChangeNotification で監視し、
        // pendingInitialY が反映できる高さに達したらスクロールして購読解除。
        document.postsFrameChangedNotifications = true
        context.coordinator.pendingInitialY = initialY
        context.coordinator.documentFrameObserver = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: document,
            queue: .main
        ) { [weak coord = context.coordinator, weak scrollView, weak document] _ in
            guard let coord, let scrollView, let document else { return }
            tryApplyPendingInitialOffset(coord: coord, scrollView: scrollView, document: document)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        // SwiftUI 側のコンテンツを差し替え (rootView 更新のみで再生成しない)。
        context.coordinator.hostingView?.rootView = content

        // updateNSView もレイアウト完了タイミングのひとつなので、ここでも試行する
        // (frameDidChangeNotification が間に合わないケースのフォールバック)。
        if let document = scrollView.documentView {
            DispatchQueue.main.async {
                tryApplyPendingInitialOffset(coord: context.coordinator,
                                             scrollView: scrollView,
                                             document: document)
            }
        }
    }

    /// 必要な高さに到達していたら `pendingInitialY` を実 scroll に変換して
    /// 適用、購読を解除する。まだ短ければ何もせず次回 frame 通知を待つ。
    private func tryApplyPendingInitialOffset(coord: Coordinator,
                                              scrollView: NSScrollView,
                                              document: NSView) {
        guard let pending = coord.pendingInitialY else { return }
        let clipHeight = scrollView.contentView.bounds.height
        let docHeight = document.frame.height
        // documentView の高さがまだ確定していない (clipView と同等以下) なら、
        // スクロール余地が無いので保留。レイアウトが進めば再呼出される。
        guard docHeight > clipHeight else { return }

        let maxY = max(0, docHeight - clipHeight)
        let clampedY = min(max(0, pending), maxY)
        coord.suppressNotify = true
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: clampedY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        DispatchQueue.main.async {
            coord.suppressNotify = false
        }

        // 反映完了。購読解除して以降の frame 変化はノータッチに。
        coord.pendingInitialY = nil
        if let observer = coord.documentFrameObserver {
            NotificationCenter.default.removeObserver(observer)
            coord.documentFrameObserver = nil
        }
    }
}
