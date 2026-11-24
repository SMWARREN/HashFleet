import SwiftUI

/// Local Wi-Fi discovery results and empty states for AddMinerView.
extension AddMinerView {
    @ViewBuilder
    var discoveryContent: some View {
        switch discovery.state {
        case .idle:
            EmptyView()
        case .scanning:
            // Progress (radar, checked count, found count, Cancel) is one row in the scan card.
            // Below it, only the miners found so far, which can be added while scanning.
            if !discovery.candidates.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("You can add these while the scan continues.")
                        .fleetFont(.footnote)
                        .foregroundStyle(FleetTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    discoveryList(discovery.candidates)
                }
            }
        case .results:
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Compatible miners")
                        .fleetFont(.caption, weight: .semibold, design: .monospaced)
                        .foregroundStyle(FleetTheme.secondary)
                    Spacer(minLength: 8)
                    if !addedAddresses.isEmpty {
                        Text("\(addedAddresses.count) added")
                            .fleetFont(.caption, weight: .semibold, design: .monospaced)
                            .foregroundStyle(FleetTheme.positive)
                            .accessibilityIdentifier("addMiner.discoveryAddedCount")
                    }
                }
                Text("Add miners individually, or choose Add all to finish and return to Overview.")
                    .fleetFont(.footnote)
                    .foregroundStyle(FleetTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                addAllButton
                discoveryList(discovery.candidates)
            }
            .onAppear {
                #if os(iOS)
                    UIAccessibility.post(
                        notification: .announcement,
                        argument: "Found \(discovery.candidates.count) compatible \(discovery.candidates.count == 1 ? "miner" : "miners"). Tap each miner you want to add."
                    )
                #endif
            }
        case .noResults:
            discoveryEmptyState(
                title: "No compatible miners found",
                message: FleetDeviceCopy.current.discoveryEmptyMessage
            )
        case .unavailable(let message):
            discoveryEmptyState(
                title: "Wi-Fi scan unavailable",
                message:
                    message + "\n\nThings to check: Wi-Fi is on, no VPN is active, and " +
                    "\(FleetDeviceCopy.hostSettingsAppName) › Privacy & Security › Local Network allows Hash Fleet."
            )
        }
    }

    /// Adds every discovered miner in one step, skipping ones already in the fleet.
    var addAllButton: some View {
        let remaining = discovery.candidates.filter { !addedAddresses.contains($0.address) }.count
        return Button {
            if remaining == 0 && !addedAddresses.isEmpty {
                FleetHaptics.success()
                dismiss()
            } else if remaining > 0 {
                FleetHaptics.medium()
                addAllDiscovered()
            } else {
                FleetHaptics.warning()
            }
        } label: {
            Label(remaining == 0 ? "Done · Return to Overview" : "Add all (\(remaining))",
                  systemImage: remaining == 0 ? "checkmark.circle.fill" : "plus.circle.fill")
                .frame(maxWidth: .infinity, minHeight: 24)
        }
        .buttonStyle(FleetPrimaryButtonStyle(tone: remaining == 0 ? .secondary : .accent, size: .compact))
        .disabled(!localNetwork.isGranted || (remaining == 0 && addedAddresses.isEmpty))
        .accessibilityIdentifier("addMiner.addAll")
        .accessibilityHint("Adds every miner found without changing their settings.")
    }

    /// Rows for found miners, grouped by model once the scan has finished. During a scan the
    /// list is flat and ordered by address; later discoveries keep slotting into place.
    @ViewBuilder
    private func discoveryList(_ candidates: [MinerDiscoveryCandidate]) -> some View {
        let groups = MinerDiscoveryGrouping.groups(for: candidates)
        if groups.count <= 1 {
            ForEach(candidatesSorted(candidates), content: discoveryRow)
        } else {
            ForEach(Array(groups.enumerated()), id: \.element.title) { _, group in
                Text(group.title)
                    .fleetFont(.caption, weight: .semibold, design: .monospaced)
                    .foregroundStyle(FleetTheme.secondary)
                    .padding(.top, 6)
                    .accessibilityIdentifier("addMiner.discoveryGroup.\(group.title)")
                ForEach(group.candidates, content: discoveryRow)
            }
        }
    }

    private func candidatesSorted(_ candidates: [MinerDiscoveryCandidate]) -> [MinerDiscoveryCandidate] {
        MinerDiscoveryService.sorted(candidates)
    }

    @ViewBuilder
    private func discoveryRow(_ candidate: MinerDiscoveryCandidate) -> some View {
        let isAdded = addedAddresses.contains(candidate.address)
        Button {
            FleetHaptics.light()
            addMiner(candidate)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "cpu")
                    .font(.title3)
                    .foregroundStyle(isAdded ? FleetTheme.positive : FleetTheme.accent)
                    .frame(width: 28, height: 28)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(candidate.name)
                            .fleetFont(.subheadline, weight: .semibold)
                            .foregroundStyle(FleetTheme.ink)
                            .lineLimit(1)
                        if let fam = candidate.detectedFamily {
                            Text(fam)
                                .fleetFont(.caption2, weight: .medium, design: .monospaced)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(FleetTheme.accent.opacity(0.12), in: Capsule())
                                .foregroundStyle(FleetTheme.accent)
                        }
                    }
                    Text([candidate.model, candidate.address].compactMap { $0 }.joined(separator: " · "))
                        .fleetFont(.caption, design: .monospaced)
                        .foregroundStyle(FleetTheme.secondary)
                        .minimumScaleFactor(0.75)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: isAdded ? "checkmark.circle.fill" : "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(isAdded ? FleetTheme.positive : FleetTheme.accent)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(FleetTheme.surface, in: RoundedRectangle(cornerRadius: 10))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .disabled(isAdded || !localNetwork.isGranted)
        .accessibilityIdentifier("addMiner.discoveryResult.\(candidate.address)")
        .accessibilityValue(isAdded ? "Added" : "Not added")
        .accessibilityHint(
            isAdded
                ? "Already in your fleet."
                : "Adds this miner without changing its settings. The list stays open."
        )
    }

    func discoveryEmptyState(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: "wifi.exclamationmark")
                .fleetFont(.subheadline, weight: .semibold)
                .foregroundStyle(FleetTheme.warning)
            Text(message)
                .fleetFont(.footnote)
                .foregroundStyle(FleetTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 16) {
                Button("Try again", systemImage: "arrow.clockwise") {
                    startDiscovery()
                }
                .fleetFont(.footnote, weight: .semibold)
                .frame(minHeight: 44)
                .accessibilityIdentifier("addMiner.discoveryRetry")
                .disabled(!localNetwork.isGranted)
                #if os(iOS)
                    Button("Open Local Network Settings", systemImage: "gear") {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        UIApplication.shared.open(url)
                    }
                    .fleetFont(.footnote, weight: .semibold)
                    .frame(minHeight: 44)
                #endif
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("addMiner.discoveryEmpty")
    }
}
