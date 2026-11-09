//
//  FleetHashrateShareCard.swift
//  HashFleet
//
//  Share calculation adapted from ShipSwift (MIT) - SWDonutChart.swift.
//  Shown inside the Fleet hashrate card as a segmented bar with a per-miner legend.
//

import SwiftUI
import HashFleetCore

/// Pure model and calculation for miner hashrate distribution across the fleet.
enum FleetHashrateShare {
    struct Slice: Identifiable, Equatable, Sendable {
        let id: UUID
        let name: String
        let hashrate: Double
        let fraction: Double
        let colorIndex: Int

        var deviceId: UUID { id }

        init(
            id: UUID,
            name: String,
            hashrate: Double,
            fraction: Double,
            colorIndex: Int
        ) {
            self.id = id
            self.name = name
            self.hashrate = hashrate
            self.fraction = fraction
            self.colorIndex = colorIndex
        }

        var color: Color {
            FleetChartPalette.color(for: colorIndex)
        }

        var percentage: Double {
            fraction * 100
        }

        var percentageString: String {
            let value = fraction * 100
            return "\(value.formatted(.number.precision(.fractionLength(0...1))))%"
        }

        var formattedHashrate: String {
            FleetFormat.hashrateWithUnit(hashrate)
        }
    }

    /// Computes sorted slices representing each online SHA-256 miner's share of the fleet.
    /// Excludes XMRig/CPU miners, offline devices, and zero/negative hashrate readings.
    /// Returns slices sorted descending by hashrate, guaranteed to sum to 1.0.
    static func slices(
        devices: [MinerDevice],
        snapshots: [UUID: MinerSnapshot]
    ) -> [Slice] {
        // Exclude XMRig/CPU miners (only .espMiner is SHA-256)
        let sha256Devices = devices.filter { $0.kind == .espMiner }

        struct Candidate {
            let device: MinerDevice
            let rate: Double
        }

        var candidates: [Candidate] = []
        for device in sha256Devices {
            guard let snapshot = snapshots[device.id],
                  snapshot.error == nil,
                  !snapshot.isReconnecting,
                  let info = snapshot.info
            else { continue }

            let rate = FleetMetricTotal.reading(info, keys: FleetTotals.hashrateKeys) ?? info.hashRate
            guard rate.isFinite, rate > 0 else { continue }
            candidates.append(Candidate(device: device, rate: rate))
        }

        guard !candidates.isEmpty else { return [] }

        // Sort descending by hashrate; tie-break stably by miner name then id
        let sorted = candidates.sorted {
            if $0.rate != $1.rate {
                return $0.rate > $1.rate
            }
            if $0.device.name != $1.device.name {
                return $0.device.name < $1.device.name
            }
            return $0.device.id.uuidString < $1.device.id.uuidString
        }

        let total = sorted.reduce(0.0) { $0 + $1.rate }
        guard total > 0 else { return [] }

        // Fractions sum to exactly 1.0
        var remaining = 1.0
        return sorted.enumerated().map { index, item in
            let fraction: Double
            if index == sorted.count - 1 {
                fraction = max(0, remaining)
            } else {
                let calc = item.rate / total
                fraction = calc
                remaining -= calc
            }
            return Slice(
                id: item.device.id,
                name: item.device.name,
                hashrate: item.rate,
                fraction: fraction,
                colorIndex: index
            )
        }
    }
}

/// Each miner's share of the fleet hashrate, drawn inside the dark Fleet hashrate card:
/// one thin segmented bar plus a wrapping legend. Static (no animation), so live updates
/// only re-lay out a few shapes once per second.
struct FleetHashrateShareStrip: View {
    let slices: [FleetHashrateShare.Slice]

    /// The hero card is charcoal in both light and dark mode, so use bright fixed colors
    /// rather than the adaptive chart palette (whose light-mode colors are dark).
    static let panelColors: [Color] = [
        Color(red: 0xF5 / 255, green: 0xAC / 255, blue: 0x26 / 255),
        Color(red: 0x2A / 255, green: 0xAE / 255, blue: 0x68 / 255),
        Color(red: 0x7A / 255, green: 0xB6 / 255, blue: 0xEC / 255),
        Color(red: 0xC6 / 255, green: 0xCE / 255, blue: 0xD6 / 255),
        Color(red: 0xE0 / 255, green: 0x7A / 255, blue: 0xB8 / 255)
    ]

    static func panelColor(_ index: Int) -> Color { panelColors[index % panelColors.count] }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SHARE BY MINER")
                .fleetFont(.caption2, weight: .semibold, design: .monospaced)
                .tracking(0.8)
                .foregroundStyle(FleetTheme.panelSecondary)
            bar
            legend
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hashrate share by miner")
        .accessibilityValue(slices.map { "\($0.name) \($0.percentageString)" }.joined(separator: ", "))
        .accessibilityIdentifier("dashboard.hashrateShare")
    }

    private var bar: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 2
            let usable = max(0, proxy.size.width - spacing * CGFloat(max(0, slices.count - 1)))
            HStack(spacing: spacing) {
                ForEach(slices) { slice in
                    Rectangle()
                        .fill(Self.panelColor(slice.colorIndex))
                        .frame(width: max(2, usable * slice.fraction))
                        .help("\(slice.name): \(slice.percentageString) · \(slice.formattedHashrate)")
                }
            }
        }
        .frame(height: 8)
        .clipShape(Capsule())
        .transaction { $0.animation = nil }
    }

    private var legend: some View {
        FleetFlowLayout(spacing: 12, lineSpacing: 6) {
            ForEach(slices) { slice in
                HStack(spacing: 6) {
                    Circle().fill(Self.panelColor(slice.colorIndex)).frame(width: 7, height: 7)
                    Text(slice.name)
                        .foregroundStyle(FleetTheme.panelInk)
                    Text(slice.percentageString)
                        .foregroundStyle(FleetTheme.panelSecondary)
                        .monospacedDigit()
                }
                .fleetFont(.caption)
                .help(slice.formattedHashrate)
            }
        }
    }
}

/// Minimal wrapping row layout for short legend items.
struct FleetFlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                y += lineHeight + lineSpacing
                x = 0
                lineHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: width.isFinite ? width : maxX, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += lineHeight + lineSpacing
                x = bounds.minX
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
