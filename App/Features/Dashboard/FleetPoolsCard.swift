import SwiftUI
import HashFleetCore

struct FleetPoolsCard: View {
    let fleet: FleetStore
    /// When set, this card shows and queries only that miner's configured pools. Used by the miner
    /// workspace so opening one miner never resolves or looks up another miner's payout address.
    let deviceID: UUID?
    let marketData: [MiningPoolCoin: CoinGeckoMarket]
    @State var store = ConnectedPoolsStore()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private struct MinerPoolSlot: Identifiable {
        let id: String
        let minerName: String
        let pool: ConfiguredMiningPool
    }

    init(fleet: FleetStore, deviceID: UUID? = nil, marketData: [MiningPoolCoin: CoinGeckoMarket] = [:]) {
        self.fleet = fleet
        self.deviceID = deviceID
        self.marketData = marketData
    }

    /// A scoped card sits inside one miner's screen, where repeating that miner's name on every row
    /// and titling the card "connected pools" fleet-wide would both be wrong.
    private var isScoped: Bool { deviceID != nil }

    private var slots: [MinerPoolSlot] {
        var results: [MinerPoolSlot] = []
        for device in fleet.devices {
            guard deviceID == nil || device.id == deviceID else { continue }
            guard let snapshot = fleet.snapshots[device.id],
                snapshot.error == nil,
                let info = snapshot.info, let date = snapshot.updatedAt,
                fleet.isDemo || (-60...300).contains(Date().timeIntervalSince(date))
            else { continue }
            let pools = ConfiguredMiningPool.resolve(info: info)
            for pool in pools {
                results.append(
                    MinerPoolSlot(
                        id: "\(device.id.uuidString)-\(pool.id)",
                        minerName: device.name,
                        pool: pool
                    )
                )
            }
        }
        return results
    }

    var body: some View {
        let poolSlots = slots
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(isScoped ? "POOL STATUS" : "CONNECTED POOLS", systemImage: "server.rack")
                    .font(FleetTheme.mono())
                    .foregroundStyle(FleetTheme.accent)
                Spacer()
                coverageBadge(count: poolSlots.count)
            }

            if poolSlots.isEmpty {
                Text(
                    isScoped
                        ? "This miner has not reported a configured mining pool in its latest reading."
                        : "No configured mining pools reported by online miners."
                )
                .fleetFont(.footnote)
                .foregroundStyle(FleetTheme.secondary)
            } else {
                VStack(spacing: 12) {
                    ForEach(poolSlots) { item in
                        slotRow(item)
                    }
                }
            }

        }
        .fleetCard(padding: 16)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(isScoped ? "minerPools.card" : "fleetPools.card")
        .task(
            id: LoadIdentity(
                entries: Set(ConnectedPoolsStore.configuredPools(fleet: fleet, deviceID: deviceID)),
                enabled: fleet.preferences.externalDataEnabled,
                demo: fleet.isDemo,
                phase: scenePhase,
                scope: deviceID
            )
        ) {
            guard scenePhase == .active, fleet.preferences.externalDataEnabled else { store.clear(); return }
            while !Task.isCancelled {
                await store.refresh(fleet: fleet, deviceID: deviceID)
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
            }
        }
        .onDisappear { store.clear() }

    }

    private struct LoadIdentity: Equatable {
        let entries: Set<ConfiguredMiningPool>
        let enabled: Bool
        let demo: Bool
        let phase: ScenePhase
        let scope: UUID?
    }

    // MARK: - Slot Row

    private func slotRow(_ item: MinerPoolSlot) -> some View {
        let pool = item.pool
        return VStack(alignment: .leading, spacing: 8) {
            slotHeader(pool)
            if !isScoped {
                Text(item.minerName).fleetFont(.caption2).foregroundStyle(FleetTheme.secondary)
            }
            BrowserLink(
                label: pool.host,
                rawValue: pool.host,
                identifier: "minerPools.host.\(pool.id)",
                font: FleetTheme.mono(11),
                alignment: .trailing
            )
            .frame(maxWidth: .infinity, alignment: .trailing)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)

            if let redacted = pool.redactedAddress {
                payoutRow(redacted)
            }

            // Public Adapter Details
            if let provider = pool.provider {
                statsDisclosure(provider: provider, coin: pool.coin, address: pool.address, host: pool.host)
            } else {
                Text(
                    "No public statistics adapter for this host. Miner settings and manual controls remain separate."
                )
                .fleetFont(.caption2)
                .foregroundStyle(FleetTheme.secondary)
            }
        }
        .padding(10)
        .background(FleetTheme.canvas.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private func slotHeader(_ pool: ConfiguredMiningPool) -> some View {
        let headerLayout =
            dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
        return headerLayout {
            Text(pool.role)
                .fleetFont(.subheadline, weight: .bold)
                .foregroundStyle(FleetTheme.ink)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("minerPools.role.\(pool.id)")
            HStack(spacing: 6) {
                Group {
                    if let active = pool.isActive {
                        activeBadge(active)
                    } else {
                        Text("Activity unknown").fleetFont(.caption2).foregroundStyle(FleetTheme.secondary)
                    }
                }
                .frame(width: dynamicTypeSize.isAccessibilitySize ? nil : 68, alignment: .leading)
                .accessibilityIdentifier("minerPools.activity.\(pool.id)")
                if let coin = pool.coin {
                    coinBadge(coin)
                        .frame(minWidth: 32, alignment: .leading)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func payoutRow(_ redacted: String) -> some View {
        HStack(spacing: 6) {
            Text("Payout:")
                .fleetFont(.caption2)
                .foregroundStyle(FleetTheme.secondary)
            Text(redacted)
                .font(FleetTheme.mono(11))
                .foregroundStyle(FleetTheme.ink)
                .privacySensitive()
        }
    }
}
