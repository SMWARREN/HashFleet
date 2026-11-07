import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Bitsy, the Hash Fleet mascot: a friendly little mining rig.
///
/// Each mood is a bundled transparent pose (`Bitsy<Mood>` in the asset catalog). The rig adds life
/// on top of the still art so every pose feels animated without video files:
/// - idle: slow breathe (scaleY) + gentle bob
/// - happy/wave: bounce with squash-and-stretch and a small tilt wobble
/// - celebrate: jump loop with spin-free hops and sparkles
/// - sleepy: slow breathing, drifting "z" bubbles
/// - worried: quick shiver, sweat drop
/// - thinking: side-to-side sway with rising dots
/// Reduce Motion shows the pose still, keeping props (z, dots, sweat) static so meaning survives.
enum BitsyMood: String, CaseIterable, Sendable {
    case idle, wave, celebrate, sleepy, worried, thinking, party

    var assetName: String { "Bitsy" + rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
    /// Falls back to the idle pose when a specific pose has not been bundled.
    var fallbackAssetName: String { BitsyMood.idle.assetName }
}

struct BitsyView: View {
    let mood: BitsyMood
    var size: CGFloat = 120
    /// Pass a changing value to trigger a one-shot hop (e.g. a tap or a new reading).
    var hopTrigger: Int = 0
    /// Allows previews and UI tests to exercise the still pose without changing system settings.
    var forceReduceMotion = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    @State private var hop: CGFloat = 0
    @State private var tapHops = 0

    private var effectiveReduceMotion: Bool { reduceMotion || forceReduceMotion }

    var body: some View {
        Group {
            if effectiveReduceMotion {
                pose(t: 0.35)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    pose(t: context.date.timeIntervalSince(start))
                }
            }
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle())
        .onTapGesture { tapHops += 1 }
        .onChange(of: hopTrigger) { _, _ in bounce() }
        .onChange(of: tapHops) { _, _ in bounce() }
        .sensoryFeedback(.impact(weight: .light), trigger: tapHops)
        .accessibilityHidden(true)
    }

    private func bounce() {
        guard !effectiveReduceMotion else { return }
        withAnimation(.spring(response: 0.22, dampingFraction: 0.5)) { hop = 1 }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.55).delay(0.18)) { hop = 0 }
    }

    @ViewBuilder
    private func pose(t: Double) -> some View {
        let m = motion(t)
        ZStack {
            // Ground shadow shrinks as Bitsy rises.
            Ellipse()
                .fill(Color.black.opacity(0.22))
                .frame(width: size * 0.5 * (1 - m.lift * 0.35), height: size * 0.07)
                .blur(radius: size * 0.02)
                .offset(y: size * 0.45)
            art
                .scaleEffect(x: m.scaleX, y: m.scaleY, anchor: .bottom)
                .rotationEffect(.degrees(m.tilt), anchor: .bottom)
                .offset(x: m.dx, y: -m.lift * size * 0.22 - hop * size * 0.12)
            props(t: t)
        }
    }

    private var art: some View {
        Image(bitsyImageName)
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(width: size * 0.92, height: size * 0.92)
    }

    private var bitsyImageName: String {
#if canImport(UIKit)
        UIImage(named: mood.assetName) != nil ? mood.assetName : mood.fallbackAssetName
#elseif canImport(AppKit)
        NSImage(named: mood.assetName) != nil ? mood.assetName : mood.fallbackAssetName
#else
        mood.fallbackAssetName
#endif
    }

    private struct Motion {
        var scaleX: CGFloat = 1, scaleY: CGFloat = 1, tilt: Double = 0, lift: CGFloat = 0, dx: CGFloat = 0
    }

    private func motion(_ t: Double) -> Motion {
        var m = Motion()
        switch mood {
        case .idle, .wave:
            let breathe = sin(t * 2 * .pi / 2.6)
            m.scaleY = 1 + 0.025 * breathe
            m.scaleX = 1 - 0.012 * breathe
            m.lift = 0.06 * (0.5 + 0.5 * sin(t * 2 * .pi / 2.6 + 1))
            if mood == .wave { m.tilt = 4 * sin(t * 2 * .pi / 1.1) }
        case .celebrate, .party:
            // Hop cycle: crouch (squash) -> launch (stretch) -> land.
            let period = mood == .party ? 0.62 : 0.8
            let p = (t / period).truncatingRemainder(dividingBy: 1)
            let air = max(0, sin(p * .pi))
            m.lift = air
            let squash = p < 0.12 ? (1 - p / 0.12) : (p > 0.9 ? (p - 0.9) / 0.1 : 0)
            m.scaleY = 1 - 0.1 * squash + 0.06 * air
            m.scaleX = 1 + 0.08 * squash - 0.03 * air
            m.tilt = (mood == .party ? 8 : 5) * sin(t * 2 * .pi / (period * 2))
        case .sleepy:
            let breathe = sin(t * 2 * .pi / 4.2)
            m.scaleY = 1 + 0.035 * breathe
            m.scaleX = 1 - 0.015 * breathe
            m.tilt = -3 + 1.5 * breathe
        case .worried:
            m.dx = CGFloat(1.6 * sin(t * 2 * .pi * 7)) * (size / 120)
            m.scaleY = 1 + 0.01 * sin(t * 2 * .pi / 1.4)
        case .thinking:
            m.tilt = 5 * sin(t * 2 * .pi / 3)
            m.lift = 0.04 * (0.5 + 0.5 * sin(t * 2 * .pi / 1.5))
        }
        return m
    }

    @ViewBuilder
    private func props(t: Double) -> some View {
        let amber = Color(red: 245 / 255, green: 172 / 255, blue: 38 / 255)
        switch mood {
        case .sleepy:
            ForEach(0..<3, id: \.self) { i in
                let p = effectiveReduceMotion ? Double(i) / 3 : ((t / 2.4) + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                Text("z")
                    .font(.system(size: size * (0.12 + 0.06 * p), weight: .heavy, design: .rounded))
                    .foregroundStyle(amber.opacity(effectiveReduceMotion ? 0.8 : 1 - p))
                    .offset(x: size * (0.3 + 0.12 * p), y: -size * (0.3 + 0.3 * p))
            }
        case .worried:
            Image(systemName: "drop.fill")
                .font(.system(size: size * 0.11))
                .foregroundStyle(Color(red: 0.55, green: 0.8, blue: 1))
                .offset(x: size * 0.32, y: -size * 0.28 + (effectiveReduceMotion ? 0 : size * 0.06 * CGFloat((t / 1.2).truncatingRemainder(dividingBy: 1))))
                .opacity(effectiveReduceMotion ? 1 : 1 - (t / 1.2).truncatingRemainder(dividingBy: 1) * 0.6)
        case .thinking:
            HStack(spacing: size * 0.03) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(amber)
                        .frame(width: size * 0.06, height: size * 0.06)
                        .offset(y: effectiveReduceMotion ? 0 : -size * 0.04 * max(0, sin(t * 2 * .pi / 1.1 - Double(i) * 0.7)))
                }
            }
            .offset(x: size * 0.34, y: -size * 0.4)
        case .celebrate, .party:
            ForEach(0..<(mood == .party ? 6 : 4), id: \.self) { i in
                let angle = Double(i) / (mood == .party ? 6 : 4) * 2 * .pi + t * 0.8
                let twinkle = effectiveReduceMotion ? 1 : 0.5 + 0.5 * sin(t * 6 + Double(i))
                Image(systemName: "sparkle")
                    .font(.system(size: size * 0.1, weight: .bold))
                    .foregroundStyle(amber)
                    .opacity(twinkle)
                    .scaleEffect(0.7 + 0.5 * twinkle)
                    .offset(x: cos(angle) * size * 0.46, y: sin(angle) * size * 0.34 - size * 0.12)
            }
        case .idle, .wave:
            EmptyView()
        }
    }
}

