import HashFleetCore
import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Optional PayPal checkout and copy-only public crypto addresses. No payment SDK or wallet access.
struct DeveloperSupportSection: View {
    var showsUnavailableMessage = false
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    private let availability: DeveloperSupportAvailability
    @State private var isOpening = false
    @State private var showOpenError = false
    @State private var copyingDestination: DeveloperSupportCrypto?
    @State private var copiedDestination: DeveloperSupportCrypto?
    @State private var showCopyError = false

    init(showsUnavailableMessage: Bool = false, availability: DeveloperSupportAvailability = .init()) {
        self.showsUnavailableMessage = showsUnavailableMessage
        self.availability = availability
    }

    var body: some View {
        // A layout container here turns the native Section into one oversized List row.
        Group {
            if availability.checkoutURL != nil || !availability.cryptoDestinations.isEmpty {
                FleetSettingsSection(DeveloperSupport.title) {
                    FleetSettingsRow {
                        Text(DeveloperSupport.explanation)
                    }
                    if availability.checkoutURL != nil {
                        FleetSettingsRow {
                            Button("Leave an optional tip via PayPal", systemImage: "arrow.up.right.square") {
                                isOpening = true
                            }
                            .disabled(isOpening)
                            .accessibilityIdentifier("about.support.paypal")
                            .accessibilityHint("Opens an external checkout in your browser. No payment is made by tapping this button.")
                        }
                        FleetSettingsRow {
                            Text(DeveloperSupport.checkoutNotice)
                                .fleetFont(.footnote)
                                .foregroundStyle(FleetTheme.secondary)
                        }
                    }
                    if !availability.cryptoDestinations.isEmpty {
                        ForEach(availability.cryptoDestinations) { destination in
                            FleetSettingsRow {
                                cryptoRow(destination)
                            }
                        }
                        FleetSettingsRow(showsSeparator: false) {
                            Text(DeveloperSupport.cryptoNotice)
                                .fleetFont(.footnote)
                                .foregroundStyle(FleetTheme.secondary)
                        }
                    }
                }
                .fleetSettingsSectionIdentifier("about.support")
            } else if showsUnavailableMessage {
                FleetSettingsSection("Thank you for being here") {
                    FleetSettingsRow {
                        Text(DeveloperSupport.explanation)
                    }
                    FleetSettingsRow(showsSeparator: false) {
                        Text(availability.isResolved
                             ? "External tipping isn't available for your current storefront. You can still support Hash Fleet by sharing the app and reporting useful feedback."
                             : "Confirming your App Store region…")
                            .fleetFont(.footnote)
                            .foregroundStyle(FleetTheme.secondary)
                    }
                }
                .fleetSettingsSectionIdentifier("support.unavailable")
            }
        }
        .task(id: isOpening) {
            guard isOpening else { return }
            defer { isOpening = false }
            let url = await availability.revalidatedURL()
            guard !Task.isCancelled, scenePhase == .active, let url else { return }
            let accepted = await FleetExternalURL.open(url, using: openURL)
            guard !Task.isCancelled else { return }
            showOpenError = !accepted
        }
        .task(id: copyingDestination) {
            guard let requested = copyingDestination else { return }
            defer { copyingDestination = nil }
            let destination = await availability.revalidatedCryptoDestination(requested)
            guard !Task.isCancelled, scenePhase == .active, let destination else { return }
            copiedDestination = nil
#if os(macOS)
            NSPasteboard.general.clearContents()
            let copied = NSPasteboard.general.setString(destination.address, forType: .string)
#else
            UIPasteboard.general.setItems(
                [["public.utf8-plain-text": destination.address]],
                options: [.localOnly: true, .expirationDate: Date.now.addingTimeInterval(120)]
            )
            let copied = true
#endif
            if copied { copiedDestination = destination }
            showCopyError = !copied
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { copiedDestination = nil }
        }
        .onChange(of: availability.cryptoDestinations) { _, destinations in
            if destinations.isEmpty { copiedDestination = nil }
        }
        .alert("Couldn't open PayPal", isPresented: $showOpenError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Please try again later. No payment was made by Hash Fleet.")
        }
        .alert("Couldn't copy address", isPresented: $showCopyError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Please try again. No wallet was opened and no payment was made.")
        }
    }

    private func cryptoRow(_ destination: DeveloperSupportCrypto) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(destination.name) (\(destination.rawValue))")
                .fleetFont(.headline)
            Text(destination.network)
                .fleetFont(.footnote)
                .foregroundStyle(FleetTheme.secondary)
            // Explicit invisible break opportunities prevent typographic hyphens from
            // looking like part of an address. Clipboard and accessibility use the original.
            Text(verbatim: destination.address.map(String.init).joined(separator: "\u{200B}"))
                .fleetFont(.footnote)
                .monospaced()
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("\(destination.name) receiving address, \(destination.address)")
                .accessibilityIdentifier("about.support.crypto.\(destination.rawValue).address")
            Button {
                copiedDestination = nil
                copyingDestination = destination
            } label: {
                Label(
                    copiedDestination == destination ? "Copied \(destination.rawValue) address" : "Copy \(destination.rawValue) address",
                    systemImage: copiedDestination == destination ? "checkmark" : "doc.on.doc"
                )
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .disabled(copyingDestination != nil || scenePhase != .active)
            .accessibilityIdentifier("about.support.crypto.\(destination.rawValue).copy")
            .accessibilityHint("Copies the public \(destination.network) address only. Does not open a wallet or send funds.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}
