import SwiftUI
import HashFleetCore

/// The scrollable ASIC/core rail of the tuning workspace. Every card reflects the shared
/// board-wide setpoints, so the rail is read-only and only scrolls the enclosing workspace.
struct MinerTuningASICRail: View {
    let proxy: ScrollViewProxy
    let chipCount: Int
    let coreReadings: [MinerTuningCoreReading]
    let frequency: Double?
    let stagedVoltage: Double?
    let referenceMaximum: Double?
    let isAnyBeyondReference: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Label("ASIC channel rail", systemImage: "square.stack.3d.up.fill")
                        .fleetFont(.headline)
                    Text("Scroll past each ASIC/core. The controls above edit the shared board setpoints.")
                        .fleetFont(.caption)
                        .foregroundStyle(FleetTheme.secondary)
                }
                Spacer(minLength: 8)
                Text("\(chipCount) total")
                    .fleetFont(.caption, weight: .semibold)
                    .foregroundStyle(FleetTheme.accent)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(1...chipCount, id: \.self) { number in
                        Button("ASIC \(number)") {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                                proxy.scrollTo("tuningSession.asic.\(number)", anchor: .center)
                            }
                        }
                        .fleetFont(.caption, weight: .semibold)
                        .buttonStyle(.bordered)
                        .tint(isAnyBeyondReference ? .red : FleetTheme.accent)
                        .accessibilityIdentifier("tuningSession.jump.\(number)")
                    }
                }
            }
            LazyVStack(spacing: 12) {
                ForEach(1...chipCount, id: \.self) { number in
                    MinerTuningASICCard(
                        number: number,
                        coreReading: coreReadings[number - 1],
                        frequency: frequency,
                        stagedVoltage: stagedVoltage,
                        referenceMaximum: referenceMaximum,
                        isBeyondReference: isAnyBeyondReference,
                        accessibilityPrefix: "tuningSession.asic.\(number)"
                    )
                    .id("tuningSession.asic.\(number)")
                }
            }
        }
        .accessibilityIdentifier("tuningSession.asicSection")
    }
}