/// A mascot with a speech bubble, used for friendly guidance and empty states.
struct BitsySays: View {
    let mood: BitsyMood
    let message: String
    var size: CGFloat = 96
    var bubbleOnLeading = false
    /// Adds a VoiceOver action that replays the character's small hop.
    var offersGreetingAction = false
    /// Allows previews and UI tests to exercise the still pose without changing system settings.
    var forceReduceMotion = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    @State private var accessibilityHop = 0

    private var effectiveReduceMotion: Bool { reduceMotion || forceReduceMotion }

    var body: some View {
        Group {
            if offersGreetingAction {
                greeting
                    .accessibilityHint("Use the Say hello to Bitsy action to see a little hop.")
                    .accessibilityAction(named: Text("Say hello to Bitsy")) {
                        accessibilityHop += 1
                    }
                    .sensoryFeedback(.impact(weight: .light), trigger: accessibilityHop)
            } else {
                greeting
            }
        }
    }

    private var greeting: some View {
        HStack(alignment: .center, spacing: 10) {
            if bubbleOnLeading { bubble }
            BitsyView(mood: mood, size: size, hopTrigger: accessibilityHop, forceReduceMotion: effectiveReduceMotion)
            if !bubbleOnLeading { bubble }
        }
        .onAppear {
            withAnimation(effectiveReduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.7).delay(0.25)) {
                shown = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(message)
    }

    private var bubble: some View {
        Text(message)
            .fleetFont(.subheadline, weight: .semibold)
            .foregroundStyle(FleetTheme.ink)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(FleetTheme.raised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(FleetTheme.accent.opacity(0.35), lineWidth: 1)
            }
            .scaleEffect(shown || effectiveReduceMotion ? 1 : 0.6, anchor: bubbleOnLeading ? .trailing : .leading)
            .opacity(shown ? 1 : 0)
    }
}

#Preview("Bitsy moods") {
    ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 24) {
            ForEach(BitsyMood.allCases, id: \.self) { mood in
                VStack {
                    BitsyView(mood: mood, size: 130)
                    Text(mood.rawValue).fleetFont(.caption)
                }
            }
        }
        .padding()
    }
    .background(Color.black)
}
