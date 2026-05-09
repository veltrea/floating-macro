import SwiftUI
import AppKit
import Combine

/// 使い捨てのスクロール調査用デバッグストア。各 PanelScrollView インスタンスが
/// 自分の最新測定値をここに書き込み、デバッグウィンドウが Combine で購読する。
final class ScrollDebugStore: ObservableObject {
    static let shared = ScrollDebugStore()

    struct Snapshot: Identifiable {
        let id: ObjectIdentifier
        var label: String
        var hostingFrame: CGSize
        var hostingIntrinsic: CGSize
        var documentFrame: CGSize
        var clipBounds: CGSize
        var lastUpdate: Date
    }

    @Published private(set) var snapshots: [Snapshot] = []

    private init() {}

    func update(id: ObjectIdentifier,
                label: String,
                hostingFrame: CGSize,
                hostingIntrinsic: CGSize,
                documentFrame: CGSize,
                clipBounds: CGSize) {
        if let idx = snapshots.firstIndex(where: { $0.id == id }) {
            snapshots[idx].label = label
            snapshots[idx].hostingFrame = hostingFrame
            snapshots[idx].hostingIntrinsic = hostingIntrinsic
            snapshots[idx].documentFrame = documentFrame
            snapshots[idx].clipBounds = clipBounds
            snapshots[idx].lastUpdate = Date()
        } else {
            snapshots.append(Snapshot(
                id: id,
                label: label,
                hostingFrame: hostingFrame,
                hostingIntrinsic: hostingIntrinsic,
                documentFrame: documentFrame,
                clipBounds: clipBounds,
                lastUpdate: Date()
            ))
        }
    }

    func remove(id: ObjectIdentifier) {
        snapshots.removeAll { $0.id == id }
    }
}

private struct ScrollDebugView: View {
    @ObservedObject var store = ScrollDebugStore.shared
    @State private var tick: Int = 0

    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if store.snapshots.isEmpty {
                    Text("スクロールビューがマウントされていません")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(store.snapshots) { snap in
                        snapshotRow(snap)
                    }
                }
            }
            .padding(12)
        }
        .frame(minWidth: 380, minHeight: 200)
        .onReceive(timer) { _ in tick &+= 1 }
    }

    @ViewBuilder
    private func snapshotRow(_ s: ScrollDebugStore.Snapshot) -> some View {
        let docVsClip = s.documentFrame.height - s.clipBounds.height
        let intrinsicMissing = s.hostingIntrinsic.height < 1
        let frameTooSmall = s.hostingFrame.height < s.hostingIntrinsic.height - 1

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(s.label).font(.headline)
                Spacer()
                Text(timeAgo(s.lastUpdate))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            grid([
                ("hosting.frame",     fmt(s.hostingFrame)),
                ("hosting.intrinsic", fmt(s.hostingIntrinsic)),
                ("document.frame",    fmt(s.documentFrame)),
                ("clip.bounds",       fmt(s.clipBounds)),
            ])
            HStack(spacing: 8) {
                badge("doc>clip: \(Int(docVsClip))",
                      ok: docVsClip > 0)
                if intrinsicMissing {
                    badge("intrinsic.h=0", ok: false)
                }
                if frameTooSmall {
                    badge("frame.h < intrinsic.h", ok: false)
                }
            }
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(6)
    }

    private func grid(_ rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(rows, id: \.0) { k, v in
                HStack {
                    Text(k)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 130, alignment: .leading)
                    Text(v)
                        .font(.system(size: 11, design: .monospaced))
                }
            }
        }
    }

    private func fmt(_ size: CGSize) -> String {
        String(format: "%.0f × %.0f", size.width, size.height)
    }

    private func badge(_ text: String, ok: Bool) -> some View {
        Text(text)
            .font(.system(size: 10, design: .monospaced))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background((ok ? Color.green : Color.red).opacity(0.25))
            .cornerRadius(4)
    }

    private func timeAgo(_ d: Date) -> String {
        let dt = Date().timeIntervalSince(d)
        if dt < 1 { return "now" }
        return String(format: "%.1fs ago", dt)
    }
}

enum ScrollDebugWindow {
    private static var controller: NSWindowController?

    static func toggle() {
        if let c = controller, c.window?.isVisible == true {
            c.close()
            controller = nil
            return
        }
        let host = NSHostingController(rootView: ScrollDebugView())
        let window = NSWindow(
            contentViewController: host
        )
        window.title = "Scroll Debug"
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 420, height: 480))
        window.isReleasedWhenClosed = false
        window.center()
        let c = NSWindowController(window: window)
        c.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        controller = c
    }
}
