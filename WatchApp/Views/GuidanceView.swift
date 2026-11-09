import SwiftUI

/// Explains connection loss in plain language. Shown when the Watch could not read one or more miners.
struct ConnectionGuidanceView: View {
    enum Scope {
        case all
        case some
        case single
    }

    var scope: Scope

    private var title: String {
        switch scope {
        case .all: "No miners reachable"
        case .some: "Some miners unreachable"
        case .single: "Can't reach this miner"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: "wifi.exclamationmark")
                .font(.headline)
                .foregroundStyle(Color.hashCaution)
            Text("Connect the Watch to the same Wi-Fi as your miners. Your iPhone can be off. Away from that network, the last readings stay saved with their real time. Unreachable doesn't mean a miner is offline.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("watch.help")
    }
}
