import HashFleetWatchCore
import SwiftUI

/// Search status stays on the fleet screen so there is no keyboard or phone-dependent setup step.
struct WatchDiscoverySection: View {
    let discovery: WatchMinerDiscoveryController
    let store: WatchFleetStore

    var body: some View {
        Section {
            if discovery.isScanning {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Finding miners", systemImage: "wifi")
                        .font(.headline)
                    if discovery.totalHosts > 0 {
                        ProgressView(value: Double(discovery.completedHosts), total: Double(discovery.totalHosts))
                        Text("\(discovery.completedHosts) of \(discovery.totalHosts) checked · \(discovery.foundCount) found")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                        Text("Looking on the Watch’s Wi-Fi…")
                            .font(.footnote)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("watch.discovery.progress")

                Button("Stop search", systemImage: "stop.circle") { discovery.cancel() }
                    .accessibilityIdentifier("watch.discovery.stop")
            } else {
                Button("Scan for miners", systemImage: "wifi") { discovery.start(store: store) }
                    .accessibilityIdentifier("watch.discovery.scan")
                    .accessibilityHint("Finds and saves compatible miners on the Watch’s local Wi-Fi. Miner settings are never changed.")

                if let message = discovery.message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(discovery.addedCount == nil ? .secondary : Color.hashGold)
                        .accessibilityIdentifier("watch.discovery.result")
                }
            }

            if discovery.isPartialSubnet {
                Text("Large network: only this Watch’s local address block is searched. Manual setup can reach other local addresses.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if discovery.reachedTimeLimit {
                Text("Search time limit reached. Results may be incomplete. You can scan again.")
                    .font(.footnote)
                    .foregroundStyle(Color.hashCaution)
            }
        }
    }
}
