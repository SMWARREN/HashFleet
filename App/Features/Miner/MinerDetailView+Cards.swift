import SwiftUI
import HashFleetCore

/// Hero and secondary cards of the miner detail screen. Moved out of MinerDetailView.swift
/// for file/type length; identifiers, wording and behavior are unchanged.
extension MinerDetailView {
    var poolIconDemoControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Mock miner · no hardware changes", systemImage: "sparkles")
                .fleetFont(.caption, weight: .semibold)
            Menu {
                ForEach(Array(SoloPoolPreset.allCases.enumerated()), id: \.element.id) { slot, preset in
                    Button(preset.title) { store.previewPool(slot: slot, for: device.id) }
                        .accessibilityIdentifier("demo.pool.select.\(slot)")
                }
            } label: {
                Label("Change mock pool", systemImage: "arrow.triangle.2.circlepath")
                    .fleetFont(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier("demo.pool.change")
            Text("The coin icon and pool name update instantly. All configured pools are shown below.")
                .fleetFont(.caption)
                .foregroundStyle(FleetTheme.secondary)
        }
        .foregroundStyle(FleetTheme.accent)
        .fleetCard(padding: FleetSurfaceSpacing.cardInset)
    }

    func firmwareUpdateSection(_ notice: FirmwareUpdateNotice) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            firmwareUpdateHeader(notice)
            if let latest = notice.latestVersion {
                Text("Installed \(notice.currentVersion) · Newest \(latest)")
                    .fleetFont(.caption, design: .monospaced)
                    .foregroundStyle(FleetTheme.ink)
                    .lineLimit(2)
            }
            Text("Official ESP-Miner releases from the bitaxeorg GitHub repository")
                .fleetFont(.caption)
                .foregroundStyle(FleetTheme.secondary)
            ForEach(notice.releases.prefix(5)) { release in
                firmwareReleaseRow(release)
            }
            Text("Checked \(notice.checkedAt.formatted(date: .abbreviated, time: .shortened)) · "
                + "updates are checked every 24 hours · dismissed releases return when newer firmware is available")
                .fleetFont(.caption2)
                .foregroundStyle(FleetTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fleetCard(padding: FleetSurfaceSpacing.cardInset, fill: FleetTheme.accent.opacity(0.10))
        .accessibilityIdentifier("detail.firmwareUpdates")
    }

