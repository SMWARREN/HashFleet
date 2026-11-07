import Charts
import CoreGraphics
import SwiftUI
import Testing
@testable import HashFleetMac

@Suite("Native chart containment", .serialized)
struct FleetNativeChartContainmentTests {
    private let width: CGFloat = 320
    @MainActor private var productionCard: FleetHistoryCard {
        FleetHistoryCard(devices: [], snapshots: [:], isDemo: true, isMinerDetail: true)
    }
    @MainActor private var chartHeight: CGFloat { productionCard.effectiveChartHeight }
    private let spillProbeHeight: CGFloat = 48
    private let probeColor = Color(red: 1, green: 0, blue: 1)

    private var sampleDates: [Date] {
        let start = Date(timeIntervalSince1970: 1_760_000_000)
        return (0..<5).map { start.addingTimeInterval(Double($0) * 60) }
    }

    private var sampleHashratesGHs: [Double] {
        [2_990, 3_010, 3_000, 3_020, 3_005]
    }

    @MainActor
    private func chart(clipped: Bool) -> AnyView {
        let dates = sampleDates
        let ratesTHs = sampleHashratesGHs.map { $0 / 1_000 }
        let focusedDomain = FleetHistoryPresentation.focusedYDomain(for: ratesTHs) ?? 0...1
        let points = zip(dates, sampleHashratesGHs).map { date, value in
            HashratePoint(date: date, value: value)
        }
        if clipped {
            let productionChart = productionCard.historyChart(
                [MinerHistorySeries(name: "Offline chart fixture", points: points)],
                window: .daily,
                selection: nil
            )
            return AnyView(productionChart.frame(width: width))
        }

        // Positive control mirrors the production marks and focused domain but deliberately omits
        // chartPlotStyle clipping, so the test proves its contrasting probe can detect the spill.
        let base = Chart {
            ForEach(Array(ratesTHs.enumerated()), id: \.offset) { index, rate in
                AreaMark(
                    x: .value("Time", dates[index]),
                    y: .value("Hashrate", rate),
                    series: .value("Series", "demo")
                )
                .foregroundStyle(Color.orange.opacity(0.75))
                LineMark(
                    x: .value("Time", dates[index]),
                    y: .value("Hashrate", rate),
                    series: .value("Series", "demo")
                )
                .foregroundStyle(Color.orange)
            }
        }
        .chartXScale(domain: dates.first!...dates.last!)
        .chartYScale(domain: focusedDomain)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .frame(width: width, height: chartHeight)

        return AnyView(base)
    }

    @MainActor
    private func renderedPixels(includeChart: Bool, clipped: Bool) -> (CGImage, Data)? {
        // Paint the independent parent probe behind the chart. A later sibling would
        // cover overflow and make even the deliberately unclipped control look safe.
        let view = ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                Color.black.frame(width: width, height: chartHeight)
                probeColor.frame(width: width, height: spillProbeHeight)
            }
            if includeChart {
                chart(clipped: clipped)
            }
        }
        .frame(width: width, height: chartHeight + spillProbeHeight, alignment: .topLeading)
        .background(Color.black)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        guard let image = renderer.cgImage,
              let providerData = image.dataProvider?.data as Data? else { return nil }
        return (image, providerData)
    }

    private func changedPixels(
        in rows: Range<Int>, image: CGImage, actual: Data, baseline: Data
    ) -> Int {
        let bytesPerPixel = image.bitsPerPixel / 8
        guard bytesPerPixel == 4 else { return Int.max }
        let bytesPerRow = image.bytesPerRow
        var changedPixels = 0
        for y in rows {
            for x in 0..<image.width {
                let offset = y * bytesPerRow + x * bytesPerPixel
                guard offset + bytesPerPixel <= actual.count,
                      offset + bytesPerPixel <= baseline.count else { continue }
                if actual[offset..<(offset + bytesPerPixel)] != baseline[offset..<(offset + bytesPerPixel)] {
                    changedPixels += 1
                }
            }
        }
        return changedPixels
    }

    private func baselineProbeRows(image: CGImage, pixels: Data) -> Range<Int>? {
        let bytesPerPixel = image.bitsPerPixel / 8
        guard bytesPerPixel == 4 else { return nil }

        // CGImage provider row zero need not correspond to the top of the SwiftUI view. Identify
        // the parent-only magenta run from the contrasting baseline instead of assuming an edge.
        let rowColors = (0..<image.height).compactMap { row -> UInt32? in
            let offset = row * image.bytesPerRow + (image.width / 2) * bytesPerPixel
            guard offset + bytesPerPixel <= pixels.count else { return nil }
            return UInt32(pixels[offset])
                | (UInt32(pixels[offset + 1]) << 8)
                | (UInt32(pixels[offset + 2]) << 16)
                | (UInt32(pixels[offset + 3]) << 24)
        }
        guard rowColors.count == image.height,
              let chartBackdrop = Dictionary(grouping: rowColors, by: { $0 })
                .max(by: { $0.value.count < $1.value.count })?.key else { return nil }

        let probeRows = rowColors.indices.filter { rowColors[$0] != chartBackdrop }
        guard let first = probeRows.first, let last = probeRows.last,
              last - first + 1 == probeRows.count else { return nil }
        return first..<(last + 1)
    }

    @MainActor
    @Test(arguments: [CGFloat(320), 680, 1720])
    func nativeHistoryKeepsItsIntrinsicHeightAcrossRepeatedRenders(width: CGFloat) throws {
        let suite = "app.hashfleet.tests.native-history-layout.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FleetStore(defaults: defaults)
        store.loadDemo()
        let device = try #require(store.devices.first)
        let card = FleetHistoryCard(
            devices: [device], snapshots: store.snapshots(for: [device.id]), isDemo: true,
            initialDisplay: .miners, isMinerDetail: true
        )
        var firstHeight: Int?
        for _ in 0..<3 {
            let renderer = ImageRenderer(content: card.frame(width: width))
            renderer.scale = 1
            let image = try #require(renderer.cgImage)
            #expect(image.width == Int(width))
            #expect(image.height > 0 && image.height < 1600,
                    "Native history must have a finite content-sized height, not grow from its own measurement")
            if let firstHeight {
                #expect(image.height == firstHeight,
                        "Rendering identical native history must converge to the same height")
            } else {
                firstHeight = image.height
            }
        }
    }

    @MainActor
    @Test func focusedAreaMarkStaysInsideChartAndUnclippedControlSpills() throws {
        let baseline = try #require(renderedPixels(includeChart: false, clipped: true))
        let clipped = try #require(renderedPixels(includeChart: true, clipped: true))
        let unclipped = try #require(renderedPixels(includeChart: true, clipped: false))

        #expect(clipped.0.width == baseline.0.width)
        #expect(clipped.0.height == baseline.0.height)
        let probe = try #require(baselineProbeRows(image: baseline.0, pixels: baseline.1))
        #expect(probe.count == Int(spillProbeHeight),
                "The baseline should identify exactly the parent-only probe height")
        let controlDiff = changedPixels(
            in: probe, image: unclipped.0, actual: unclipped.1, baseline: baseline.1
        )
        let clippedDiff = changedPixels(
            in: probe, image: clipped.0, actual: clipped.1, baseline: baseline.1
        )
        #expect(controlDiff > 0,
                "The unclipped positive control should change pixels in the parent probe below the chart")
        #expect(clippedDiff == 0,
                "The production clipped focused-domain chart must leave the contrasting parent probe unchanged")
    }
}
