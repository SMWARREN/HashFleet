import SwiftUI
import HashFleetWatchCore
#if canImport(WatchKit)
import WatchKit
#endif

/// ShipSwift-styled setup inbox sheet for Apple Watch.
/// Transferred securely from the paired iPhone via WatchConnectivity.
struct WatchSetupInboxView: View {
    let transfer: WatchFleetSetupTransfer
    let store: WatchFleetStore
    let onFinished: () -> Void
    @State private var errorMessage: String?
    @State private var isImporting = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    // MARK: - ShipSwift Header Badge & Icon
                    VStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(Color.hashGold.opacity(0.15))
                                .frame(width: 44, height: 44)
                            Image(systemName: "applewatch.and.arrow.forward")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(Color.hashGold)
                        }

                        // ShipSwift Status Badge
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.hashGold)
                                .frame(width: 5, height: 5)
                            Text("\(transfer.miners.count) MINERS READY")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.hashGold)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color.hashGold.opacity(0.15))
                        )

                        Text("Import from iPhone")
                            .font(.system(.headline, design: .rounded))
                            .fontWeight(.bold)

                        Text("Direct local Wi-Fi reading on your wrist. Phone is optional after import.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 4)
                    }
                    .padding(.top, 4)

                    // MARK: - Miner Cards
                    VStack(spacing: 6) {
                        ForEach(transfer.miners) { miner in
                            HStack(spacing: 8) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(Color.hashGold.opacity(0.12))
                                        .frame(width: 28, height: 28)
                                    Image(systemName: "cpu")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(Color.hashGold)
                                }

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(miner.name)
                                        .font(.system(size: 12, weight: .semibold))
                                        .lineLimit(1)
                                    Text(miner.address)
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 4)

                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.hashGold.opacity(0.7))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.white.opacity(0.06))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                                    )
                            )
                            .privacySensitive()
                        }
                    }

                    // MARK: - Error Notice
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }

                    // MARK: - Actions
                    VStack(spacing: 8) {
                        Button {
                            do {
                                isImporting = true
                                #if canImport(WatchKit)
                                WKInterfaceDevice.current().play(.success)
                                #endif
                                _ = try store.importMiners(transfer.miners, updateExisting: true)
                                onFinished()
                            } catch {
                                isImporting = false
                                errorMessage = error.localizedDescription
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "square.and.arrow.down.fill")
                                    .font(.system(size: 13, weight: .bold))
                                Text(isImporting ? "Importing…" : "Import \(transfer.miners.count) Miners")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.hashGold)
                        .foregroundStyle(.black)
                        .accessibilityIdentifier("watch.setup.import")

                        Button("Not now", role: .cancel, action: onFinished)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("watch.setup.cancel")
                    }
                    .padding(.top, 4)

                    // MARK: - Trust & Privacy Footer
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.hashGold.opacity(0.8))
                        Text("Keeps existing miners · Read-only")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 8)
                }
                .padding(.horizontal, 6)
            }
            .navigationTitle("iPhone Setup")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled()
        }
    }
}
