import SwiftUI

/// Shared row geometry preserves source order, uses at most three columns, and
/// gives an incomplete row of one item the entire row. Mac pages also avoid sparse rows
/// when neighboring sections have substantially different measured heights.
enum FleetBalancedRowGeometry {
    static func frames(
        itemCount: Int,
        width: CGFloat,
        columns: Int,
        spacing: CGFloat,
        avoidsUnevenRows: Bool = false,
        height: (Int, CGFloat) -> CGFloat
    ) -> [CGRect] {
        guard itemCount > 0 else { return [] }
        let width = width.isFinite ? max(0, width) : 0
        let columns = min(3, max(1, columns))
        let spacing = spacing.isFinite ? min(width, max(0, spacing)) : 0
        var result: [CGRect] = []
        var originY: CGFloat = 0
        var start = 0
        while start < itemCount {
            let rowCount = min(columns, itemCount - start)
            let rowSpacing = rowCount > 1
                ? min(spacing, width / CGFloat(rowCount - 1))
                : spacing
            let cellWidth = max(0, (width - rowSpacing * CGFloat(rowCount - 1)) / CGFloat(rowCount))
            let measuredHeights = (0..<rowCount).map { height(start + $0, cellWidth) }
            let spansRow = rowCount == columns
                && columns > 1
                && avoidsUnevenRows
                && needsFullRow(heights: measuredHeights)
            let visibleCount = spansRow ? 1 : rowCount
            let rowWidths = spansRow
                ? [width]
                : Array(repeating: cellWidth, count: rowCount)
            let rowHeights = spansRow ? [height(start, width)] : measuredHeights
            var rowHeight: CGFloat = 0
            for offset in 0..<visibleCount {
                let measuredHeight = rowHeights[offset]
                let cellHeight = measuredHeight.isFinite ? max(0, measuredHeight) : 0
                result.append(CGRect(
                    x: CGFloat(offset) * (rowWidths[offset] + rowSpacing),
                    y: originY,
                    width: rowWidths[offset],
                    height: cellHeight
                ))
                rowHeight = max(rowHeight, cellHeight)
            }
            originY += rowHeight + rowSpacing
            start += spansRow ? 1 : rowCount
        }
        return result
    }

    /// Small wrapping differences can share a row. A large unused area cannot.
    static func needsFullRow(heights: [CGFloat]) -> Bool {
        let valid = heights.map { $0.isFinite ? max(0, $0) : 0 }
        guard let tallest = valid.max(), let shortest = valid.min() else { return false }
        return tallest - shortest > max(84, tallest * 0.35)
    }
}

struct FleetBalancedColumnsLayout: Layout {
    var columns = 2
    var spacing: CGFloat = FleetLayout.cardGridSpacing
    var minimumColumnWidth: CGFloat = 320
    var avoidsUnevenRows: Bool = FleetLayout.isMac

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width: CGFloat
        if let proposedWidth = proposal.width, proposedWidth.isFinite {
            width = max(0, proposedWidth)
        } else {
            let idealWidth = subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
            let idealColumns = min(3, min(max(1, columns), max(1, subviews.count)))
            width = idealWidth * CGFloat(idealColumns) + spacing * CGFloat(idealColumns - 1)
        }
        let frames = frames(width: width, subviews: subviews)
        return CGSize(width: width, height: frames.map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = frames(width: bounds.width, subviews: subviews)
        for (index, frame) in frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
        }
    }

    private func frames(width: CGFloat, subviews: Subviews) -> [CGRect] {
        let availableColumns = Self.fittingColumnCount(
            availableWidth: width,
            maximumColumns: columns,
            itemCount: subviews.count,
            minimumColumnWidth: minimumColumnWidth,
            spacing: spacing
        )
        return FleetBalancedRowGeometry.frames(
            itemCount: subviews.count,
            width: width,
            columns: availableColumns,
            spacing: spacing,
            avoidsUnevenRows: avoidsUnevenRows
        ) { index, cellWidth in
            subviews[index].sizeThatFits(ProposedViewSize(width: cellWidth, height: nil)).height
        }
    }

    static func fittingColumnCount(
        availableWidth: CGFloat,
        maximumColumns: Int,
        itemCount: Int,
        minimumColumnWidth: CGFloat,
        spacing: CGFloat
    ) -> Int {
        let requested = min(3, max(1, maximumColumns))
        guard itemCount > 0 else { return 0 }
        let itemLimited = min(requested, itemCount)
        guard availableWidth.isFinite, minimumColumnWidth.isFinite, minimumColumnWidth > 0 else {
            return 1
        }
        let width = max(0, availableWidth)
        let gap = spacing.isFinite ? max(0, spacing) : 0
        var fit = 1
        if itemLimited > 1 {
            for candidate in 2...itemLimited {
                let requiredWidth = minimumColumnWidth * CGFloat(candidate)
                    + gap * CGFloat(candidate - 1)
                guard requiredWidth.isFinite else { break }
                if width >= requiredWidth {
                    fit = candidate
                } else {
                    break
                }
            }
        }
        return fit
    }
}

