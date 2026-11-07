import SwiftUI

#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Continues the system launch artwork while the app loads underneath.
/// Plays once per launch; the whole screen remains a skip target.
struct FleetStartupSplash: View {
    let holdForTesting: Bool
    let onContinue: () -> Void
    var previewReducedMotion = false

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.colorScheme) private var colorScheme
    private var reduceMotion: Bool { systemReduceMotion || previewReducedMotion }
    @State private var illuminated = false
    @State private var revealsTitle = false
    @State private var completed = false
    @State private var haloBreathing = false
    @State private var pulseRing = false

    private let amber = Color(red: 245 / 255, green: 172 / 255, blue: 38 / 255)
    private let brandArtworkSize: CGFloat = 220

    private static let brandLoopData: Data? = {
        guard let data = NSDataAsset(name: "HashFleetBrandLoop")?.data,
              AnimatedWebPImage.isAnimated(data) else {
            return nil
        }
        return data
    }()

    var body: some View {
        ZStack {
            FleetTheme.canvas

            if colorScheme == .dark {
                Image("HashFleetAmbient")
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 360, height: 360)
                    .scaleEffect(haloBreathing && !reduceMotion ? 1.1 : 0.96)
                    .opacity(haloBreathing && !reduceMotion ? 0.96 : 0.62)
                    .blendMode(.screen)
                    .animation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true), value: haloBreathing)

                // Native ambient treatment keeps the splash premium without changing the approved miner artwork.
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [amber.opacity(0.24), amber.opacity(0.08), .clear],
                            center: .center,
                            startRadius: 8,
                            endRadius: 190
                        )
                    )
                    .frame(width: 360, height: 360)
                    .scaleEffect(haloBreathing && !reduceMotion ? 1.14 : 0.92)
                    .opacity(haloBreathing && !reduceMotion ? 1 : 0.62)
                    .blur(radius: 4)
                    .animation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true), value: haloBreathing)
            }

            Circle()
                .stroke(amber.opacity(haloBreathing && !reduceMotion ? 0.24 : 0.1), lineWidth: 1)
                .frame(width: 286, height: 286)
                .scaleEffect(haloBreathing && !reduceMotion ? 1.08 : 0.94)
                .animation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true), value: haloBreathing)

            // Begin at the exact 220-point storyboard size and center. The animation is
            // loaded from a bundled data set; the approved launch art remains the fallback.
            Group {
                if let brandLoopData = Self.brandLoopData {
                    AnimatedWebPImage(
                        data: brandLoopData,
                        isPlaying: !reduceMotion,
                        displaySize: CGSize(width: brandArtworkSize, height: brandArtworkSize)
                    )
                } else {
                    Image("HashFleetLaunch")
                        .renderingMode(.original)
                        .resizable()
                        .scaledToFit()
                        .overlay {
                            // Preserve the existing power-up accent on the static fallback.
                            Capsule()
                                .fill(amber)
                                .frame(width: 37, height: 3)
                                .shadow(color: amber.opacity(0.8), radius: 9)
                                .position(x: 109, y: 46)
                                .opacity(illuminated ? 0.9 : 0)
                        }
                }
            }
            .frame(width: brandArtworkSize, height: brandArtworkSize)
            .scaleEffect(illuminated && !reduceMotion ? 1.12 : 1)
            .accessibilityLabel("Hash Fleet miner")
            .accessibilityIdentifier("launch.miner")

            // Draw above the artwork so the expanding ring stays visible around the miner.
            Circle()
                .strokeBorder(amber.opacity(0.5), lineWidth: 2)
                .frame(width: 300, height: 300)
                .scaleEffect(pulseRing && !reduceMotion ? 1.22 : 0.98)
                .opacity(pulseRing && !reduceMotion ? 0 : 0.58)
                .animation(.easeOut(duration: 2.2).repeatForever(autoreverses: false), value: pulseRing)

            VStack(spacing: 8) {
                Text("HASH FLEET")
                    .fleetFont(.largeTitle, weight: .semibold, design: .rounded)
                    .tracking(4)
                    .foregroundStyle(FleetTheme.ink)
                Text("Your miners. One fleet.")
                    .fleetFont(.subheadline)
                    .foregroundStyle(FleetTheme.secondary)
            }
            .offset(y: 150 + (revealsTitle || reduceMotion ? 0 : 8))
            .opacity(revealsTitle ? 1 : 0)
            .accessibilityHidden(!revealsTitle)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .overlay {
            Button(action: finish) {
                Color.clear.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open Hash Fleet")
            .accessibilityHint("Skip the introduction")
            .accessibilityIdentifier("launch.continue")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("launch.splash")
        .task {
            if !reduceMotion {
                withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
                    haloBreathing = true
                }
                withAnimation(.easeOut(duration: 2.2).repeatForever(autoreverses: false)) {
                    pulseRing = true
                }
            }
            // The existing held screenshot mode retains the exact launch-screen frame.
            guard !holdForTesting else { return }
            do {
                if reduceMotion {
                    revealsTitle = true
                    try await Task.sleep(for: .milliseconds(450))
                } else {
                    withAnimation(.easeInOut(duration: 0.65)) { illuminated = true }
                    try await Task.sleep(for: .milliseconds(250))
                    withAnimation(.easeOut(duration: 0.45)) { revealsTitle = true }
                    try await Task.sleep(for: .milliseconds(650))
                    withAnimation(.easeOut(duration: 0.4)) { illuminated = false }
                    try await Task.sleep(for: .milliseconds(500))
                }
                try Task.checkCancellation()
                finish()
            } catch {
                // Leaving or skipping the splash cancels its sequence.
            }
        }
    }

    private func finish() {
        guard !completed else { return }
        completed = true
        onContinue()
    }
}

private struct FleetSplashPreview: View {
    var reducedMotion = false
    @State private var replayID = UUID()
    @State private var finished = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if !finished {
                FleetStartupSplash(holdForTesting: false, onContinue: {
                    withAnimation(reducedMotion ? nil : .easeOut(duration: 0.25)) { finished = true }
                }, previewReducedMotion: reducedMotion)
                .id(replayID)
                .transition(.opacity)
            } else {
                Button("Replay splash") {
                    replayID = UUID()
                    finished = false
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
        }
    }
}

#Preview("Splash · replay") {
    FleetSplashPreview()
        .preferredColorScheme(.dark)
}

#Preview("Splash · reduced motion") {
    FleetSplashPreview(reducedMotion: true)
        .preferredColorScheme(.dark)
}

#Preview("Splash · launch match") {
    FleetStartupSplash(holdForTesting: true, onContinue: {})
}
