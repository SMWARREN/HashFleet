import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Actual Production FleetMinerDetailGrid Cache Regression Tests

@main
struct FleetMinerDetailGridCacheRegressionTests {
    static func main() {
        print("Running FleetMinerDetailGrid Cache Regression Tests (with unconditional preconditions under -O)...")
        testGeometryPreservation()
        print("PASS: testGeometryPreservation")
        testDegenerateWidths()
        print("PASS: testDegenerateWidths")
        testActualProductionResolvedLayoutCacheHitAndMiss()
        print("PASS: testActualProductionResolvedLayoutCacheHitAndMiss")
        testAllKeyFieldsTriggerRecomputation()
        print("PASS: testAllKeyFieldsTriggerRecomputation")
        testCacheClearForcesRecomputationWithChangedHeight()
        print("PASS: testCacheClearForcesRecomputationWithChangedHeight")
        #if canImport(AppKit)
        testActualNSHostingViewObservedModelAndReflow()
        print("PASS: testActualNSHostingViewObservedModelAndReflow")
        #endif
        print("All FleetMinerDetailGrid cache regression checks passed successfully with active preconditions.")
    }

    // MARK: - 1. Exact Production Geometry Output Preservation

    static func testGeometryPreservation() {
        let testWidths: [CGFloat] = [320, 480, 728, 1028, 2056]

        // 2 items: metric pairs
        for width in testWidths {
            let config = FleetMinerDetailGeometry.FramesConfiguration(
                itemCount: 2,
                width: width,
                maximumColumns: 2,
                minimumColumnWidth: 140,
                spacing: 10
            )
            let frames = FleetMinerDetailGeometry.frames(configuration: config) { index, _ in
                index == 0 ? 60 : 95
            }
            precondition(frames.count == 2)
            precondition(frames[0].height == 95 && frames[1].height == 95)
            precondition(abs(frames[0].width - (width - 10) / 2) < 0.001)
            precondition(abs(frames[1].maxX - width) < 0.001)
            precondition(frames[0].minY == frames[1].minY)
        }

        // 4 items: balanced 2x2 vs 4-column (threshold: 4*130 + 3*8 = 544)
        for width in testWidths {
            let config = FleetMinerDetailGeometry.FramesConfiguration(
                itemCount: 4,
                width: width,
                maximumColumns: 4,
                minimumColumnWidth: 130,
                spacing: 8
            )
            let frames = FleetMinerDetailGeometry.frames(configuration: config) { index, _ in
                72 + CGFloat(index * 5)
            }
            let columns = width >= 544 ? 4 : 2
            precondition(frames.count == 4)
            for frame in frames {
                let expectedWidth = (width - CGFloat(columns - 1) * 8) / CGFloat(columns)
                precondition(abs(frame.width - expectedWidth) < 0.001)
            }
        }
    }

    // MARK: - 2. Degenerate Inputs (Zero, Negative, NaN, Inf)

    static func testDegenerateWidths() {
        // Zero count
        let emptyConfig = FleetMinerDetailGeometry.FramesConfiguration(
            itemCount: 0,
            width: 480,
            maximumColumns: 4,
            minimumColumnWidth: 130,
            spacing: 8
        )
        precondition(FleetMinerDetailGeometry.frames(configuration: emptyConfig) { _, _ in 72 }.isEmpty)

        // Non-finite and negative widths
        for width in [CGFloat.zero, -1.0, -100.0, .infinity, -.infinity, .nan] {
            let config = FleetMinerDetailGeometry.FramesConfiguration(
                itemCount: 3,
                width: width,
                maximumColumns: -1,
                minimumColumnWidth: .nan,
                spacing: .infinity
            )
            let frames = FleetMinerDetailGeometry.frames(configuration: config) { index, _ in
                index == 0 ? .infinity : index == 1 ? .nan : -5.0
            }
            precondition(frames.count == 3)
            for f in frames {
                precondition(f.minX.isFinite && f.minX >= 0)
                precondition(f.minY.isFinite && f.minY >= 0)
                precondition(f.width.isFinite && f.width >= 0)
                precondition(f.height.isFinite && f.height >= 0)
            }
        }
    }

    // MARK: - 3. Actual Production resolvedLayout Cache Hit and Miss Verification

