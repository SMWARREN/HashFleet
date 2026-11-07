import SwiftUI

/// Compact status strip for the top of the compact dashboard.
///
/// The ticker continuously moves one repeated track containing every miner, with a pause control.
/// The repeated track travels completely offscreen before the identical copy takes its place, so
/// the line loops seamlessly instead of showing one miner and silently rotating the others away.
/// Reduce Motion, VoiceOver, and accessibility Dynamic Type sizes get a static, fully readable
/// presentation instead: every miner's full status is laid out at once with unrestricted wrapping,
/// and nothing animates. Pausing, backgrounding, or leaving the screen freezes the clock entirely.
/// All data comes from the fleet's most recent readings; the ticker performs no networking.
struct FleetStatusTicker: View {
    let fleet: FleetStore
    var viewport: CGRect?

    @State private var marqueeClock = FleetMarqueeClock()
    @State private var isPaused = false
    @State private var isVisible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase

    /// Pixels per second keeps long fleets readable while avoiding a second-by-second state update.
    static let marqueePixelsPerSecond: Double = 34
    /// Thirty updates per second are enough for a readable marquee while leaving display-cadence
    /// headroom for live telemetry updates, chart gestures, and scrolling.
    static let marqueeFramesPerSecond: Double = 30

    private var model: FleetStatusTickerModel {
        FleetStatusTickerModel(devices: fleet.visibleDevices, snapshots: fleet.snapshots, isDemo: fleet.isDemo)
    }

    /// Anything that makes a changing line unreadable gets the full static layout: Reduce Motion,
    /// VoiceOver, and accessibility Dynamic Type sizes, where one cycling line cannot hold all text.
    private var usesStaticLayout: Bool {
        reduceMotion || voiceOver || dynamicTypeSize.isAccessibilitySize
    }

    /// Live cycling only makes sense while the strip is visible and the scene is active.
    private var shouldCycle: Bool {
        !usesStaticLayout && !isPaused && scenePhase == .active && isVisible
    }

    var body: some View {
        let model = model
        if !model.items.isEmpty {
            content(for: model)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("fleet.ticker")
                .onChange(of: shouldCycle, initial: true) { _, running in
                    marqueeClock.setRunning(running, at: .now)
                }
                .onAppear { isVisible = true }
                .onDisappear { isVisible = false }
                .onGeometryChange(for: Bool.self) { geometry in
                    let frame = geometry.frame(in: .global)
                    guard let viewport else { return true }
                    return frame.intersects(viewport)
                } action: { visible in
                    isVisible = visible
                }
        }
    }

    @ViewBuilder
    private func content(for model: FleetStatusTickerModel) -> some View {
        if usesStaticLayout {
            staticLayout(model)
        } else {
            HStack(spacing: 0) {
                FleetMarqueeTrack(items: marqueeItems(for: model), clock: $marqueeClock, reduceMotion: reduceMotion)
                    .frame(maxWidth: .infinity)
                pauseButton
            }
        }
    }

    private var pauseButton: some View {
        Button {
            isPaused.toggle()
            marqueeClock.setRunning(shouldCycle, at: .now)
        } label: {
            Image(systemName: isPaused ? "play.fill" : "pause.fill")
                .fleetFont(.caption)
                .contentTransition(.symbolEffect(.replace))
                // 44pt minimum hit target.
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(FleetTheme.marqueeSecondary)
        .accessibilityLabel(isPaused ? "Resume status ticker" : "Pause status ticker")
        .accessibilityIdentifier("fleet.ticker.pause")
    }

    // MARK: - Static (Reduce Motion / VoiceOver / accessibility sizes)

    /// No ticker, no animation, no cadence. Every miner is readable at once, each row wraps as far
    /// as needed, and each carries its own complete accessibility label in fleet order.
    private func staticLayout(_ model: FleetStatusTickerModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(model.items) { item in
                row(for: item, wrapsFully: true)
            }
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Row

    /// One miner's compact line: status dot, name, reported segments, and any firmware notice.
    /// `wrapsFully` removes the line cap so large Dynamic Type never clips content.
    private func row(for item: FleetStatusTickerModel.Item, wrapsFully: Bool = false) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(dotColor(for: item))
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text(viewText(for: item))
                .fleetFont(.footnote)
                .foregroundStyle(item.isOnline ? FleetTheme.marqueeInk : FleetTheme.marqueeSecondary)
                .lineLimit(wrapsFully ? nil : 1)
                .fixedSize(horizontal: false, vertical: wrapsFully)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.summary)
        .accessibilityIdentifier("fleet.ticker.item.\(item.id)")
    }