/// Forms and reading pages remain single-column on mobile and at accessibility sizes.
struct FleetSectionGrid<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let spacing: CGFloat
    let minimumRows: Int
    let content: Content

    init(spacing: CGFloat = FleetLayout.cardGridSpacing, minimumRows: Int = 1,
         @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.minimumRows = minimumRows
        self.content = content()
    }

    var body: some View {
        #if os(macOS)
        FleetAlignedSectionColumnsLayout(
            columns: dynamicTypeSize.isAccessibilitySize ? 1 : 3,
            spacing: spacing,
            minimumRows: minimumRows
        ) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        #else
        FleetBalancedColumnsLayout(
            columns: FleetLayout.isMac && !dynamicTypeSize.isAccessibilitySize ? 3 : 1,
            spacing: spacing
        ) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        #endif
    }
}

/// A page introduction is not a settings card. Keep it above the card rows at every width.
struct FleetSectionFullWidthKey: LayoutValueKey {
    static let defaultValue = false
}

/// Automatic introduction placement must not overwrite a caller's explicit span.
struct FleetSectionAutomaticFullWidthKey: LayoutValueKey {
    static let defaultValue = false
}

struct FleetSectionSurfaceKey: LayoutValueKey {
    static let defaultValue = false
}

extension View {
    @ViewBuilder
    func fleetSectionFullWidth() -> some View {
        #if os(macOS)
        layoutValue(key: FleetSectionFullWidthKey.self, value: true)
        #else
        self
        #endif
    }

    /// Opt in only for standalone cards inside FleetSectionGrid. Their surface must
    /// accept the row height, without making cards in ordinary stacks grow forever.
    @ViewBuilder
    func fleetSectionGridCardContent() -> some View {
        #if os(macOS)
        frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        #else
        self
        #endif
    }
}

private enum FleetSectionSurfaceTop: AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> CGFloat { 0 }
}

private enum FleetSectionSurfaceBottom: AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> CGFloat { context.height }
}

extension VerticalAlignment {
    static let fleetSectionSurfaceTop = VerticalAlignment(FleetSectionSurfaceTop.self)
    static let fleetSectionSurfaceBottom = VerticalAlignment(FleetSectionSurfaceBottom.self)
}

/// Separate the card from its header and footer. Equal overall section heights alone do not
/// align the surfaces when one section has a title or a longer explanatory footer.
struct FleetSectionMeasurement {
    var above: CGFloat
    var surface: CGFloat
    var below: CGFloat

    var height: CGFloat { above + surface + below }
}

enum FleetAlignedSectionGeometry {
    struct Grid {
        let width: CGFloat
        let columns: Int
        let spacing: CGFloat
    }

    /// A short page should read down the window, not occupy one shallow row.
    /// Full-width introductions and charts are not cards available to fill columns.
    static func columnLimit(cardCount: Int, maximumColumns: Int, minimumRows: Int) -> Int {
        min(max(1, maximumColumns), max(1, cardCount / max(1, minimumRows)))
    }

    static func frames(
        itemCount: Int,
        grid: Grid,
        fullWidth: (Int) -> Bool,
        measure: (Int, CGFloat) -> FleetSectionMeasurement
    ) -> [CGRect] {
        guard itemCount > 0 else { return [] }
        let width = grid.width.isFinite ? max(0, grid.width) : 0
        let columns = min(3, max(1, grid.columns))
        let gap = grid.spacing.isFinite ? max(0, min(grid.spacing, width)) : 0
        var frames: [CGRect] = []
        var index = 0
        var y: CGFloat = 0

        while index < itemCount {
            var count = 1
            if !fullWidth(index) {
                while count < columns, index + count < itemCount, !fullWidth(index + count) {
                    count += 1
                }
            }
            var cellWidth = max(0, (width - gap * CGFloat(count - 1)) / CGFloat(count))
            var measurements = (0..<count).map { measure(index + $0, cellWidth) }
            // A small difference should stretch the shorter surface, not break a useful row.
            // Keep the largest compatible prefix together. A tall third section must not
            // force the two matching short cards ahead of it into separate full-width rows.
            while count > 1 {
                let heights = measurements.map(\.surface)
                let tallest = heights.max() ?? 0
                let shortest = heights.min() ?? 0
                guard tallest - shortest > max(180, tallest * 0.6) else { break }
                count -= 1
                cellWidth = max(0, (width - gap * CGFloat(count - 1)) / CGFloat(count))
                measurements = (0..<count).map { measure(index + $0, cellWidth) }
            }
            let above = measurements.map(\.above).max() ?? 0
            let surface = measurements.map(\.surface).max() ?? 0
            let below = measurements.map(\.below).max() ?? 0
            for offset in 0..<count {
                let item = measurements[offset]
                frames.append(CGRect(
                    x: CGFloat(offset) * (cellWidth + gap),
                    y: y + above - item.above,
                    width: cellWidth,
                    height: item.above + surface + item.below
                ))
            }
            y += above + surface + below + gap
            index += count
        }
        return frames
    }
}

