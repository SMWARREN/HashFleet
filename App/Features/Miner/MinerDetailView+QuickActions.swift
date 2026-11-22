import Accessibility
import Observation
import SwiftUI
import HashFleetCore

enum MinerDetailQuickAction: String, CaseIterable {
    case identify, pause, resume, restart

    var endpoint: MinerEndpoint {
        switch self {
        case .identify: .identify
        case .pause: .pause
        case .resume: .resume
        case .restart: .restart
        }
    }

    var symbol: String {
        switch self {
        case .identify: "light.beacon.max"
        case .pause: "pause"
        case .resume: "play"
        case .restart: "arrow.clockwise"
        }
    }

    var identifier: String { "detail.quick.\(rawValue)" }

    var previewResult: String {
        switch self {
        case .identify: "Device signal simulated. Nothing sent."
        case .pause: "Mining paused in demo. Nothing sent."
        case .resume: "Mining resumed in demo. Nothing sent."
        case .restart: "Restart simulated. Nothing sent."
        }
    }
}

struct MinerQuickActionPreviewResult: View {
    let action: MinerDetailQuickAction

    var body: some View {
        Label {
            Text(action.previewResult).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "checkmark.circle.fill").accessibilityHidden(true)
        }
        .fleetFont(.footnote)
        .foregroundStyle(FleetTheme.positive)
    }

    static func announce(_ action: MinerDetailQuickAction) {
        AccessibilityNotification.Announcement(action.previewResult).post()
    }
}

@MainActor @Observable
final class MinerInlineActionState {
    struct Identity: Equatable {
        let mac: String
        let firmware: String
    }

    private(set) var isSending = false
    private(set) var receipt: String?
    private(set) var succeeded = false
    private(set) var unsupported: Set<MinerDetailQuickAction> = []
    private(set) var latestAction: MinerDetailQuickAction?
    var showsError = false
    private static var inFlight: Set<UUID> = []

    nonisolated static func identity(from info: MinerInfo) -> Identity? {
        guard let rawMAC = info.raw["macAddr"]?.stringValue ?? info.raw["mac"]?.stringValue,
              let firmware = info.raw["version"]?.stringValue, !firmware.isEmpty else { return nil }
        let mac = rawMAC.lowercased().filter { $0 != ":" && $0 != "-" }
        guard mac.utf8.count == 12, mac.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              mac != "000000000000", mac != "ffffffffffff" else { return nil }
        return .init(mac: mac, firmware: firmware)
    }

    func send(_ action: MinerDetailQuickAction, device: MinerDevice, store: FleetStore) async {
        guard !isSending, !unsupported.contains(action), Self.inFlight.insert(device.id).inserted else { return }
        defer {
            Self.inFlight.remove(device.id)
            isSending = false
            if let receipt {
                showsError = !succeeded
                AccessibilityNotification.Announcement(receipt).post()
            }
        }
        latestAction = action
        succeeded = false
        func currentIdentity() -> Identity? {
            let snapshot = store.snapshot(for: device.id)
            guard NumberFirstPreview.usesLivePhoneLayouts,
                  store.preferences.dashboardMode == .essentials, device.kind != .xmrig,
                  MinerWriteAvailability.allows(snapshot, device: device, currentDevices: store.devices, isDemo: store.isDemo),
                  let info = snapshot?.info else { return nil }
            return Self.identity(from: info)
        }
        guard let identity = currentIdentity() else {
            receipt = "Current miner identity or connection is unavailable. Nothing sent."
            return
        }

        isSending = true
        receipt = "Sending \(action.endpoint.title.lowercased())…"
        let client = MinerAPIClient(device: device, session: store.session)
        var attemptingCommand = false
        do {
            let preflight = try await client.info()
            try Task.checkCancellation()
            guard currentIdentity() == identity, Self.identity(from: preflight) == identity else {
                receipt = "The miner connection or identity changed. Nothing sent."
                return
            }
            attemptingCommand = true
            _ = try await client.execute(action.endpoint)
            receipt = "\(action.endpoint.title): miner accepted the request."
            succeeded = true
        } catch let MinerAPIError.http(status, _, _) where attemptingCommand && MinerCapabilityProbe.isUnsupportedStatus(status) {
            unsupported.insert(action)
            receipt = "This firmware did not accept \(action.endpoint.title.lowercased()) (HTTP \(status))."
        } catch {
            receipt = attemptingCommand
                ? "No confirmed result. Check the miner before trying again."
                : "Could not verify the miner connection. Nothing sent."
        }
    }
}

struct MinerInlineActionFeedback: View {
    var state: MinerInlineActionState

