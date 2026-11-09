import SwiftUI
import HashFleetCore

/// Demo mode presentation on the dashboard: simulated readings notice banner and sample pool icon gallery.
extension DashboardView {
    internal var demoNotice: some View {
        let layout =
            dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        return layout {
            Label(
                store.isPoolIconDemo ? "Pool icon demo · mock data" : "Demo · simulated readings",
                systemImage: "sparkles"
            )
            .fleetFont(.caption, weight: .semibold)
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Exit demo", action: store.clearDemo)
                .fleetFont(.caption, weight: .semibold)
                .frame(minHeight: 44)
                .accessibilityIdentifier("dashboard.exitDemo")
        }
        .foregroundStyle(FleetTheme.accent)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    internal var poolIconDemoGallery: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Explore every pool and coin")
                .fleetFont(.title2, weight: .bold)
                .accessibilityAddTraits(.isHeader)
            Text(
                "\(SoloPoolPreset.allCases.count) sample miners, one per pool. Tap any miner to explore its pool. " +
                    "These are in-app icons, not Home Screen icons."
            )
            .fleetFont(.subheadline)
            .foregroundStyle(FleetTheme.secondary)
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 280 : 145), spacing: 10)],
                spacing: 10
            ) {
                ForEach(Array(store.visibleDevices.enumerated()), id: \.element.id) { index, device in
                    let context = MinerMiningContext.resolve(info: store.snapshots[device.id]?.info)
                    NavigationLink {
                        MinerDetailView(device: device, store: store, insights: insights)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                CoinGeckoIcon(coin: context.pool?.coin, fallbackTicker: context.coinLabel, size: 34)
                                Text(context.coinLabel).fleetFont(.headline)
                            }
                            Text(context.providerLabel).fleetFont(.subheadline, weight: .semibold)
                            Text(device.name).fleetFont(.caption).foregroundStyle(FleetTheme.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
                        .padding(FleetSurfaceSpacing.cardInset)
                        .background(FleetTheme.raised, in: RoundedRectangle(cornerRadius: 14))
                        .contentShape(Rectangle())
                        .fleetMinerTransitionSource(
                            id: device.id,
                            in: minerTransitionNamespace,
                            enabled: !reduceMotion
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(device.name), \(context.headline), mock miner")
                    .accessibilityHint("Open and change this miner's simulated pool")
                    .accessibilityIdentifier("demo.pool.miner.\(index)")
                    .fleetStaggeredEntrance(index: index, reduceMotion: reduceMotion)
                }
            }
            Text("These are sample readings only. Your real miners keep their existing settings.")
                .fleetFont(.caption)
                .foregroundStyle(FleetTheme.secondary)
        }
        .accessibilityIdentifier("demo.pool.gallery")
    }
}
