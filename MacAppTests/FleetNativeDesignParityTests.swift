import AppKit
import HashFleetCore
import SwiftUI
import Testing
@testable import HashFleetMac

@MainActor
@Suite("Native shared design parity")
struct FleetNativeDesignParityTests {
    @Test func paletteResolvesToTheApprovedSharedColorsInBothAppearances() {
        let palette: [(name: String, color: Color, light: UInt32, dark: UInt32)] = [
            ("canvas", FleetTheme.canvas, 0xFFFFFF, 0x02090C),
            ("surface", FleetTheme.surface, 0xF5F5F5, 0x10191D),
            ("raised", FleetTheme.raised, 0xE5E5E5, 0x182126),
            ("ink", FleetTheme.ink, 0x21201E, 0xF4F6F7),
            ("secondary", FleetTheme.secondary, 0x595959, 0xBFC6CC),
            ("accent", FleetTheme.accent, 0x8A5000, 0xF5AC26),
            ("positive", FleetTheme.positive, 0x356447, 0x25A354),
            ("warning", FleetTheme.warning, 0x864705, 0xF5AC26),
            ("separator", FleetTheme.separator, 0xCCCCCC, 0x27343A)
        ]
        for scheme in [ColorScheme.light, .dark] {
            var environment = EnvironmentValues()
            environment.colorScheme = scheme
            for entry in palette {
                let actual = entry.color.resolve(in: environment)
                let expected = components(scheme == .light ? entry.light : entry.dark)
                #expect(abs(actual.red - expected.red) < 0.005, "\(entry.name) red in \(scheme)")
                #expect(abs(actual.green - expected.green) < 0.005, "\(entry.name) green in \(scheme)")
                #expect(abs(actual.blue - expected.blue) < 0.005, "\(entry.name) blue in \(scheme)")
                #expect(actual.opacity == 1)
            }
        }
    }

    @Test func actualSharedCardRendersTheSameSurfaceAndCanvasColors() throws {
        for scheme in [ColorScheme.light, .dark] {
            let renderer = ImageRenderer(content:
                Color.clear
                    .frame(width: 120, height: 80)
                    .fleetCard(padding: 0, borderWidth: 0)
                    .padding(20)
                    .background(FleetTheme.canvas)
                    .environment(\.colorScheme, scheme)
            )
            renderer.scale = 1
            renderer.colorMode = .nonLinear
            let image = try #require(renderer.cgImage)
            let center = try pixel(in: image, x: 80, y: 60)
            let outside = try pixel(in: image, x: 2, y: 2)
            expectColor(center, equals: scheme == .dark ? 0x10191D : 0xF5F5F5)
            expectColor(outside, equals: scheme == .dark ? 0x02090C : 0xFFFFFF)
        }
    }

    @Test func sharedHeadlineAndBodyKeepTheirDistinctWeights() throws {
        let shared = ImageRenderer(content:
            Text("Workshop Gamma")
                .fleetFont(.headline)
                .fixedSize()
                .environment(\.dynamicTypeSize, .large)
        )
        let reference = ImageRenderer(content:
            Text("Workshop Gamma")
                .font(.system(size: 17, weight: .semibold))
                .fixedSize()
        )
        let actualSize = try #require(shared.nsImage).size
        let expectedSize = try #require(reference.nsImage).size
        #expect(abs(actualSize.width - expectedSize.width) <= 1)
        #expect(abs(actualSize.height - expectedSize.height) <= 1)
    }