/// The grid measures real section alignment guides and offers each card the same surface
/// height. Headers and footers retain their own natural heights outside that shared surface.
private struct FleetAlignedSectionColumnsLayout: Layout {
    let columns: Int
    let spacing: CGFloat
    let minimumRows: Int

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? max(0, $0) : nil }
            ?? subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        let frames = frames(width: width, subviews: subviews)
        return CGSize(width: width, height: frames.map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (index, frame) in frames(width: bounds.width, subviews: subviews).enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
        }
    }

    private func frames(width: CGFloat, subviews: Subviews) -> [CGRect] {
        let cardCount = subviews.filter {
            !$0[FleetSectionFullWidthKey.self] && !$0[FleetSectionAutomaticFullWidthKey.self]
        }.count
        let count = FleetBalancedColumnsLayout.fittingColumnCount(
            availableWidth: width,
            maximumColumns: FleetAlignedSectionGeometry.columnLimit(
                cardCount: cardCount, maximumColumns: columns, minimumRows: minimumRows
            ),
            itemCount: subviews.count,
            minimumColumnWidth: 320, spacing: spacing
        )
        return FleetAlignedSectionGeometry.frames(
            itemCount: subviews.count,
            grid: FleetAlignedSectionGeometry.Grid(width: width, columns: count, spacing: spacing),
            fullWidth: {
                subviews[$0][FleetSectionFullWidthKey.self]
                    || subviews[$0][FleetSectionAutomaticFullWidthKey.self]
            },
            measure: { index, cellWidth in
                let child = subviews[index]
                let dimensions = child.dimensions(in: ProposedViewSize(width: cellWidth, height: nil))
                guard child[FleetSectionSurfaceKey.self] else {
                    return FleetSectionMeasurement(above: 0, surface: dimensions.height, below: 0)
                }
                let top = dimensions[VerticalAlignment.fleetSectionSurfaceTop]
                let bottom = dimensions[VerticalAlignment.fleetSectionSurfaceBottom]
                return FleetSectionMeasurement(
                    above: top, surface: max(0, bottom - top), below: max(0, dimensions.height - bottom)
                )
            }
        )
    }
}

/// Exactly three children: heading, expandable surface, footer. The surface alone absorbs
/// the row's extra height, so a two-line footer can never push that card's bottom upward.
struct FleetSectionChromeLayout: Layout {
    var spacing: CGFloat = 8

    private func metrics(_ proposal: ProposedViewSize, _ subviews: Subviews) -> FleetSectionMeasurement {
        guard subviews.count == 3 else { return .init(above: 0, surface: 0, below: 0) }
        let natural = subviews.map { $0.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil)).height }
        let above = natural[0] > 0 ? natural[0] + spacing : 0
        let below = natural[2] > 0 ? natural[2] + spacing : 0
        let offered = proposal.height.flatMap { $0.isFinite ? $0 - above - below : nil } ?? natural[1]
        return .init(above: above, surface: max(natural[1], offered), below: below)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        let measured = metrics(ProposedViewSize(width: width, height: proposal.height), subviews)
        return CGSize(width: width, height: measured.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else { return }
        let measured = metrics(ProposedViewSize(width: bounds.width, height: bounds.height), subviews)
        let headerHeight = max(0, measured.above - spacing)
        let footerHeight = max(0, measured.below - spacing)
        for (index, y, height) in [(0, CGFloat.zero, headerHeight),
                                   (1, measured.above, measured.surface),
                                   (2, measured.above + measured.surface + (footerHeight > 0 ? spacing : 0), footerHeight)] {
            subviews[index].place(
                at: CGPoint(x: bounds.minX, y: bounds.minY + y), anchor: .topLeading,
                proposal: ProposedViewSize(width: bounds.width, height: height)
            )
        }
    }

    func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize,
                           subviews: Subviews, cache: inout ()) -> CGFloat? {
        let measured = metrics(ProposedViewSize(width: bounds.width, height: bounds.height), subviews)
        if guide == .fleetSectionSurfaceTop { return measured.above }
        if guide == .fleetSectionSurfaceBottom { return measured.above + measured.surface }
        return nil
    }
}