    static func testActualProductionResolvedLayoutCacheHitAndMiss() {
        let grid = FleetMinerDetailGrid(maximumColumns: 2, minimumColumnWidth: 320, spacing: 14, balancesFourItems: false)
        var cache = FleetMinerDetailGrid.Cache()

        var measurementsPerformed = 0
        let measurementClosure: (Int, CGFloat) -> CGFloat = { _, _ in
            measurementsPerformed += 1
            return 100.0
        }

        // Pass 1: Initial resolution (models sizeThatFits at width 1024)
        let (frames1, size1) = grid.resolvedLayout(
            width: 1024,
            itemCount: 20,
            cache: &cache,
            height: measurementClosure
        )
        precondition(measurementsPerformed == 20, "Pass 1 must measure all 20 items once")
        precondition(frames1.count == 20)
        precondition(size1.width == 1024)
        precondition(cache.key != nil)
        precondition(cache.frames.count == 20)

        // Pass 2: Identical resolution (models placeSubviews at same bounds width 1024)
        let (frames2, size2) = grid.resolvedLayout(
            width: 1024,
            itemCount: 20,
            cache: &cache,
            height: measurementClosure
        )
        precondition(measurementsPerformed == 20, "Pass 2 MUST reuse cache with ZERO duplicate measurements")
        precondition(frames2 == frames1, "Pass 2 must return identical cached frames")
        precondition(size2 == size1, "Pass 2 must return identical cached size")

        // Pass 3: New width 1280 (cache miss)
        let (frames3, size3) = grid.resolvedLayout(
            width: 1280,
            itemCount: 20,
            cache: &cache,
            height: measurementClosure
        )
        precondition(measurementsPerformed == 40, "Pass 3 must trigger re-measurement for new width")
        precondition(size3.width == 1280)
        precondition(frames3 != frames1)
    }

    // MARK: - 4. All Geometry Key Fields Invalidate Cache

    static func testAllKeyFieldsTriggerRecomputation() {
        var measurements = 0
        let measure: (Int, CGFloat) -> CGFloat = { _, _ in
            measurements += 1
            return 80.0
        }

        var grid = FleetMinerDetailGrid(maximumColumns: 2, minimumColumnWidth: 320, spacing: 14, balancesFourItems: false)
        var cache = FleetMinerDetailGrid.Cache()

        // Baseline
        _ = grid.resolvedLayout(width: 1024, itemCount: 10, cache: &cache, height: measure)
        precondition(measurements == 10)

        // Key field 1: maximumColumns changed
        grid.maximumColumns = 3
        _ = grid.resolvedLayout(width: 1024, itemCount: 10, cache: &cache, height: measure)
        precondition(measurements == 20, "Changing maximumColumns must invalidate cache")

        // Key field 2: minimumColumnWidth changed
        grid.minimumColumnWidth = 200
        _ = grid.resolvedLayout(width: 1024, itemCount: 10, cache: &cache, height: measure)
        precondition(measurements == 30, "Changing minimumColumnWidth must invalidate cache")

        // Key field 3: spacing changed
        grid.spacing = 20
        _ = grid.resolvedLayout(width: 1024, itemCount: 10, cache: &cache, height: measure)
        precondition(measurements == 40, "Changing spacing must invalidate cache")

        // Key field 4: balancesFourItems changed
        grid.balancesFourItems = true
        _ = grid.resolvedLayout(width: 1024, itemCount: 10, cache: &cache, height: measure)
        precondition(measurements == 50, "Changing balancesFourItems must invalidate cache")

        // Key field 5: itemCount changed
        _ = grid.resolvedLayout(width: 1024, itemCount: 8, cache: &cache, height: measure)
        precondition(measurements == 58, "Changing itemCount must invalidate cache")
    }

    // MARK: - 5. updateCache Clears Stale Heights

