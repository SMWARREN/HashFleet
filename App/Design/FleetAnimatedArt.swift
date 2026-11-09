import SwiftUI

#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Bundled fan-spin loops generated from the static fleet illustrations by
/// `Tools/generate_fleet_art_loops.py`. The static PNG is always the fallback.
enum FleetArtLoop: String, CaseIterable, Sendable {
    case fleetCluster = "FleetClusterArt"
    case minerCooling = "MinerCoolingArt"
    case brand = "HashFleetLaunch"

    var staticImageName: String { rawValue }

    var loopAssetName: String {
        switch self {
        case .fleetCluster: "FleetClusterArtLoop"
        case .minerCooling: "MinerCoolingArtLoop"
        case .brand: "HashFleetBrandLoop"
        }
    }

    /// Decoded once per process; `NSDataAsset` reads are not free and several screens share a loop.
    @MainActor private static var cache: [FleetArtLoop: Data] = [:]

    @MainActor var loopData: Data? {
        if let cached = Self.cache[self] { return cached }
        guard let data = NSDataAsset(name: loopAssetName)?.data,
              AnimatedWebPImage.isAnimated(data) else { return nil }
        Self.cache[self] = data
        return data
    }
}

/// Plays a fleet illustration's fan loop. Reduce Motion shows the static frame, and the view
/// keeps the exact frame size either way so layouts never jump between the two states.
struct FleetAnimatedArt: View {
    let loop: FleetArtLoop
    let size: CGSize
    var isPlaying = true
    var accessibilityIdentifier: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(_ loop: FleetArtLoop, size: CGSize, isPlaying: Bool = true, accessibilityIdentifier: String? = nil) {
        self.loop = loop
        self.size = size
        self.isPlaying = isPlaying
        self.accessibilityIdentifier = accessibilityIdentifier
    }

    var body: some View {
        Group {
            if let data = loop.loopData {
                AnimatedWebPImage(data: data, isPlaying: isPlaying && !reduceMotion, displaySize: size)
            } else {
                Image(loop.staticImageName)
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: size.width, height: size.height)
        .accessibilityHidden(true)
        .modifier(OptionalIdentifier(identifier: accessibilityIdentifier))
    }
}

/// Automatically spins the actual illustration for about ten seconds on each appearance,
/// then rests. A tap replays a shorter burst. Both durations are whole seamless loops.
/// Reduce Motion (or `isEnabled == false`) keeps the static frame.
struct FleetLoadAnimatedArt: View {
    let loop: FleetArtLoop
    let size: CGSize
    var isEnabled = true
    var accessibilityIdentifier: String?

    /// One seamless pass of the bundled fan loop (48 frames at 42 ms).
    static let loopDuration: Duration = .milliseconds(2016)
    static let entranceDuration = loopDuration * 5
    static let replayDuration = loopDuration * 2

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var isSpinning = false
    @State private var isVisible = false
    @State private var manualSpins = 0

    private var canAnimate: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        let testReduceMotion = arguments.contains("--ui-testing") && arguments.contains("--ui-test-reduce-motion")
        return isEnabled && !reduceMotion && !testReduceMotion
    }

    private var shouldPlay: Bool { canAnimate && isVisible && scenePhase == .active }

    var body: some View {
        Color.clear
            .frame(width: size.width, height: size.height)
            .overlay {
                FleetAnimatedArt(loop, size: size, isPlaying: shouldPlay && isSpinning)
            }
            .contentShape(Rectangle())
            .onTapGesture { if canAnimate { manualSpins += 1 } }
            // The art is decorative, but because tapping spins the fans it is exposed
            // as one element with a matching action instead of being hidden.
            .accessibilityElement()
            .accessibilityLabel("Three miners")
            .accessibilityAddTraits(canAnimate ? [.isButton, .isImage] : .isImage)
            .accessibilityHint(canAnimate ? "Spins up the miner fans." : "")
            .accessibilityAction { if canAnimate { manualSpins += 1 } }
            .modifier(OptionalIdentifier(identifier: accessibilityIdentifier))
            .sensoryFeedback(.impact(weight: .light), trigger: manualSpins) { oldValue, newValue in
                newValue > oldValue
            }
            .onAppear {
                manualSpins = 0
                isVisible = true
            }
            .task(id: TaskKey(canAnimate: shouldPlay, manualSpins: manualSpins)) {
                guard shouldPlay else {
                    isSpinning = false
                    return
                }
                isSpinning = true
                do {
                    try await Task.sleep(for: manualSpins > 0 ? Self.replayDuration : Self.entranceDuration)
                    try Task.checkCancellation()
                } catch {
                    return
                }
                isSpinning = false
            }
            .onDisappear {
                isVisible = false
                isSpinning = false
            }
    }

    private struct TaskKey: Equatable {
        let canAnimate: Bool
        let manualSpins: Int
    }
}

private struct OptionalIdentifier: ViewModifier {
    let identifier: String?
    func body(content: Content) -> some View {
        if let identifier { content.accessibilityIdentifier(identifier) } else { content }
    }
}