    func firmwareUpdateHeader(_ notice: FirmwareUpdateNotice) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Label("Firmware updates", systemImage: "arrow.down.circle.fill")
                .fleetFont(.subheadline, weight: .semibold)
                .foregroundStyle(FleetTheme.accent)
            Spacer(minLength: 8)
            if let latestVersion = notice.latestVersion {
                Button("Dismiss firmware update", systemImage: "xmark") {
                    store.firmwareUpdates.dismiss(deviceID: device.id, releaseVersion: latestVersion)
                }
                .labelStyle(.iconOnly)
                .fleetFont(.caption, weight: .bold)
                .frame(width: 44, height: 44)
                .accessibilityLabel("Dismiss firmware update")
                .accessibilityHint("This notice will return when a newer release is available.")
                .accessibilityIdentifier("detail.firmwareUpdates.dismiss")
            }
        }
    }

    @ViewBuilder
    func firmwareReleaseRow(_ release: FirmwareRelease) -> some View {
        if let url = release.url {
            Link(destination: url) {
                HStack(spacing: 8) {
                    Text(release.version)
                        .fleetFont(.caption, weight: .semibold, design: .monospaced)
                    Spacer(minLength: 8)
                    Text("View release")
                        .fleetFont(.caption2, weight: .semibold)
                    Image(systemName: "arrow.up.right")
                        .fleetFont(.caption2, weight: .semibold)
                        .accessibilityHidden(true)
                }
                .foregroundStyle(FleetTheme.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier("detail.firmwareRelease.\(release.version)")
        }
    }

    func hashrateHero(_ info: MinerInfo) -> some View {
        // A field the firmware never sent is not a zero reading. `MinerInfo`'s conveniences fall back
        // to 0, so read the raw keys here and show "Not reported" when they are absent.
        let hashrate = FleetFormat.sensor(info, keys: "hashRate", "hashrate")
        return VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 5) {
                hashrateHeroHeading(info)
                hashrateHeroModelRow(info)
            }
            .foregroundStyle(FleetTheme.hashrateSecondary)
            hashrateHeroValue(hashrate)
            Rectangle()
                .fill(FleetTheme.hashrateInk.opacity(0.14))
                .frame(height: 1)
                .accessibilityHidden(true)
            sharesSummary(info)
            sampleAge
                .fleetFont(.caption2)
                .foregroundStyle(FleetTheme.hashrateSecondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .fleetCard(padding: 16, fill: FleetTheme.hashrateSurface, border: .clear)
    }

    func hashrateHeroHeading(_ info: MinerInfo) -> some View {
        let poolContext = MinerMiningContext.resolve(info: info)
        let poolTitle = poolContext.pool == nil ? "POOL NOT REPORTED" : poolContext.providerLabel.uppercased()
        let readingTitle = store.isDemo
            ? "SAMPLE HASHRATE"
            : (snapshot?.error != nil
                ? "LAST KNOWN HASHRATE"
                : (isLive ? "LIVE HASHRATE" : "LATEST HASHRATE"))
        return HStack(alignment: .center, spacing: 7) {
            Label(readingTitle, systemImage: "waveform.path")
                .fleetFont(.caption2, weight: .medium, design: .monospaced)
                .foregroundStyle(FleetTheme.hashrateAccent)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 6)
            HStack(alignment: .center, spacing: 5) {
                Text(poolTitle)
                    .fleetFont(.caption2, weight: .medium, design: .monospaced)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if let coin = poolContext.pool?.coin {
                    CoinGeckoIcon(coin: coin, fallbackTicker: miningMarket?.ticker ?? coin.ticker, size: 18)
                        .frame(width: 18, height: 18)
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityIdentifier("detail.poolContext")
    }

    func hashrateHeroModelRow(_ info: MinerInfo) -> some View {
        let chipText = isXMRig ? "XMRIG CPU" : MinerCapabilityPresentation.asicDescriptor(info: info)
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(chipText ?? "ASIC NOT REPORTED")
                .fleetFont(.caption2, weight: .medium, design: .monospaced)
                .lineLimit(1)
            Text("·")
                .fleetFont(.caption2, weight: .medium, design: .monospaced)
            MinerUptimeLabel(
                reportedSeconds: info.raw["uptimeSeconds"]?.intValue,
                observedAt: snapshot?.updatedAt,
                identifier: "detail.uptime",
                color: FleetTheme.hashrateSecondary
            )
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }

    func hashrateHeroValue(_ hashrate: Double?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            let value = hashrate.map { FleetFormat.hashrate($0) } ?? "Not reported"
            Text(value)
                .fleetDisplayFont(weight: .medium)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .fleetHeadlineNumericUpdate(value, reduceMotion: reduceMotion)
            if let hashrate {
                Text(FleetFormat.hashrateUnit(hashrate))
                    .fleetFont(.subheadline)
                    .foregroundStyle(FleetTheme.hashrateSecondary)
            }
        }
        .foregroundStyle(FleetTheme.hashrateInk)
    }

    func sharesSummary(_ info: MinerInfo) -> some View {
        let summary = MinerShareSummary(info: info)
        // The proposal puts the share counters on one row so the control card stays in the first
        // viewport. Accessibility sizes keep the single-column stack.
        let columns = Array(repeating: GridItem(.flexible(), alignment: .leading),
                            count: dynamicTypeSize.isAccessibilitySize ? 1 : min(summary.metrics.count, 3))
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            ForEach(summary.metrics) { metric in
                VStack(alignment: .leading, spacing: 3) {
                    Text(metric.title)
                        .fleetFont(.caption2)
                        .foregroundStyle(FleetTheme.hashrateSecondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                        .minimumScaleFactor(0.7)
                    Text(metric.value)
                        .fleetFont(.caption, weight: .semibold, design: .monospaced)
                        .foregroundStyle(FleetTheme.hashrateInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .minimumScaleFactor(0.7)
                        .fleetNumericUpdate(metric.value, reduceMotion: reduceMotion)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(metric.title), \(metric.value)")
                .accessibilityIdentifier("detail.shares.\(metric.id)")
                .fleetShareRise(metric.id == "accepted" ? summary.sharesAccepted : nil)
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// Best shares belong beside the latest reading, where a miner owner can compare this
    /// session with the miner's reported all-time record without opening Diagnostics.
    /// These are difficulty shares, not proof that this miner found a block.
    func bestShares(_ info: MinerInfo) -> some View {
        let best = MiningDifficultyFormat.short(info.raw["bestDiff"])
        let bestValue = MiningDifficultyFormat.parse(info.raw["bestDiff"])
        let session = MiningDifficultyFormat.short(info.raw["bestSessionDiff"])
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label("BEST SHARES", systemImage: "trophy.fill")
                    .fleetFont(.caption2, weight: .medium, design: .monospaced)
                    .foregroundStyle(FleetTheme.accent)
                Spacer(minLength: 8)
                Text("Reported by miner")
                    .fleetFont(.caption2)
                    .foregroundStyle(FleetTheme.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    bestShareMetric(title: "Best", value: best, id: "detail.bestShare.ever")
                        .fleetRecordShine(bestValue)
                    Divider().frame(height: 34).overlay(FleetTheme.separator)
                    bestShareMetric(title: "Best this session", value: session, id: "detail.bestShare.session")
                }
                VStack(alignment: .leading, spacing: 10) {
                    bestShareMetric(title: "Best", value: best, id: "detail.bestShare.ever")
                        .fleetRecordShine(bestValue)
                    bestShareMetric(title: "Best this session", value: session, id: "detail.bestShare.session")
                }
            }
            Text("A higher difficulty share is a stronger share, not a mined block.")
                .fleetFont(.caption2)
                .foregroundStyle(FleetTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .fleetCard(padding: FleetSurfaceSpacing.cardInset, border: FleetTheme.comparisonBorder.opacity(0.25), borderWidth: 0.5)
        .accessibilityElement(children: .contain)
    }

    func bestShareMetric(title: String, value: String?, id: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .fleetFont(.caption)
                .foregroundStyle(FleetTheme.secondary)
                .lineLimit(1)
            let displayValue = value ?? "Not reported"
            Text(displayValue)
                .fleetFont(.title2, weight: .bold, design: .rounded)
                .foregroundStyle(FleetTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .fleetNumericUpdate(displayValue, reduceMotion: reduceMotion)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
        .accessibilityLabel("\(title), \(value ?? "not reported")")
    }

    var sampleAge: some View {
        HStack(spacing: 3) {
            if store.isDemo, let updated = snapshot?.updatedAt {
                Text("Sampled")
                Text(updated, style: .relative)
                Text("ago")
            } else if isLive, snapshot?.info != nil, snapshot?.error == nil {
                Text("Live now")
            } else if let updated = snapshot?.updatedAt {
                Text("Updated")
                Text(updated, style: .relative)
                Text("ago")
            } else {
                Text("No reading recorded yet")
            }
        }
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(sampleAgeAccessibilityLabel)
        .accessibilityIdentifier("detail.sampleAge")
    }

    var sampleAgeAccessibilityLabel: String {
        if store.isDemo, snapshot?.updatedAt != nil { return "Sampled reading" }
        if isLive, snapshot?.info != nil, snapshot?.error == nil { return "Live now" }
        if snapshot?.updatedAt != nil { return "Updated reading" }
        return "No reading recorded yet"
    }
}
