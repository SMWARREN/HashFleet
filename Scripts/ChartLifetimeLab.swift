// Diagnostic entry point only. Never add this file to a shipping app target.
// Use an isolated frozen source tree and app.hashfleet.chartlab bundle namespace.
#if DEBUG
import SwiftUI
import Charts
import HashFleetCore
import Observation
import Darwin

// Offline-only diagnostic entry point. All store, background, widget and hardware startup
// paths are intentionally absent. The chart below is the unchanged production builder.
@main
struct OfflineChartLabApp: App {
    init() {
        guard Bundle.main.bundleIdentifier?.hasPrefix("app.hashfleet.chartlab.") == true else {
            print("CHART_LAB_FAILED requires an isolated app.hashfleet.chartlab bundle identifier")
            exit(64)
        }
    }

    var body: some Scene {
        WindowGroup {
            if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
                Color.clear
            } else {
                OfflineChartLabView()
            }
        }
    }
}

@MainActor
@Observable
private final class OfflineChartLabModel {
    var revision = 0
    @ObservationIgnored var renderedRevisions = Set<Int>()
    @ObservationIgnored var samples: [[String: UInt64]] = []
    @ObservationIgnored var stoppedAtMemoryLimit = false
    @ObservationIgnored var measurementFailed = false
    let arguments = ProcessInfo.processInfo.arguments

    var updateCount: Int {
        guard let index = arguments.firstIndex(of: "--chart-updates"), index + 1 < arguments.count,
              let count = Int(arguments[index + 1]) else { return 2_000 }
        return min(max(count, 1), 20_000)
    }

    var histories: [MinerHistorySeries] {
        let count = arguments.contains("--single-series") || arguments.contains("--fragmented") ? 1 : 4
        let base = arguments.contains("--full-card")
            ? Date()
            : Date(timeIntervalSince1970: 1_790_000_000 + Double(revision))
        return (0..<count).map { series in
            let id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", series + 1))!
            let pointCount = arguments.contains("--fragmented") ? 12_288 : 240
            let points = (0..<pointCount).map { point in
                let offset = arguments.contains("--fragmented")
                    ? Double((point / 96) * 1_200 + (point % 96) * 5)
                    : Double(point - 239) * 10
                return HashratePoint(
                    date: base.addingTimeInterval(offset),
                    value: 2_500 + Double(series * 200) + sin(Double(point + revision) / 7) * 120
                )
            }
            return MinerHistorySeries(id: id, name: "Offline fixture \(series + 1)", points: points)
        }
    }

    func recordRender() { renderedRevisions.insert(revision) }

    func sample() {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        let value: [String: UInt64] = [
            "revision": UInt64(revision), "rendered": UInt64(renderedRevisions.count),
            "physFootprint": info.phys_footprint, "resident": info.resident_size,
            "taskInfoStatus": UInt64(status)
        ]
        samples.append(value)
        stoppedAtMemoryLimit = stoppedAtMemoryLimit || info.phys_footprint > 256 * 1_024 * 1_024
        measurementFailed = measurementFailed || status != KERN_SUCCESS
        print("CHART_LAB_SAMPLE \(value)")
        fflush(nil)
    }

