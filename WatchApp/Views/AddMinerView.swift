import HashFleetWatchCore
import SwiftUI

/// Manual setup on the Watch. Validation lives in `WatchFleetStore.addMiner`; this view only surfaces its result.
struct AddMinerView: View {
    let store: WatchFleetStore

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var address = ""
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Name") {
                TextField("Name", text: $name)
                    .accessibilityIdentifier("watch.add.name")
            }

            Section {
                TextField("192.168.1.50", text: $address)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("watch.add.address")
            } header: {
                Text("Local address")
            } footer: {
                Text("Use the miner's Wi-Fi address on your home network. Only local addresses work.")
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(Color.hashCaution)
                        .accessibilityIdentifier("watch.add.error")
                }
            }

            Section {
                Button("Add miner", systemImage: "plus.circle.fill", action: save)
                    .disabled(trimmedAddress.isEmpty)
                    .accessibilityIdentifier("watch.add.save")
            }
        }
        .navigationTitle("Add miner")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var trimmedAddress: String {
        address.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmedName.isEmpty ? trimmedAddress : trimmedName
        do {
            try store.addMiner(name: finalName, address: trimmedAddress)
            errorMessage = nil
            dismiss()
            Task { await store.refresh() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
