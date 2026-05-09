import SwiftUI
import AppKit
import FloatingMacroCore

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
    /// デバッグウィンドウに表示するラベル (パネル名等)。
    let debugLabel: String
    /// スクロール領域の中身。SwiftUI ビュー。
    let content: Content

    init(initialY: CGFloat,
         debugLabel: String = "Panel",
         onScrollChange: @escaping (CGFloat) -> Void,
         @ViewBuilder content: () -> Content) {
        self.initialY = initialY
        self.debugLabel = debugLabel
        self.onScrollChange = onScrollChange
        self.content = content()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onScrollChange: onScrollChange)
    }

    final class Coordinator: NSObject {
        let onScrollChange: (CGFloat) -> Void
        var hostingView: NSHostingView<Content>?
        weak var scrollViewRef: NSScrollView?
        weak var documentRef: NSView?
        var clipObserver: NSObjectProtocol?
        var hostingFrameObserver: NSObjectProtocol?
        var debugTimer: Timer?
        var debugLabel: String = "Panel"
        /// 起動時に反映したい scrollY。SwiftUI のレイアウトが終わって documentView
        /// の高さがこの値+clipView 高さに達するまで再試行し続け、反映できたら nil
        /// にして購読解除する。
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
            if let o = hostingFrameObserver { NotificationCenter.default.removeObserver(o) }
            debugTimer?.invalidate()
            ScrollDebugStore.shared.remove(id: ObjectIdentifier(self))
        }

        @objc func clipBoundsChanged(_ note: Notification) {
            guard !suppressNotify, let clip = note.object as? NSClipView else { return }
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

        // hosting を document の 4 辺にピン留め。
        // 横方向は document 幅（= clipView 幅）に従い、
        // 縦方向は hosting の intrinsicContentSize が document 高さを決める。
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: document.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: document.bottomAnchor),
        ])
        scrollView.documentView = document

        // documentView の幅を clipView の幅と一致させる。
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

        // NSHostingView の frame 変化を監視。Auto Layout で高さが確定した後に
        // documentView の frame を明示的に同期する。NSScrollView は
        // documentView.frame.size でスクロール可能範囲を決定するため、
        // Auto Layout だけでは反映が遅れるケースを補う。
        hosting.postsFrameChangedNotifications = true
        context.coordinator.pendingInitialY = initialY
        context.coordinator.hostingFrameObserver = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: hosting,
            queue: .main
        ) { [weak coord = context.coordinator, weak scrollView, weak document, weak hosting] _ in
            guard let coord, let scrollView, let document, let hosting else { return }
            let intrinsicH = hosting.intrinsicContentSize.height
            let frameH = hosting.frame.height
            // intrinsic と frame の大きい方を採用 (intrinsic=0 を返すケースのフォールバック)
            // さらに余白を上下それぞれ 200 加算する。
            let baseH = max(intrinsicH, frameH)
            let targetH = baseH > 0 ? baseH : 0
            if targetH > 0, abs(document.frame.height - targetH) > 1 {
                document.setFrameSize(NSSize(width: document.frame.width, height: targetH))
            }
            // 初期スクロール位置の復元。
            tryApplyPendingInitialOffset(coord: coord, scrollView: scrollView,
                                         docHeight: targetH)
        }

        context.coordinator.scrollViewRef = scrollView
        context.coordinator.documentRef = document
        context.coordinator.debugLabel = debugLabel
        startDebugSampling(coord: context.coordinator)

        return scrollView
    }

    private func startDebugSampling(coord: Coordinator) {
        coord.debugTimer?.invalidate()
        let coordId = ObjectIdentifier(coord)
        let timer = Timer(timeInterval: 0.3, repeats: true) { [weak coord] _ in
            guard let coord,
                  let hosting = coord.hostingView,
                  let scrollView = coord.scrollViewRef,
                  let document = coord.documentRef else { return }
            ScrollDebugStore.shared.update(
                id: coordId,
                label: coord.debugLabel,
                hostingFrame: hosting.frame.size,
                hostingIntrinsic: hosting.intrinsicContentSize,
                documentFrame: document.frame.size,
                clipBounds: scrollView.contentView.bounds.size
            )
        }
        RunLoop.main.add(timer, forMode: .common)
        coord.debugTimer = timer
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.hostingView?.rootView = content
        context.coordinator.debugLabel = debugLabel

        if let document = scrollView.documentView,
           let hosting = context.coordinator.hostingView {
            DispatchQueue.main.async {
                let intrinsicH = hosting.intrinsicContentSize.height
                let frameH = hosting.frame.height
                let baseH = max(intrinsicH, frameH)
                let targetH = baseH > 0 ? baseH + 400 : 0
                if targetH > 0, abs(document.frame.height - targetH) > 1 {
                    document.setFrameSize(NSSize(width: document.frame.width,
                                                  height: targetH))
                }
                tryApplyPendingInitialOffset(coord: context.coordinator,
                                             scrollView: scrollView,
                                             docHeight: targetH)
            }
        }
    }

    private func tryApplyPendingInitialOffset(coord: Coordinator,
                                              scrollView: NSScrollView,
                                              docHeight: CGFloat) {
        guard let pending = coord.pendingInitialY else { return }
        let clipHeight = scrollView.contentView.bounds.height
        guard docHeight > clipHeight else { return }

        let maxY = max(0, docHeight - clipHeight)
        let clampedY = min(max(0, pending), maxY)
        coord.suppressNotify = true
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: clampedY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        DispatchQueue.main.async {
            coord.suppressNotify = false
        }
        coord.pendingInitialY = nil
    }
}