    @Test func sharedSettingsRowsPreserveTheMinimumTargetAndLetTextGrow() throws {
        let short = ImageRenderer(content:
            FleetSettingsRow(showsSeparator: false) {
                Text("Realtime miner readings").fleetFont(.body)
            }
            .environment(\.fleetSettingsIsForm, true)
            .frame(width: 280)
        )
        #expect(try #require(short.nsImage).size.height >= 44)

        let paragraph = ImageRenderer(content:
            FleetSettingsRow(showsSeparator: false) {
                Text("A read-only live connection while Fleet is open, with HTTP fallback for miners that cannot stream. This never changes miner hardware.")
                    .fleetFont(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .environment(\.fleetSettingsIsForm, true)
            .frame(width: 280)
        )
        let renderedSize = try #require(paragraph.nsImage).size
        #expect(renderedSize.width == 280)
        #expect(renderedSize.height > 44)
    }

    @Test func formAndListSectionsKeepTheSameInnerCardPadding() throws {
        for isForm in [false, true] {
            let renderer = ImageRenderer(content:
                FleetSettingsSection(surface: Color(.sRGB, red: 0, green: 0, blue: 1, opacity: 1)) {
                    Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 1)
                        .frame(height: 44)
                }
                .environment(\.fleetSettingsIsForm, isForm)
            )
            renderer.proposedSize = ProposedViewSize(width: 240, height: nil)
            renderer.scale = 1
            renderer.colorMode = .nonLinear
            let image = try #require(renderer.cgImage)
            #expect(image.width == 240)
            #expect(image.height == 76)
            for point in [(15, 38), (224, 38), (120, 15), (120, 60)] {
                expectColor(try pixel(in: image, x: point.0, y: point.1), equals: 0x0000FF)
            }
            for point in [(16, 38), (223, 38), (120, 16), (120, 59)] {
                expectColor(try pixel(in: image, x: point.0, y: point.1), equals: 0xFF0000)
            }
        }
    }

    @Test func nativeReadingContainerRendersAcrossTheAvailableWidth() throws {
        for width: CGFloat in [480, 760, 1_100, 1_600] {
            let reading = ImageRenderer(content:
                Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 1).frame(height: 44)
                    .fleetReadableWidth(760)
                    .background(Color(.sRGB, red: 0, green: 0, blue: 1, opacity: 1))
            )
            reading.proposedSize = ProposedViewSize(width: width, height: 44)
            reading.scale = 1
            reading.colorMode = .nonLinear
            let image = try #require(reading.cgImage)
            #expect(image.width == Int(width))
            expectColor(try pixel(in: image, x: Int(width) - 2, y: 22), equals: 0xFF0000)
        }
    }