    var body: some View {
        if let receipt = state.receipt {
            Label(receipt, systemImage: state.isSending ? "clock" :
                (state.succeeded ? "checkmark.circle.fill" : "exclamationmark.circle"))
                .fixedSize(horizontal: false, vertical: true)
                .fleetFont(.footnote)
                .foregroundStyle(state.isSending ? FleetTheme.secondary : (state.succeeded ? FleetTheme.positive : FleetTheme.warning))
        }
    }
}

extension MinerDetailView {
    func toolRow(_ title: String, subtitle: String, symbol: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .fleetFont(.title3)
                .foregroundStyle(FleetTheme.accent)
                .frame(width: detailIconColumnWidth)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).fleetFont(.headline).foregroundStyle(FleetTheme.ink)
                Text(subtitle).fleetFont(.caption).foregroundStyle(FleetTheme.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").fleetFont(.caption, weight: .bold).foregroundStyle(FleetTheme.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 44, maxHeight: .infinity, alignment: .leading)
        .fleetCard(padding: FleetSurfaceSpacing.cardInset)
        .contentShape(Rectangle())
    }

    func quickAction(_ action: MinerDetailQuickAction, compact: Bool = false) -> some View {
        quickActionControl(action.endpoint, symbol: action.symbol, compact: compact)
            .accessibilityIdentifier(action.identifier)
            .accessibilityHint("Opens a review form. No command is sent until you confirm it.")
    }

    func previewQuickAction(_ action: MinerDetailQuickAction) -> some View {
        let active = !store.isDemo && liveQuickAction.latestAction == action ? liveQuickAction : nil
        let unsupported = !store.isDemo && liveQuickAction.unsupported.contains(action)
        return Button {
            guard usesNumberFirstDetail, dashboardMode == .essentials,
                  let info, NumberFirstPreview.minerAvailability(info, device: device, store: store)
                    .quickActions.contains(action) else { return }
            if store.isDemo {
                previewQuickActionResult = action
                MinerQuickActionPreviewResult.announce(action)
            } else {
                Task { await liveQuickAction.send(action, device: device, store: store) }
            }
        } label: {
            quickActionLabel(action.endpoint, symbol: action.symbol, compact: true, feedback: active)
        }
        .buttonStyle(.plain)
        .disabled(unsupported || (!store.isDemo && liveQuickAction.isSending))
        .accessibilityIdentifier(action.identifier)
        .accessibilityValue(active?.receipt ?? (unsupported ? "Unavailable on this firmware" : ""))
        .accessibilityHint(store.isDemo ? "Simulates this action without contacting a miner."
            : "Sends the command directly to this miner, if its firmware accepts it.")
    }

    @ViewBuilder
    private func quickActionControl(_ endpoint: MinerEndpoint, symbol: String, compact: Bool) -> some View {
        #if os(macOS)
        NavigationLink(value: endpoint) {
            quickActionLabel(endpoint, symbol: symbol, compact: compact)
        }
        .buttonStyle(.plain)
        #else
        // Compact miner cards push an inline destination. Start the next push from
        // this screen's state instead of looking up a value route from inside that destination.
        if usesCompactHorizontalLayout {
            Button { compactEndpointRoute = endpoint } label: {
                quickActionLabel(endpoint, symbol: symbol, compact: compact)
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(value: endpoint) {
                quickActionLabel(endpoint, symbol: symbol, compact: compact)
            }
        }
        #endif
    }

    @ViewBuilder
    private func quickActionLabel(_ endpoint: MinerEndpoint, symbol: String, compact: Bool,
                                  feedback: MinerInlineActionState? = nil) -> some View {
        if compact {
            Label {
                Text(endpoint.title).fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: symbol)
                    .foregroundStyle(FleetTheme.accent)
                    .opacity(feedback == nil ? 1 : 0)
                    .overlay {
                        if let feedback {
                            if feedback.isSending {
                                ProgressView().controlSize(.mini)
                            } else {
                                Image(systemName: feedback.succeeded ? "checkmark" : "exclamationmark.circle")
                                    .foregroundStyle(feedback.succeeded ? FleetTheme.positive : FleetTheme.warning)
                            }
                        }
                    }
                    .accessibilityHidden(true)
            }
            .fleetFont(.subheadline, weight: .medium)
            .foregroundStyle(FleetTheme.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(FleetTheme.raised, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        } else {
            VStack(spacing: 8) {
                Image(systemName: symbol).fleetFont(.title3).accessibilityHidden(true)
                Text(endpoint.title)
                    .fleetFont(.caption2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(FleetTheme.accent)
            .frame(maxWidth: .infinity, minHeight: 54, maxHeight: .infinity)
            .fleetCard(padding: FleetSurfaceSpacing.cardInset)
            .contentShape(Rectangle())
        }
    }
}
