import SwiftUI
import HashFleetWatchCore

struct WatchSetupInboxView: View {
    let transfer: WatchFleetSetupTransfer
    let store: WatchFleetStore
    let onFinished: () -> Void
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Add miners from iPhone?")
                        .font(.headline)
                    Text("Saved on this Watch. Readings will work without your phone on the miners’ Wi-Fi.")
                        .font(.footnote)
                    ForEach(transfer.miners) { miner in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(miner.name)
                            Text(miner.address).font(.caption).foregroundStyle(.secondary)
                        }
                        .privacySensitive()
                    }
                }
                Section {
                    Button("Import miners", systemImage: "square.and.arrow.down") {
                        do {
                            _ = try store.importMiners(transfer.miners)
                            onFinished()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                    .accessibilityIdentifier("watch.setup.import")
                    Button("Not now", role: .cancel, action: onFinished)
                        .accessibilityIdentifier("watch.setup.cancel")
                    Text("Keeps your existing Watch miners. No miner settings are changed.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let errorMessage {
                        Text(errorMessage).font(.footnote).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("iPhone setup")
            .interactiveDismissDisabled()
        }
    }
}