    @Test func commonPageShellRendersEqualGuttersAtEveryViewportWidth() throws {
        let inset = Int(FleetLayout.pagePadding)
        let contentHeight = 44
        let height = contentHeight + inset * 2
        for width in [480, 760, 1_100, 1_600] {
            let renderer = ImageRenderer(content:
                Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 1)
                    .frame(height: CGFloat(contentHeight))
                    .fleetPageContainer(compactMaxWidth: 760)
                    .background(Color(.sRGB, red: 0, green: 0, blue: 1, opacity: 1))
            )
            renderer.scale = 1
            renderer.colorMode = .nonLinear
            renderer.proposedSize = ProposedViewSize(width: CGFloat(width), height: CGFloat(height))
            let image = try #require(renderer.cgImage)
            #expect(image.width == width)
            #expect(image.height == height)
            for point in [(inset - 1, height / 2), (width - inset, height / 2),
                          (width / 2, inset - 1), (width / 2, height - inset)] {
                expectColor(try pixel(in: image, x: point.0, y: point.1), equals: 0x0000FF)
            }
            for point in [(inset, height / 2), (width - inset - 1, height / 2),
                          (width / 2, inset), (width / 2, height - inset - 1)] {
                expectColor(try pixel(in: image, x: point.0, y: point.1), equals: 0xFF0000)
            }
        }
    }

    @Test func sharedPageGridActuallyRendersOneTwoAndThreeColumns() throws {
        let cases: [(width: Int, category: DynamicTypeSize, columns: Int)] = [
            (600, .large, 1), (900, .large, 2), (1_400, .large, 3),
            (1_400, .accessibility3, 1)
        ]
        let itemCount = 6
        let itemHeight = 44
        let inset = Int(FleetLayout.pagePadding)
        let gap = Int(FleetLayout.sectionSpacing)
        for entry in cases {
            let renderer = ImageRenderer(content:
                FleetSectionGrid(spacing: FleetLayout.sectionSpacing) {
                    ForEach(0..<itemCount, id: \.self) { _ in
                        Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 1)
                            .frame(height: CGFloat(itemHeight))
                    }
                }
                .fleetPageContainer()
                .background(Color(.sRGB, red: 0, green: 0, blue: 1, opacity: 1))
                .environment(\.dynamicTypeSize, entry.category)
            )
            renderer.scale = 1
            renderer.colorMode = .nonLinear
            renderer.proposedSize = ProposedViewSize(width: CGFloat(entry.width), height: nil)
            let image = try #require(renderer.cgImage)
            let rows = itemCount / entry.columns
            #expect(image.width == entry.width)
            #expect(image.height == rows * itemHeight + (rows - 1) * gap + inset * 2)
            let cellWidth = CGFloat(entry.width - inset * 2 - (entry.columns - 1) * gap)
                / CGFloat(entry.columns)
            for row in 0..<rows {
                let y = inset + row * (itemHeight + gap) + itemHeight / 2
                for column in 0..<entry.columns {
                    let x = CGFloat(inset) + CGFloat(column) * (cellWidth + CGFloat(gap))
                    expectColor(try pixel(in: image, x: Int(x + cellWidth / 2), y: y), equals: 0xFF0000)
                    if column + 1 < entry.columns {
                        expectColor(try pixel(in: image, x: Int(x + cellWidth + CGFloat(gap) / 2), y: y), equals: 0x0000FF)
                    }
                }
                expectColor(try pixel(in: image, x: inset - 1, y: y), equals: 0x0000FF)
                expectColor(try pixel(in: image, x: entry.width - inset, y: y), equals: 0x0000FF)
            }
        }
    }

    @Test func mixedSectionHeadersAndFootersKeepTheirActualSurfacesEven() throws {
        for width: CGFloat in [900, 1_756] {
            let renderer = ImageRenderer(content:
                FleetSectionGrid(spacing: FleetLayout.sectionSpacing) {
                    Color.red.frame(height: 48).fleetSectionFullWidth()
                    ForEach(0..<3, id: \.self) { index in
                        FleetSettingsSection(
                            index == 0 ? nil : "Section heading",
                            footer: index == 1 ? "Short note" : (index == 2
                                ? "A longer explanatory footer wraps onto several lines without changing the card surface alignment."
                                : nil),
                            surface: Color(.sRGB, red: 0, green: 1, blue: 0, opacity: 1)
                        ) {
                            Color.clear.frame(height: CGFloat(40 + index * 20))
                        }
                    }
                }
                .fleetPageContainer()
                .background(Color(.sRGB, red: 0, green: 0, blue: 1, opacity: 1))
            )
            renderer.scale = 1
            renderer.proposedSize = ProposedViewSize(width: width, height: nil)
            let image = try #require(renderer.cgImage)
            let columns = width > 1_000 ? 3 : 2
            let cellWidth = (width - 32 - CGFloat(columns - 1) * 16) / CGFloat(columns)
            let first = try colorSpan(in: image, x: Int(16 + cellWidth / 2), rgb: 0x00FF00)
            for column in 1..<columns {
                let next = try colorSpan(in: image,
                    x: Int(16 + CGFloat(column) * (cellWidth + 16) + cellWidth / 2), rgb: 0x00FF00)
                #expect(first.lowerBound == next.lowerBound, "Card top must align with and without a heading")
                #expect(first.upperBound == next.upperBound, "A longer footer must not shorten its card")
            }
            #expect(first.count >= (columns == 3 ? 112 : 92), "Cards must fit the tallest content in their row with 16pt insets")
        }
    }

    @Test func explicitFullWidthSurvivesASectionSurfaceAndAccessibilityWrapper() throws {
        for width: CGFloat in [900, 1_756] {
            let renderer = ImageRenderer(content:
                FleetSectionGrid(spacing: 16) {
                    FleetSettingsSection(surface: Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 1)) {
                        Color.clear.frame(height: 60)
                    }
                    .fleetSettingsSectionIdentifier("regression.intro")
                    .fleetSectionFullWidth()
                    ForEach(0..<2, id: \.self) { index in
                        FleetSettingsSection(surface: Color(.sRGB, red: 0, green: 1, blue: 0, opacity: 1)) {
                            Color.clear.frame(height: CGFloat(40 + index * 20))
                        }
                    }
                }
                .background(Color(.sRGB, red: 0, green: 0, blue: 1, opacity: 1))
            )
            renderer.scale = 1
            renderer.proposedSize = ProposedViewSize(width: width, height: nil)
            let image = try #require(renderer.cgImage)
            expectColor(try pixel(in: image, x: Int(width) - 32, y: 46), equals: 0xFF0000)
            let cellWidth = (width - 16) / 2
            let left = try colorSpan(in: image, x: Int(cellWidth / 2), rgb: 0x00FF00)
            let right = try colorSpan(in: image, x: Int(cellWidth * 1.5 + 16), rgb: 0x00FF00)
            #expect(left == right)
            #expect(left.lowerBound >= 92 + 16, "Both cards must start below the full-width introduction")
        }
    }

    @Test func actualNetworkCardSurfacesAcceptTheSharedRowHeight() throws {
        let now = Date(timeIntervalSince1970: 1_793_000_000)
        let result = MiningDataResult(value: 1, fetchedAt: now,
            sourceURL: try #require(URL(string: "https://network-demo.invalid")))
        for width: CGFloat in [900, 1_756] {
            let renderer = ImageRenderer(content:
                FleetSectionGrid(spacing: 16) {
                    ForEach(0..<3, id: \.self) { index in
                        InsightsSourceCard(title: "Network card", result: result, isDemo: true, now: now) { _ in
                            Color.clear.frame(height: CGFloat(40 + index * 40))
                        }
                    }
                }
                .background(Color(.sRGB, red: 0, green: 0, blue: 1, opacity: 1))
                .environment(\.colorScheme, .dark)
            )
            renderer.scale = 1
            renderer.proposedSize = ProposedViewSize(width: width, height: nil)
            let image = try #require(renderer.cgImage)
            let columns = width > 1_000 ? 3 : 2
            let cellWidth = (width - CGFloat(columns - 1) * 16) / CGFloat(columns)
            let first = try colorSpan(in: image, x: Int(cellWidth / 2), rgb: 0x10191D)
            for column in 1..<columns {
                let next = try colorSpan(in: image,
                    x: Int(CGFloat(column) * (cellWidth + 16) + cellWidth / 2), rgb: 0x10191D)
                #expect(first == next, "Network card surfaces must have equal tops and bottoms, not only equal layout proposals")
            }
        }
    }

    @Test func sectionGeometrySeparatesIntroAndAlignsSurfaceInsteadOfWholeSection() {
        let samples = [
            FleetSectionMeasurement(above: 0, surface: 60, below: 0),
            FleetSectionMeasurement(above: 0, surface: 100, below: 0),
            FleetSectionMeasurement(above: 30, surface: 140, below: 24),
            FleetSectionMeasurement(above: 50, surface: 120, below: 60)
        ]
        let frames = FleetAlignedSectionGeometry.frames(
            itemCount: samples.count, grid: .init(width: 1_500, columns: 3, spacing: 16),
            fullWidth: { $0 == 0 }, measure: { index, _ in samples[index] }
        )
        #expect(frames[0] == CGRect(x: 0, y: 0, width: 1_500, height: 60))
        for index in 1...3 {
            #expect(frames[index].minY + samples[index].above == 126)
            #expect(frames[index].maxY - samples[index].below == 266)
            #expect(frames[index].minY >= frames[0].maxY + 16)
        }
    }

    @Test func sectionGeometryKeepsTallToolsOutOfShortCardRows() {
        let frames = FleetAlignedSectionGeometry.frames(
            itemCount: 3, grid: .init(width: 1_500, columns: 3, spacing: 16),
            fullWidth: { _ in false },
            measure: { index, _ in .init(above: 24, surface: index == 0 ? 900 : 90, below: 0) }
        )
        #expect(frames[0].width == 1_500)
        #expect(frames[1].minY >= frames[0].maxY + 16)
        #expect(frames[1].minY == frames[2].minY)
        #expect(frames[1].height == 114)
        #expect(frames[1].maxY == frames[2].maxY)
    }

    @Test func tallThirdSectionPreservesAnEvenTwoCardPrefix() {
        let frames = FleetAlignedSectionGeometry.frames(
            itemCount: 3, grid: .init(width: 1_756, columns: 3, spacing: 16),
            fullWidth: { _ in false },
            measure: { index, _ in
                .init(above: index == 0 ? 0 : 28, surface: index == 2 ? 680 : 106,
                      below: index == 1 ? 32 : 0)
            }
        )
        #expect(frames[0].width == 870)
        #expect(frames[1].width == 870)
        #expect(frames[0].minY == frames[1].minY + 28)
        #expect(frames[0].maxY == frames[1].maxY - 32)
        #expect(frames[2].width == 1_756)
        #expect(frames[2].minY >= max(frames[0].maxY, frames[1].maxY) + 16)
    }

    @Test func valueRowsUseTrailingEdgesAndStackWithoutOverflow() throws {
        for width: CGFloat in [240, 640] {
            let renderer = ImageRenderer(content:
                LabeledContent {
                    Color(.sRGB, red: 0, green: 1, blue: 0, opacity: 1).frame(width: 120, height: 20)
                } label: {
                    Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 1).frame(width: 160, height: 20)
                }
                .labeledContentStyle(FleetSettingsValueStyle())
                .background(Color(.sRGB, red: 0, green: 0, blue: 1, opacity: 1))
            )
            renderer.scale = 1
            renderer.proposedSize = ProposedViewSize(width: width, height: nil)
            let image = try #require(renderer.cgImage)
            #expect(image.width == Int(width))
            if width > 300 {
                #expect(image.height == 20)
                expectColor(try pixel(in: image, x: Int(width) - 1, y: 10), equals: 0x00FF00)
            } else {
                #expect(image.height == 46)
                #expect(try colorSpan(in: image, x: 60, rgb: 0x00FF00).count == 20)
            }
        }
    }

    @Test func sparsePagesRequireEnoughCardsForAtLeastTwoRows() {
        for count in 0...3 {
            #expect(FleetAlignedSectionGeometry.columnLimit(
                cardCount: count, maximumColumns: 3, minimumRows: 2
            ) == 1)
        }
        for count in 4...5 {
            #expect(FleetAlignedSectionGeometry.columnLimit(
                cardCount: count, maximumColumns: 3, minimumRows: 2
            ) == 2)
        }
        #expect(FleetAlignedSectionGeometry.columnLimit(cardCount: 6, maximumColumns: 3, minimumRows: 2) == 3)
        #expect(FleetAlignedSectionGeometry.columnLimit(cardCount: 9, maximumColumns: 1, minimumRows: 2) == 1)
        #expect(FleetAlignedSectionGeometry.columnLimit(cardCount: -1, maximumColumns: -1, minimumRows: 0) == 1)
    }

    @Test func sparseNativePageActuallyStacksThreeFullWidthSections() throws {
        for width in [900, 1_756] {
            for category in [DynamicTypeSize.large, .accessibility3] {
                let renderer = ImageRenderer(content:
                    FleetSectionGrid(spacing: 16, minimumRows: 2) {
                        Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 1)
                            .frame(height: 48)
                            .fleetSectionFullWidth()
                        ForEach(0..<3, id: \.self) { _ in
                            Color(.sRGB, red: 0, green: 1, blue: 0, opacity: 1)
                                .frame(height: 44)
                        }
                    }
                    .background(Color(.sRGB, red: 0, green: 0, blue: 1, opacity: 1))
                    .environment(\.dynamicTypeSize, category)
                )
                renderer.scale = 1
                renderer.colorMode = .nonLinear
                renderer.proposedSize = ProposedViewSize(width: CGFloat(width), height: nil)
                let image = try #require(renderer.cgImage)
                #expect(image.width == width)
                #expect(image.height == 48 + 3 * (44 + 16))
                expectColor(try pixel(in: image, x: width - 8, y: 24), equals: 0xFF0000)
                for index in 0..<3 {
                    let top = 48 + 16 + index * (44 + 16)
                    for x in [8, width / 2, width - 8] {
                        expectColor(try pixel(in: image, x: x, y: top + 22), equals: 0x00FF00)
                    }
                    expectColor(try pixel(in: image, x: width / 2, y: top - 8), equals: 0x0000FF)
                }
            }
        }
    }

    private func colorSpan(in image: CGImage, x: Int, rgb: UInt32) throws -> ClosedRange<Int> {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(data: nil, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        let matches = (0..<image.height).filter { y in
            let offset = y * context.bytesPerRow + x * 4
            return abs(Int(bytes[offset]) - Int((rgb >> 16) & 255)) <= 1
                && abs(Int(bytes[offset + 1]) - Int((rgb >> 8) & 255)) <= 1
                && abs(Int(bytes[offset + 2]) - Int(rgb & 255)) <= 1
                && bytes[offset + 3] == 255
        }
        let first = try #require(matches.first)
        var last = first
        for y in matches.dropFirst() {
            guard y == last + 1 else { break }
            last = y
        }
        return first...last
    }

    private func components(_ rgb: UInt32) -> (red: Float, green: Float, blue: Float) {
        (Float((rgb >> 16) & 255) / 255, Float((rgb >> 8) & 255) / 255, Float(rgb & 255) / 255)
    }

    /// Read explicit 8-bit sRGB bytes. NSBitmapImageRep.colorAt applies additional
    /// display/HDR color conversion and is not an oracle for the rendered RGB bytes.
    private func pixel(in image: CGImage, x: Int, y: Int) throws -> (red: Int, green: Int, blue: Int, alpha: Int) {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width * 4,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setBlendMode(.copy)
        context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height)))
        let bytes = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        let offset = y * context.bytesPerRow + x * 4
        return (Int(bytes[offset]), Int(bytes[offset + 1]), Int(bytes[offset + 2]), Int(bytes[offset + 3]))
    }

    private func expectColor(_ actual: (red: Int, green: Int, blue: Int, alpha: Int), equals rgb: UInt32) {
        #expect(abs(actual.red - Int((rgb >> 16) & 255)) <= 1)
        #expect(abs(actual.green - Int((rgb >> 8) & 255)) <= 1)
        #expect(abs(actual.blue - Int(rgb & 255)) <= 1)
        #expect(actual.alpha == 255)
    }
}
