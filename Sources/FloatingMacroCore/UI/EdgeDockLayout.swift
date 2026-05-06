import Foundation

public struct EdgeDockLayout {
    /// 同一辺にドックされたバー群の配置位置を計算する。
    /// バーは辺の中央を基準に等間隔（gap = 4pt）で並べる。
    ///
    /// - Parameters:
    ///   - edge: ドック先の辺
    ///   - screenFrame: `NSScreen.visibleFrame` 相当（menuBar/Dock 除外済み）
    ///   - bars: この辺にドックされるバーの (id, size) リスト（表示順）
    /// - Returns: 各 id に対応する origin (x, y)
    public static func positions(
        edge: DockEdge,
        screenFrame: CGRect,
        bars: [(id: String, size: CGSize)]
    ) -> [(id: String, origin: CGPoint)] {
        guard !bars.isEmpty else { return [] }

        let gap: CGFloat = 4

        switch edge {
        case .left, .right:
            let totalHeight = bars.map(\.size.height).reduce(0, +)
                + CGFloat(bars.count - 1) * gap
            var y = screenFrame.midY + totalHeight / 2

            return bars.map { bar in
                y -= bar.size.height
                let x: CGFloat
                if edge == .right {
                    x = screenFrame.maxX - bar.size.width
                } else {
                    x = screenFrame.minX
                }
                let origin = CGPoint(x: x, y: y)
                y -= gap
                return (id: bar.id, origin: origin)
            }

        case .top, .bottom:
            let totalWidth = bars.map(\.size.width).reduce(0, +)
                + CGFloat(bars.count - 1) * gap
            var x = screenFrame.midX - totalWidth / 2

            return bars.map { bar in
                let y: CGFloat
                if edge == .top {
                    y = screenFrame.maxY - bar.size.height
                } else {
                    y = screenFrame.minY
                }
                let origin = CGPoint(x: x, y: y)
                x += bar.size.width + gap
                return (id: bar.id, origin: origin)
            }
        }
    }
}
