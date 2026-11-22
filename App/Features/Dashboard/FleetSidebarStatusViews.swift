import SwiftUI
#if os(macOS)
import AppKit
#endif
import HashFleetCore

/// A compact miner row designed for the Mac sidebar with status indicator, live hashrate, and temp.
struct MinerSidebarRow: View {
    let device: MinerDevice
    let snapshot: MinerSnapshot?
    let isDemo: Bool
    let isLive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var attention: MinerSidebarAttention? {
        MinerSidebarAttention.resolve(
            state: presentationState,
            temperature: snapshot?.info.flatMap { FleetFormat.sensor($0, keys: "temp") }
        )
    }

    private var presentationState: FleetMinerPresentationState {
        if snapshot?.info == nil, snapshot?.isReconnecting == true { return .loading }
        return FleetMinerPresentationState.resolve(
            isDemo: isDemo,
            hasInfo: snapshot?.info != nil,
            hasError: snapshot?.error != nil,
            isLive: isLive,
            isReconnecting: snapshot?.isReconnecting == true
        )
    }

    var body: some View {
        HStack(spacing: 8) {
            // Dot and halo share one fixed slot the width of the sidebar icon tiles, pinned to
            // the slot's leading edge so the halo lines up flush with the tiles above and below.
            ZStack {
                if presentationState.isOperational {
                    Circle()
                        .strokeBorder(presentationState.color.opacity(0.35), lineWidth: 2)
                }
                Circle()
                    .fill(presentationState.color)
                    .frame(width: 8, height: 8)
                    // One ripple when the miner goes offline or comes back (ShipSwift swPing idea,
                    // using the app's existing one-shot pulse). Never repeats while idle.
                    .fleetStatusTransitionPulse(
                        isOnline: presentationState.isOperational,
                        color: presentationState.color,
                        reduceMotion: reduceMotion
                    )
            }
            .frame(width: 14, height: 14)
            .frame(width: FleetLayout.sidebarIconWidth, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .fleetFont(.subheadline, weight: .medium)
                    .foregroundStyle(FleetTheme.ink)
                    .lineLimit(1)

                Text(device.address)
                    .fleetFont(.caption2)
                    .foregroundStyle(FleetTheme.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 2) {
                if let attention, attention == .offline {
                    FleetStatusPill(text: attention.text, systemImage: attention.systemImage, tint: FleetTheme.warning)
                        .accessibilityLabel(attention.accessibilityLabel)
                } else if let info = snapshot?.info {
                    Text(FleetFormat.sensor(info, keys: "hashRate", "hashrate")
                        .map { FleetFormat.hashrateWithUnit($0) } ?? "Not reported")
                        .fleetFont(.caption2, weight: .semibold, design: .monospaced)
                        .foregroundStyle(FleetTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    if let attention {
                        FleetStatusPill(text: attention.text, systemImage: attention.systemImage, tint: MinerSidebarAttention.hotTint)
                            .accessibilityLabel(attention.accessibilityLabel)
                    } else if let temp = FleetFormat.sensor(info, keys: "temp") {
                        // `sensor` only guarantees finite; garbage like 1e300 from firmware would trap Int().
                        Text("\(FleetFormat.number(temp))°C")
                            .fleetFont(.caption2, design: .monospaced)
                            .foregroundStyle(FleetTheme.secondary)
                    }
                } else {
                    Text("—")
                        .font(FleetTheme.mono(11))
                        .foregroundStyle(FleetTheme.secondary)
                }
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button {
                #if os(macOS)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(device.address, forType: .string)
                #else
                UIPasteboard.general.string = device.address
                #endif
            } label: {
                Label("Copy Address", systemImage: "doc.on.doc")
            }

            if let url = try? device.validatedURL() {
                Link(destination: url) {
                    Label("Open Web Interface", systemImage: "safari")
                }
            }
        }
    }
}

/// Persistent footer pinned at the bottom of the desktop sidebar showing live fleet vitals.
struct FleetSidebarFooter: View {
    let store: FleetStore
    var onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(store.onlineCount > 0 ? FleetTheme.positive : FleetTheme.warning)
                            .frame(width: 6, height: 6)
                        Text(store.isDemo ? "Demo Fleet" : "\(store.onlineCount)/\(store.visibleDevices.count) Online")
                            .fleetFont(.caption2, weight: .medium)
                            .foregroundStyle(FleetTheme.secondary)
                    }

                    if store.totalHashrate > 0 {
                        Text(FleetFormat.hashrateWithUnit(store.totalHashrate))
                            .font(FleetTheme.mono(12).weight(.bold))
                            .foregroundStyle(FleetTheme.ink)
                    }
                }

                Spacer()

                Button {
                    onRefresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .fleetFont(.caption, weight: .semibold)
                        .foregroundStyle(FleetTheme.ink)
                        .frame(width: 28, height: 28)
                        .background(FleetTheme.surface, in: Circle())
                }
                .buttonStyle(.plain)
                .help("Refresh fleet (⌘R)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            FleetTheme.surface
                .ignoresSafeArea(.container, edges: .bottom)
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(FleetTheme.separator)
                .frame(height: 1)
        }
        .shadow(color: Color.black.opacity(0.12), radius: 8, y: -2)
    }
}