    private func dotColor(for item: FleetStatusTickerModel.Item) -> Color {
        switch item.status {
        case .online: item.notices.isEmpty ? FleetTheme.positive : FleetTheme.warning
        case .offline: FleetTheme.separator
        case .connecting, .reconnecting: FleetTheme.marqueeSecondary
        }
    }

    private func viewText(for item: FleetStatusTickerModel.Item) -> String {
        var parts: [String] = []
        if item.isSimulated { parts.append("Simulated") }
        parts.append(item.name)
        switch item.status {
        case .connecting: parts.append("Connecting")
        case .reconnecting: parts.append("Reconnecting…")
        case .offline: parts.append("Offline")
        case .online: parts.append(contentsOf: item.segments)
        }
        parts.append(contentsOf: item.notices)
        return parts.joined(separator: " · ")
    }

    private func marqueeItems(for model: FleetStatusTickerModel) -> [FleetMarqueeItem] {
        model.items.map { item in
            FleetMarqueeItem(
                id: item.id,
                text: viewText(for: item),
                color: dotColor(for: item),
                isOnline: item.isOnline,
                summary: item.summary
            )
        }
    }
}

private struct FleetMarqueeItem: Identifiable {
    let id: UUID
    let text: String
    let color: Color
    let isOnline: Bool
    let summary: String
}

/// Geometry and phase math stay pure so the native UI can be tested without copying SwiftUI's
/// rendering machinery into a synthetic harness.
enum FleetMarqueeLayout {
    /// How the clock must be adjusted for a geometry change so the pixels under the viewport
    /// never jump.
    enum GeometryAdjustment: Equatable, Sendable {
        /// Showed offset 0 (first measurement, or the track just became scrollable after being
        /// pinned at the start); restart the clock so it still shows offset 0.
        case reset
        /// Track stayed scrollable but its measured width changed; rebase the clock so the same
        /// physical pixel stays under the viewport.
        case preserveOffset
        /// Nothing about the visible offset changed.
        case none
    }

    static func travelDistance(copyWidth: CGFloat, gap: CGFloat) -> CGFloat {
        max(0, copyWidth) + max(0, gap)
    }

    static func offset(elapsed: TimeInterval, copyWidth: CGFloat, gap: CGFloat, pixelsPerSecond: Double) -> CGFloat {
        let travel = travelDistance(copyWidth: copyWidth, gap: gap)
        guard travel > 0, pixelsPerSecond > 0, elapsed.isFinite, elapsed >= 0 else { return 0 }
        let duration = Double(travel) / pixelsPerSecond
        let phase = elapsed.truncatingRemainder(dividingBy: duration)
        return CGFloat(phase / duration) * travel
    }

    static func isScrollable(copyWidth: CGFloat, gap: CGFloat, viewportWidth: CGFloat) -> Bool {
        travelDistance(copyWidth: copyWidth, gap: gap) > max(0, viewportWidth) + 1
    }

    /// Decides the clock adjustment for a change in measured copy width or scrollability.
    /// A raw elapsed time only has meaning relative to a travel distance, so every transition
    /// that changes which travel distance applies must either rebase the clock (preserving the
    /// physical offset) or restart it (preserving offset 0). Otherwise the same elapsed value is
    /// reinterpreted against a new geometry and the text visibly jumps.
    static func adjustment(
        oldCopyWidth: CGFloat,
        newCopyWidth: CGFloat,
        wasScrollable: Bool,
        isScrollable: Bool
    ) -> GeometryAdjustment {
        guard newCopyWidth > 0 else { return .none }
        if oldCopyWidth <= 0 { return isScrollable ? .reset : .none }
        if isScrollable && !wasScrollable { return .reset }
        guard isScrollable else { return .none }
        return abs(newCopyWidth - oldCopyWidth) > 0 ? .preserveOffset : .none
    }
}

/// The first copy is exposed to accessibility; the second copy is visual-only. Measuring only the
/// first copy lets the second copy land exactly where the first began at the loop boundary.
private struct FleetMarqueeTrack: View {
    let items: [FleetMarqueeItem]
    @Binding var clock: FleetMarqueeClock
    let reduceMotion: Bool
    @State private var copyWidth: CGFloat = 0
    @State private var viewportWidth: CGFloat = 0
    @ScaledMetric(relativeTo: .footnote) private var lineHeight: CGFloat = 20

    private static let copyGap: CGFloat = 30
    private static let itemGap: CGFloat = 24

