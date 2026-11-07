import SwiftUI

/// Item-aware rows for miner readings and controls. Unlike an adaptive GridItem, this
/// never reserves empty columns. Heights come from the actual contents at each width,
/// and every surface in a row receives the tallest measured height.
enum FleetMinerDetailGeometry {
    struct FramesConfiguration {
        let itemCount: Int
        let width: CGFloat
        let maximumColumns: Int
        let minimumColumnWidth: CGFloat
        let spacing: CGFloat
        let balancesFourItems: Bool

        init(
            itemCount: Int,
            width: CGFloat,
            maximumColumns: Int,
            minimumColumnWidth: CGFloat,
            spacing: CGFloat,
            balancesFourItems: Bool = true
        ) {
            self.itemCount = itemCount
            self.width = width
            self.maximumColumns = maximumColumns
            self.minimumColumnWidth = minimumColumnWidth
            self.spacing = spacing
            self.balancesFourItems = balancesFourItems
        }
    }

    static func frames(
        configuration config: FramesConfiguration,
        height: (Int, CGFloat) -> CGFloat
    ) -> [CGRect] {
        guard config.itemCount > 0 else { return [] }
        let width = config.width.isFinite ? max(0, config.width) : 0
        let gap = config.spacing.isFinite ? max(0, config.spacing) : 0
        let minimum = config.minimumColumnWidth.isFinite ? max(1, config.minimumColumnWidth) : 1
        let limit = min(config.itemCount, min(4, max(1, config.maximumColumns)))
        var columns = 1
        if limit > 1 {
            for candidate in 2...limit where width >= minimum * CGFloat(candidate) + gap * CGFloat(candidate - 1) {
                columns = candidate
            }
        }
        // Four sibling actions read as a balanced 2-by-2 group until all four fit.
        if config.balancesFourItems && config.itemCount == 4 && columns == 3 { columns = 2 }
        var frames: [CGRect] = []
        var y: CGFloat = 0
        var start = 0
        while start < config.itemCount {
            let count = min(columns, config.itemCount - start)
            let rowGap = count > 1 ? min(gap, width / CGFloat(count - 1)) : 0
            let cellWidth = max(0, (width - rowGap * CGFloat(count - 1)) / CGFloat(count))
            let rowHeight = (0..<count).map { offset in
                let measured = height(start + offset, cellWidth)
                return measured.isFinite ? max(0, measured) : 0
            }.max() ?? 0
            for offset in 0..<count {
                frames.append(CGRect(x: CGFloat(offset) * (cellWidth + rowGap), y: y,
                                     width: cellWidth, height: rowHeight))
            }
            y += rowHeight + gap
            start += count
        }
        return frames
    }
}

struct FleetMinerDetailGrid: Layout {
    var maximumColumns = 2
    var minimumColumnWidth: CGFloat = 140
    var spacing: CGFloat = 10
    var balancesFourItems = true

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width: CGFloat
        if let proposed = proposal.width, proposed.isFinite {
            width = max(0, proposed)
        } else {
            let idealColumns = min(max(1, subviews.count), min(4, max(1, maximumColumns)))
            let idealCell = subviews.map { $0.sizeThatFits(.unspecified).width }
                .filter(\.isFinite).max() ?? minimumColumnWidth
            width = max(minimumColumnWidth, idealCell) * CGFloat(idealColumns)
                + max(0, spacing) * CGFloat(idealColumns - 1)
        }
        let frames = frames(width: width, subviews: subviews)
        return CGSize(width: width, height: frames.map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (index, frame) in frames(width: bounds.width, subviews: subviews).enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                                 anchor: .topLeading,
                                 proposal: ProposedViewSize(width: frame.width, height: frame.height))
        }
    }

    private func frames(width: CGFloat, subviews: Subviews) -> [CGRect] {
        let config = FleetMinerDetailGeometry.FramesConfiguration(
            itemCount: subviews.count,
            width: width,
            maximumColumns: maximumColumns,
            minimumColumnWidth: minimumColumnWidth,
            spacing: spacing,
            balancesFourItems: balancesFourItems
        )
        return FleetMinerDetailGeometry.frames(configuration: config) { index, width in
            subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil)).height
        }
    }
}
