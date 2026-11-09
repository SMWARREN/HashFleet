import SwiftUI

struct FleetOnboardingView: View {
    let addMiner: () -> Void
    let exploreDemo: () -> Void
    var forceReduceMotion = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The test-only override complements the user's read-only system accessibility setting.
    private var effectiveReduceMotion: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return reduceMotion || forceReduceMotion
            || (arguments.contains("--ui-testing") && arguments.contains("--ui-test-reduce-motion"))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 24) {
                BitsySays(
                    mood: .wave,
                    message: effectiveReduceMotion
                        ? "Hi, I'm Bitsy! I'll help you get your first miner set up."
                        : "Hi, I'm Bitsy! Tap me for a little hop.",
                    size: 112,
                    offersGreetingAction: !effectiveReduceMotion,
                    forceReduceMotion: effectiveReduceMotion
                )
                .accessibilityIdentifier("onboarding.bitsy")
                // Keep the three miners on the first screen with Bitsy. The old
                // 126-point art lived below this entire card, so most people
                // never saw the fans spin when they opened the app.
                FleetLoadAnimatedArt(
                    loop: .fleetCluster,
                    size: CGSize(width: 240, height: 142),
                    isEnabled: !effectiveReduceMotion,
                    accessibilityIdentifier: "onboarding.minerCluster"
                )
                .frame(maxWidth: .infinity)
                .fleetStaggeredEntrance(index: 1, reduceMotion: effectiveReduceMotion)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Your miners.\nOne clear view.")
                        .fleetFont(.largeTitle, weight: .bold)
                        .tracking(-1)
                        .foregroundStyle(FleetTheme.panelInk)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(
                        "Connect compatible open-source miners on your network. See hashrate and temperatures, then "
                            + "review each settings change before it is sent."
                    )
                    .fleetFont(.body)
                    .foregroundStyle(FleetTheme.panelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .fleetStaggeredEntrance(index: 2, reduceMotion: effectiveReduceMotion)
                Button(action: addMiner) { Label("Connect your first miner", systemImage: "plus") }
                    .buttonStyle(FleetPrimaryButtonStyle(onDarkSurface: true))
                    .accessibilityIdentifier("dashboard.connectFirstMiner")
                    .fleetStaggeredEntrance(index: 3, reduceMotion: effectiveReduceMotion)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fleetCard(padding: 26, fill: FleetTheme.charcoal)
            .overlay(alignment: .topTrailing) {
                Image("HashFleetAmbient")
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 250, height: 250)
                    .opacity(0.28)
                    .scaleEffect(0.98)
                    .blendMode(.screen)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .fleetStaggeredEntrance(index: 0, reduceMotion: effectiveReduceMotion)

            VStack(alignment: .leading, spacing: 22) {
                FleetSectionLabel(
                    title: "Start with your local hardware",
                    subtitle: "One miner to start. Room to grow."
                )
                .fleetStaggeredEntrance(index: 4, reduceMotion: effectiveReduceMotion)
                onboardingStep(
                    "01",
                    title: "Connect to the same local network",
                    detail: FleetDeviceCopy.current.onboardingNetworkDetail,
                    symbol: "wifi"
                )
                .fleetStaggeredEntrance(index: 5, reduceMotion: effectiveReduceMotion)
                onboardingStep(
                    "02",
                    title: "Enter its local address",
                    detail: "An IP address or a .local hostname is all you need.",
                    symbol: "link"
                )
                .fleetStaggeredEntrance(index: 6, reduceMotion: effectiveReduceMotion)
                onboardingStep(
                    "03",
                    title: "Start monitoring",
                    detail: "See live readings and fine-tune your miner.",
                    symbol: "waveform.path"
                )
                .fleetStaggeredEntrance(index: 7, reduceMotion: effectiveReduceMotion)
            }
            .fleetCard()
            .fleetStaggeredEntrance(index: 3, reduceMotion: effectiveReduceMotion)

            VStack(spacing: 9) {
                Button("Just looking? Try the demo", action: exploreDemo)
                    .fleetFont(.subheadline, weight: .semibold)
                    .foregroundStyle(FleetTheme.accent)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("dashboard.exploreDemo")
                Text("The sample data is clearly labeled, and you do not need a miner.")
                    .fleetFont(.footnote)
                    .foregroundStyle(FleetTheme.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .fleetStaggeredEntrance(index: 8, reduceMotion: effectiveReduceMotion)
        }
    }

    private func onboardingStep(_ number: String, title: String, detail: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(number)
                .fleetFont(.caption, weight: .medium, design: .monospaced)
                .foregroundStyle(FleetTheme.accent)
                .padding(.top, 3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Label(title, systemImage: symbol).fleetFont(.subheadline, weight: .semibold)
                    .foregroundStyle(FleetTheme.ink)
                Text(detail).fleetFont(.footnote).foregroundStyle(FleetTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Welcome") {
    ScrollView {
        FleetOnboardingView(addMiner: {}, exploreDemo: {})
            .padding(16)
    }
    .background(FleetTheme.canvas)
}

#Preview("Welcome · Reduce Motion") {
    ScrollView {
        FleetOnboardingView(addMiner: {}, exploreDemo: {}, forceReduceMotion: true)
            .padding(16)
    }
    .background(FleetTheme.canvas)
}
