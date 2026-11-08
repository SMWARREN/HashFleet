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
    struct Cache {
        struct Key: Equatable {
            let width: CGFloat
            let maximumColumns: Int
            let minimumColumnWidth: CGFloat
            let spacing: CGFloat
            let balancesFourItems: Bool
            let itemCount: Int
        }

        var key: Key?
        var frames: [CGRect] = []
        var size: CGSize = .zero

        mutating func clear() {
            key = nil
            frames = []
            size = .zero
        }
    }

    var maximumColumns = 2
    var minimumColumnWidth: CGFloat = 140
    var spacing: CGFloat = 10
    var balancesFourItems = true

    func makeCache(subviews: Subviews) -> Cache {
        Cache()
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        // Invalidate cached frames whenever subviews or intrinsic content identities change,
        // preventing stale row heights under dynamic text, error updates, or hierarchy changes.
        cache.clear()
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
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
        let (_, size) = resolvedLayout(width: width, itemCount: subviews.count, cache: &cache) { index, cellWidth in
            subviews[index].sizeThatFits(ProposedViewSize(width: cellWidth, height: nil)).height
        }
        return size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        let (placedFrames, _) = resolvedLayout(width: bounds.width, itemCount: subviews.count, cache: &cache) { index, cellWidth in
            subviews[index].sizeThatFits(ProposedViewSize(width: cellWidth, height: nil)).height
        }
        for (index, frame) in placedFrames.enumerated() where index < subviews.count {
            subviews[index].place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                                 anchor: .topLeading,
                                 proposal: ProposedViewSize(width: frame.width, height: frame.height))
        }
    }

    /// Production layout resolver used by both sizeThatFits and placeSubviews.
    /// Reuses measured frames when width, itemCount, and geometry configuration match cache.
    internal func resolvedLayout(
        width: CGFloat,
        itemCount: Int,
        cache: inout Cache,
        height: (Int, CGFloat) -> CGFloat
    ) -> (frames: [CGRect], size: CGSize) {
        let normalizedWidth = width.isFinite ? max(0, width) : 0
        let key = Cache.Key(
            width: normalizedWidth,
            maximumColumns: maximumColumns,
            minimumColumnWidth: minimumColumnWidth,
            spacing: spacing,
            balancesFourItems: balancesFourItems,
            itemCount: itemCount
        )

        // Reuse cached frames and size when dimensions, count, and layout geometry match exactly
        if let cachedKey = cache.key, cachedKey == key, cache.frames.count == itemCount {
            return (cache.frames, cache.size)
        }

        // Measure layout frames using production geometry
        let config = FleetMinerDetailGeometry.FramesConfiguration(
            itemCount: itemCount,
            width: normalizedWidth,
            maximumColumns: maximumColumns,
            minimumColumnWidth: minimumColumnWidth,
            spacing: spacing,
            balancesFourItems: balancesFourItems
        )
        let calculatedFrames = FleetMinerDetailGeometry.frames(configuration: config, height: height)
        let calculatedHeight = calculatedFrames.map(\.maxY).max() ?? 0
        let calculatedSize = CGSize(width: normalizedWidth, height: calculatedHeight)

        cache.key = key
        cache.frames = calculatedFrames
        cache.size = calculatedSize
        return (calculatedFrames, calculatedSize)
    }
}