    func run() async {
        let startedAt = ProcessInfo.processInfo.systemUptime
        if arguments.contains("--full-card") &&
            ["--fragmented", "--selection", "--windows", "--no-axes"].contains(where: arguments.contains) {
            print("CHART_LAB_FAILED full-card mode does not support direct-chart-only options")
            fflush(nil)
            if arguments.contains("--exit-on-complete") { exit(64) }
            return
        }
        try? await Task.sleep(for: .seconds(1))
        sample()
        for index in 1...updateCount {
            if stoppedAtMemoryLimit || measurementFailed { break }
            guard !Task.isCancelled else { return }
            revision = index
            // Yield a complete display interval so updates reach Swift Charts rather than
            // merely mutating a data array repeatedly inside one coalesced transaction.
            try? await Task.sleep(for: .milliseconds(22))
            if index.isMultiple(of: arguments.contains("--fragmented") ? 10 : 250) { sample() }
        }
        try? await Task.sleep(for: .seconds(1))
        sample()
        let complete = revision == updateCount && !stoppedAtMemoryLimit && !measurementFailed &&
            Double(renderedRevisions.count) >= Double(updateCount) * 0.95
        let result: [String: Any] = [
            "updates": updateCount, "completedUpdates": revision,
            "stoppedAtMemoryLimit": stoppedAtMemoryLimit,
            "measurementFailed": measurementFailed, "complete": complete,
            "elapsedSeconds": ProcessInfo.processInfo.systemUptime - startedAt,
            "renderedRevisions": renderedRevisions.count,
            "arguments": arguments, "samples": samples,
            "os": ProcessInfo.processInfo.operatingSystemVersionString
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            if let index = arguments.firstIndex(of: "--result-path"), index + 1 < arguments.count {
                try data.write(to: URL(fileURLWithPath: arguments[index + 1]), options: .withoutOverwriting)
            } else {
                #if os(macOS)
                throw CocoaError(.fileNoSuchFile)
                #else
                let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                try data.write(to: directory.appendingPathComponent("chart-lab-result.json"), options: .atomic)
                #endif
            }
        } catch {
            print("CHART_LAB_FAILED result write: \(error)")
            fflush(nil)
            if arguments.contains("--exit-on-complete") { exit(74) }
            return
        }
        print("CHART_LAB_COMPLETE requested=\(updateCount) completed=\(revision) rendered=\(renderedRevisions.count) passed=\(complete)")
        fflush(nil)
        if arguments.contains("--exit-on-complete") { exit(complete ? 0 : 1) }
    }
}

private struct OfflineChartLabView: View {
    @State private var model = OfflineChartLabModel()

    var body: some View {
        let histories = model.histories
        let selection = model.arguments.contains("--selection") && model.revision % 20 < 10
            ? FleetChartSelection.resolve(at: histories[0].points[120].date, in: histories,
                                          tolerance: 60, clusterTolerance: 60)
            : nil
        let _ = model.recordRender()
        VStack {
            Text("Offline Charts lifetime test").font(.headline)
            Text("Update \(model.revision) / \(model.updateCount)").monospacedDigit()
            Group {
                if model.arguments.contains("--full-card") {
                    let devices = histories.map {
                        MinerDevice(id: $0.id, name: $0.name, address: "offline.invalid", kind: .espMiner)
                    }
                    let snapshots = Dictionary(uniqueKeysWithValues: histories.map {
                        ($0.id, MinerSnapshot(history: $0.points))
                    })
                    FleetHistoryCard(devices: devices, snapshots: snapshots, isDemo: true,
                                     isMinerDetail: model.arguments.contains("--detail"))
                } else {
                    chart(histories, selection: selection)
                }
            }
            .id(model.arguments.contains("--remount") ? model.revision / 250 : 0)
            .frame(maxWidth: .infinity)
            Text("Synthetic data only. No mining or phone access.").font(.caption)
        }
        .padding(20)
        .frame(minWidth: 320, minHeight: 420)
        .task { await model.run() }
    }

    @ViewBuilder
    private func chart(_ histories: [MinerHistorySeries], selection: FleetChartSelection?) -> some View {
        let card = FleetHistoryCard(devices: [], snapshots: [:], isDemo: true,
                                   isMinerDetail: model.arguments.contains("--detail"))
        let segments = model.arguments.contains("--fragmented")
            ? FleetHistoryPresentation.segments(histories[0].points) : nil
        let window = model.arguments.contains("--windows")
            ? HistoryWindow.allCases[(model.revision / 100) % HistoryWindow.allCases.count] : .daily
        let chart = card.historyChart(histories, window: window, selection: selection, segments: segments)
        if model.arguments.contains("--no-axes") {
            chart.chartXAxis(.hidden).chartYAxis(.hidden)
        } else {
            chart
        }
    }
}

#endif