    static func testCacheClearForcesRecomputationWithChangedHeight() {
        let grid = FleetMinerDetailGrid(maximumColumns: 2, minimumColumnWidth: 320, spacing: 14, balancesFourItems: false)
        var cache = FleetMinerDetailGrid.Cache()

        var currentItemHeight: CGFloat = 100.0
        var measureCalls = 0
        let dynamicMeasure: (Int, CGFloat) -> CGFloat = { _, _ in
            measureCalls += 1
            return currentItemHeight
        }

        // Measure with initial height 100
        let (_, initialSize) = grid.resolvedLayout(width: 1024, itemCount: 4, cache: &cache, height: dynamicMeasure)
        precondition(measureCalls == 4)
        precondition(initialSize.height > 0)

        // Cache hit without clear: returns stale size
        currentItemHeight = 250.0
        let (_, cachedSize) = grid.resolvedLayout(width: 1024, itemCount: 4, cache: &cache, height: dynamicMeasure)
        precondition(measureCalls == 4, "Un-cleared cache returns cached size without measuring")
        precondition(cachedSize.height == initialSize.height)

        // Explicit cache clear (models updateCache when subviews or content change)
        cache.clear()
        precondition(cache.key == nil)

        // Resolution after clear measures updated 250pt content
        let (_, updatedSize) = grid.resolvedLayout(width: 1024, itemCount: 4, cache: &cache, height: dynamicMeasure)
        precondition(measureCalls == 8, "Cleared cache must re-measure changed heights")
        precondition(updatedSize.height > initialSize.height, "Updated layout size must reflect expanded content")
    }

    // MARK: - 6. Actual NSHostingView Same-Root Observed Model Test

    #if canImport(AppKit)
    @MainActor
    final class ObservedGridModel: ObservableObject {
        @Published var itemHeight: CGFloat
        @Published var text: String
        @Published var fontSize: CGFloat

        init(itemHeight: CGFloat = 50, text: String = "Item", fontSize: CGFloat = 14) {
            self.itemHeight = itemHeight
            self.text = text
            self.fontSize = fontSize
        }
    }

    @MainActor
    static func testActualNSHostingViewObservedModelAndReflow() {
        struct ObservedItemView: View {
            @ObservedObject var model: ObservedGridModel
            var body: some View {
                VStack(spacing: 4) {
                    Text(model.text)
                        .font(.system(size: model.fontSize))
                    Color.blue
                        .frame(height: model.itemHeight)
                }
                .frame(maxWidth: .infinity)
            }
        }

        struct HostedTestGrid: View {
            @ObservedObject var model: ObservedGridModel
            var body: some View {
                FleetMinerDetailGrid(maximumColumns: 2, minimumColumnWidth: 100, spacing: 10) {
                    ObservedItemView(model: model)
                    ObservedItemView(model: model)
                }
            }
        }

        let model = ObservedGridModel(itemHeight: 50, text: "Initial", fontSize: 14)
        let host = NSHostingView(rootView: HostedTestGrid(model: model))
        host.frame = NSRect(x: 0, y: 0, width: 300, height: 400)

        func pumpRunLoop(seconds: TimeInterval) {
            let deadline = Date().addingTimeInterval(seconds)
            while Date() < deadline {
                _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
            }
            host.needsLayout = true
            host.layoutSubtreeIfNeeded()
        }

        // 1. Initial measurement
        pumpRunLoop(seconds: 0.1)
        let initialFitting = host.fittingSize
        precondition(initialFitting.height >= 50, "Initial fitting height must accommodate 50pt items")

        // 2. Expand height on SAME root view through observed model mutation
        model.itemHeight = 150
        pumpRunLoop(seconds: 0.15)
        let expandedFitting = host.fittingSize
        precondition(expandedFitting.height >= 150, "Fitting size must refresh when observed model expands height")
        precondition(expandedFitting.height > initialFitting.height, "Expanded content must increase fitting height")

        // 3. Shrink height on SAME root view
        model.itemHeight = 35
        pumpRunLoop(seconds: 0.15)
        let shrunkFitting = host.fittingSize
        precondition(shrunkFitting.height < expandedFitting.height, "Shrunk content must reduce fitting height")

        // 4. Width reflow (300pt 1-col/2-col boundary to 600pt wide)
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        pumpRunLoop(seconds: 0.1)
        let wideFitting = host.fittingSize
        precondition(wideFitting.width.isFinite && wideFitting.height.isFinite)

        // 5. Large font text scenario on SAME root view
        model.fontSize = 38
        model.text = "Significantly Longer Dynamic Header Text"
        pumpRunLoop(seconds: 0.15)
        let largeTextFitting = host.fittingSize
        precondition(largeTextFitting.height > shrunkFitting.height, "Large font text must expand row height")
    }
    #endif
}