    var body: some View {
        GeometryReader { viewport in
            let canScroll = FleetMarqueeLayout.isScrollable(
                copyWidth: copyWidth,
                gap: Self.copyGap,
                viewportWidth: viewport.size.width
            )
            // Build the text outside the per-frame closure. Only translation needs a display tick,
            // not rebuilding both complete fleets of labels and their numeric transitions.
            let track = HStack(spacing: Self.copyGap) {
                copy(accessibilityHidden: false)
                    .background {
                        GeometryReader { copyGeometry in
                            Color.clear.preference(
                                key: FleetMarqueeWidthPreferenceKey.self,
                                value: copyGeometry.size.width
                            )
                        }
                    }
                copy(accessibilityHidden: true)
            }
            .fixedSize(horizontal: true, vertical: false)
            // The marquee is decorative. Cap its schedule instead of competing with live metric
            // updates at the device's full display cadence, while still suspending work when
            // paused or offscreen.
            TimelineView(.periodic(from: .now, by: 1 / FleetStatusTicker.marqueeFramesPerSecond)) { context in
                track
                    .offset(
                        x: canScroll
                            ? -FleetMarqueeLayout.offset(
                                elapsed: clock.elapsed(at: context.date),
                                copyWidth: copyWidth,
                                gap: Self.copyGap,
                                pixelsPerSecond: FleetStatusTicker.marqueePixelsPerSecond
                            ) : 0
                    )
                    // Translation is already time-based. An inherited ease/spring must not interpolate
                    // each new offset, repeatedly slowing it down. Child numeric animations opt back in.
                    .transaction { $0.animation = nil }
            }
        }
        .frame(height: lineHeight)
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fleet.ticker.marquee")
        .onPreferenceChange(FleetMarqueeWidthPreferenceKey.self) { width in
            guard width > 0, abs(width - copyWidth) > 0.5 else { return }
            applyGeometryChange(newCopyWidth: width, newViewportWidth: viewportWidth)
        }
        .onGeometryChange(for: CGFloat.self) { geometry in
            geometry.size.width
        } action: { newViewportWidth in
            applyGeometryChange(newCopyWidth: copyWidth, newViewportWidth: newViewportWidth)
        }
    }

    /// One funnel for both geometry sources (measured copy width and viewport width) so a change
    /// arriving from either direction is judged against the same before/after scrollability pair.
    private func applyGeometryChange(newCopyWidth: CGFloat, newViewportWidth: CGFloat) {
        // Sub-half-point text changes keep the previous width so the phase does not drift.
        let measuredWidth = (copyWidth > 0 && abs(newCopyWidth - copyWidth) <= 0.5) ? copyWidth : newCopyWidth
        let wasScrollable = FleetMarqueeLayout.isScrollable(
            copyWidth: copyWidth,
            gap: Self.copyGap,
            viewportWidth: viewportWidth
        )
        let nowScrollable = FleetMarqueeLayout.isScrollable(
            copyWidth: measuredWidth,
            gap: Self.copyGap,
            viewportWidth: newViewportWidth
        )
        switch FleetMarqueeLayout.adjustment(
            oldCopyWidth: copyWidth,
            newCopyWidth: measuredWidth,
            wasScrollable: wasScrollable,
            isScrollable: nowScrollable
        ) {
        case .reset:
            clock.reset(at: .now)
        case .preserveOffset:
            clock.preserveOffset(
                from: copyWidth,
                to: measuredWidth,
                gap: Self.copyGap,
                at: .now,
                pixelsPerSecond: FleetStatusTicker.marqueePixelsPerSecond
            )
        case .none:
            break
        }
        copyWidth = measuredWidth
        viewportWidth = newViewportWidth
    }

    private func copy(accessibilityHidden: Bool) -> some View {
        HStack(spacing: Self.itemGap) {
            ForEach(items) { item in
                if accessibilityHidden {
                    visualItem(item)
                } else {
                    accessibleItem(item)
                }
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityHidden(accessibilityHidden)
    }

    private func accessibleItem(_ item: FleetMarqueeItem) -> some View {
        itemContent(item)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(item.summary)
            .accessibilityIdentifier("fleet.ticker.item.\(item.id)")
    }

    private func visualItem(_ item: FleetMarqueeItem) -> some View {
        itemContent(item)
            .accessibilityHidden(true)
    }

    private func itemContent(_ item: FleetMarqueeItem) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(item.color)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text(item.text)
                .fleetFont(.footnote)
                .monospacedDigit()
                .fleetNumericUpdate(item.text, reduceMotion: reduceMotion)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: true)
        }
        .foregroundStyle(item.isOnline ? FleetTheme.marqueeInk : FleetTheme.marqueeSecondary)
    }
}

private struct FleetMarqueeWidthPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
