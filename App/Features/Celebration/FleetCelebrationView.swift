import SwiftUI
import HashFleetCore

/// A milestone worth a full-screen moment: a new personal best share difficulty or a found block.
/// Carries only display fields and the miner ID so it can be rebuilt from a notification payload.
struct FleetCelebration: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable, Equatable {
        case bestShareAllTime
        case bestShareSession
        case blockFound
    }

    let id: UUID
    let kind: Kind
    let deviceID: UUID
    let minerName: String
    /// Headline number, e.g. "392.00M" or a block height.
    let value: String
    let detail: String
    /// False only for sample previews created while the fleet is empty: there is no real
    /// miner to open, so the celebration offers `Keep mining` alone instead of routing to
    /// the removed-miner fallback.
    var viewMinerAvailable: Bool = true

    init(id: UUID = UUID(), kind: Kind, deviceID: UUID, minerName: String, value: String, detail: String) {
        self.id = id
        self.kind = kind
        self.deviceID = deviceID
        self.minerName = minerName
        self.value = value
        self.detail = detail
    }

    init(_ event: MinerBestShareEvent) {
        self.init(
            id: event.id,
            kind: event.kind == .allTime ? .bestShareAllTime : .bestShareSession,
            deviceID: event.deviceID,
            minerName: event.minerName,
            value: event.displayValue,
            detail: event.kind == .allTime ? "New all-time best share difficulty" : "New best share this session"
        )
    }

    /// All record kinds use this illustrated popup. Status and safety alerts keep their
    /// existing alert surfaces and must not be mistaken for a mining record.
    init?(_ event: FleetNotificationEvent) {
        switch event {
        case .bestShare(let share): self.init(share)
        case .blockFound(let block): self.init(block)
        case .stateChange, .metricAlert, .power, .temperature: return nil
        }
    }

    init(_ event: MinerBlockFoundEvent) {
        let coin = event.coinLabel.map { "\($0) block" } ?? "Block"
        self.init(
            id: event.id,
            kind: .blockFound,
            deviceID: event.deviceID,
            minerName: event.minerName,
            value: event.height.map { FleetFormat.blockHeight($0) } ?? coin,
            detail: event.height == nil ? "Your miner reported a found block" : "\(coin) found at this height"
        )
    }

    var eyebrow: String {
        switch kind {
        case .bestShareAllTime: "NEW HIGH SCORE"
        case .bestShareSession: "SESSION BEST"
        case .blockFound: "BLOCK FOUND"
        }
    }

    var headline: String {
        switch kind {
        case .bestShareAllTime, .bestShareSession: "\(minerName) hit a new best"
        case .blockFound: "\(minerName) found a block!"
        }
    }

    var valueCaption: String {
        switch kind {
        case .bestShareAllTime, .bestShareSession: "difficulty"
        case .blockFound: detail.hasPrefix("Your") ? "" : "height"
        }
    }

    var isBlock: Bool { kind == .blockFound }

    // MARK: Notification payload

    static let userInfoKind = "app.hashfleet.celebration.kind"
    static let userInfoDevice = "app.hashfleet.deviceID"
    static let userInfoMiner = "app.hashfleet.minerName"
    static let userInfoValue = "app.hashfleet.celebration.value"
    static let userInfoDetail = "app.hashfleet.celebration.detail"
    static let userInfoID = "app.hashfleet.celebration.id"

    var userInfo: [String: String] {
        [
            Self.userInfoKind: kind.rawValue,
            Self.userInfoDevice: deviceID.uuidString,
            Self.userInfoMiner: minerName,
            Self.userInfoValue: value,
            Self.userInfoDetail: detail,
            Self.userInfoID: id.uuidString
        ]
    }

    init?(userInfo: [AnyHashable: Any]) {
        guard let rawKind = userInfo[Self.userInfoKind] as? String,
              let kind = Kind(rawValue: rawKind),
              let rawDevice = userInfo[Self.userInfoDevice] as? String,
              let deviceID = UUID(uuidString: rawDevice),
              let minerName = userInfo[Self.userInfoMiner] as? String,
              let value = userInfo[Self.userInfoValue] as? String else { return nil }
        let id = (userInfo[Self.userInfoID] as? String).flatMap(UUID.init(uuidString:)) ?? UUID()
        self.init(
            id: id, kind: kind, deviceID: deviceID, minerName: minerName,
            value: value, detail: userInfo[Self.userInfoDetail] as? String ?? ""
        )
    }
}

/// Full-screen celebration. Choreography (ms): backdrop 0, rays 0 to loop, mascot spring 80,
/// eyebrow 260, value count-up 360 to 1260, headline 520, buttons 700, confetti burst 380.
/// Reduce Motion: static mascot, no rays, no confetti, no count-up, opacity-only entrance.
struct FleetCelebrationView: View {
    let celebration: FleetCelebration
    let onViewMiner: () -> Void
    let onDismiss: () -> Void
    var onDisableSessionBestAlerts: (() -> Void)?
    var onSupport: (() -> Void)?
    var pendingCount: Int = 0
    var onReviewLater: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var appeared = false
    @State private var revealedValue = false
    @State private var confettiStart: Date?
    @State private var hapticTrigger = 0

    private let amber = Color(red: 245 / 255, green: 172 / 255, blue: 38 / 255)

    var body: some View {
        ZStack {
            backdrop
            if !reduceMotion { RaysView(color: amber, isBlock: celebration.isBlock).opacity(appeared ? 1 : 0) }
            if dynamicTypeSize.isAccessibilitySize {
                ScrollView {
                    content.padding(.vertical, 24)
                }
            } else {
                // Keep a direct hit-test path when everything fits. A permanent
                // scroll container can obscure controls above another scene sheet.
                ViewThatFits(in: .vertical) {
                    content
                    ScrollView { content.padding(.vertical, 24) }
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("celebration.screen")
        .accessibilityValue(ProcessInfo.processInfo.arguments.contains("--ui-testing") ? celebration.id.uuidString : "")
        .sensoryFeedback(celebration.isBlock ? .success : .impact(weight: .heavy), trigger: hapticTrigger)
        .onAppear(perform: start)
    }

    private var backdrop: some View {
        ZStack {
            Color.black.opacity(0.94)
            RadialGradient(
                colors: [amber.opacity(celebration.isBlock ? 0.55 : 0.4), .clear],
                center: .center, startRadius: 10, endRadius: 420
            )
            .scaleEffect(appeared && !reduceMotion ? 1 : 0.6)
        }
        .opacity(appeared ? 1 : 0)
        .onTapGesture(perform: onDismiss)
        .accessibilityHidden(true)
    }

    private var content: some View {
        VStack(spacing: dynamicTypeSize.isAccessibilitySize ? 12 : 18) {
            Spacer(minLength: dynamicTypeSize.isAccessibilitySize ? 24 : 40)
            mascot
            Text(celebration.eyebrow)
                .fleetFont(.subheadline, weight: .heavy, design: .monospaced)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .tracking(3)
                .foregroundStyle(amber)
                // Bright rays must not blend into individual heading glyphs as they turn.
                // Keep the illustrated celebration intact, with a stable contrast surface.
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.black.opacity(0.65), in: Capsule())
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared || reduceMotion ? 0 : 12)
                .animation(entrance(delay: 0.26), value: appeared)
                .accessibilityIdentifier("celebration.eyebrow")
            valueLabel
            Text(celebration.headline)
                .fleetFont(.title2, weight: .bold)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared || reduceMotion ? 0 : 14)
                .animation(entrance(delay: 0.52), value: appeared)
                .accessibilityIdentifier("celebration.headline")
            Text(celebration.detail)
                .fleetFont(.subheadline)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .accessibilityShowsLargeContentViewer { Text(celebration.detail) }
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .opacity(appeared ? 1 : 0)
                .animation(entrance(delay: 0.6), value: appeared)
                .accessibilityIdentifier("celebration.detail")
            Spacer(minLength: dynamicTypeSize.isAccessibilitySize ? 12 : 20)
            buttons
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared || reduceMotion ? 0 : 20)
                .animation(entrance(delay: 0.7), value: appeared)
            Spacer(minLength: dynamicTypeSize.isAccessibilitySize ? 24 : 34)
        }
        .padding(.horizontal, 28)
    }

    private var mascot: some View {
        let side: CGFloat = dynamicTypeSize.isAccessibilitySize ? 150 : 230
        return ZStack {
            Circle()
                .fill(amber.opacity(0.22))
                .frame(width: side * 1.05, height: side * 1.05)
                .blur(radius: 30)
                .scaleEffect(appeared && !reduceMotion ? 1.1 : 0.8)
                .animation(reduceMotion ? nil : .easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: appeared)
            FleetAnimatedArt(
                .fleetCluster,
                size: CGSize(width: side * 1.1, height: side * 0.73)
            )
            .opacity(celebration.isBlock ? 0.55 : 0)
            .offset(y: side * 0.28)
            .scaleEffect(0.8)
            BitsyView(
                mood: celebration.isBlock ? .party : .celebrate,
                size: side,
                hopTrigger: hapticTrigger
            )
            .offset(y: celebration.isBlock ? -side * 0.08 : 0)
            .accessibilityElement()
            .accessibilityLabel(celebration.isBlock ? "Bitsy is throwing a block party" : "Bitsy is celebrating")
            .accessibilityIdentifier("celebration.mascot")
            if celebration.isBlock {
                Image(systemName: "cube.fill")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(amber)
                    .shadow(color: amber.opacity(0.8), radius: 16)
                    .offset(y: -side * 0.62)
                    .symbolEffect(.bounce, options: .repeat(2), value: hapticTrigger)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(amber)
                    .shadow(color: amber.opacity(0.8), radius: 14)
                    .offset(x: side * 0.42, y: -side * 0.42)
                    .symbolEffect(.bounce, options: .repeat(2), value: hapticTrigger)
                    .accessibilityHidden(true)
            }
        }
        .background {
            if !reduceMotion, let confettiStart {
                // Keep bright particles inside the artwork, away from readable copy and actions.
                ConfettiView(start: confettiStart, isBlock: celebration.isBlock)
                    .clipped()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .scaleEffect(appeared ? 1 : (reduceMotion ? 1 : 0.3))
        .rotationEffect(.degrees(appeared || reduceMotion ? 0 : -12))
        .opacity(appeared ? 1 : 0)
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.55, dampingFraction: 0.58).delay(0.08), value: appeared)
    }

    private var valueLabel: some View {
        VStack(spacing: 2) {
            Group {
                if reduceMotion || !revealedValue {
                    Text(revealedValue || reduceMotion ? celebration.value : Self.scrambled(celebration.value))
                } else {
                    Text(celebration.value)
                }
            }
            .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 44 : 64, weight: .black, design: .rounded))
            .foregroundStyle(
                LinearGradient(colors: [.white, amber], startPoint: .top, endPoint: .bottom)
            )
            .shadow(color: amber.opacity(0.7), radius: 18)
            .contentTransition(.numericText())
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .scaleEffect(revealedValue && !reduceMotion ? 1 : (reduceMotion ? 1 : 0.85))
            .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.55), value: revealedValue)
            .accessibilityIdentifier("celebration.value")
            if !celebration.valueCaption.isEmpty {
                Text(celebration.valueCaption.uppercased())
                    .fleetFont(.caption, weight: .semibold)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .opacity(appeared ? 1 : 0)
        .animation(entrance(delay: 0.36), value: appeared)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(celebration.value) \(celebration.valueCaption)")
    }

    private var buttons: some View {
        VStack(spacing: 12) {
            if celebration.viewMinerAvailable {
                Button(action: onViewMiner) {
                    Label("View \(celebration.minerName)", systemImage: "arrow.right.circle.fill")
                        .fleetFont(.headline)
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, minHeight: 54)
                }
                .buttonStyle(.borderedProminent)
                .tint(amber)
                .foregroundStyle(.black)
                .clipShape(Capsule())
                .accessibilityIdentifier("celebration.viewMiner")
            }
            if pendingCount > 0 {
                Text("\(pendingCount) more waiting")
                    .fleetFont(.caption, weight: .semibold)
                    .foregroundStyle(.white.opacity(0.75))
                    .accessibilityIdentifier("celebration.waitingCount")
            }
            if let onReviewLater {
                Button(action: onReviewLater) {
                    Text("Review later")
                        .fleetFont(.subheadline, weight: .semibold)
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .accessibilityIdentifier("celebration.reviewLater")
                .accessibilityHint("Pauses record popups without acknowledging or discarding any records. New records keep queuing.")
            }
            Button(action: onDismiss) {
                Text("Keep mining")
                    .fleetFont(.subheadline, weight: .semibold)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.8))
            .accessibilityIdentifier("celebration.dismiss")
            if celebration.kind == .bestShareSession, let onDisableSessionBestAlerts {
                Button(action: onDisableSessionBestAlerts) {
                    Text("Turn off session-best alerts")
                        .fleetFont(.footnote)
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .multilineTextAlignment(.center)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.65))
                .accessibilityIdentifier("celebration.disableSessionAlerts")
                .accessibilityHint(
                    "Turns off only session-best alerts. " +
                    "All-time records, blocks and safety alerts keep their current settings. " +
                    "You can turn session-best alerts back on in App settings."
                )
            }
            // This is internal navigation. The destination rechecks payment eligibility.
            if let onSupport {
                Button(action: onSupport) {
                    Label("Support Hash Fleet", systemImage: "heart")
                        .fleetFont(.footnote)
                        .multilineTextAlignment(.center)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.7))
                .accessibilityIdentifier("celebration.support")
                .accessibilityHint("Opens the optional support page. No payment is made and no features are unlocked.")
            }
        }
    }

    private func entrance(delay: Double) -> Animation? {
        reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.78).delay(delay)
    }

    private func start() {
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .easeOut(duration: 0.35)) { appeared = true }
        hapticTrigger += 1
        guard !reduceMotion else {
            revealedValue = true
            return
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(380))
            confettiStart = .now
            try? await Task.sleep(for: .milliseconds(520))
            withAnimation(.spring(response: 0.5, dampingFraction: 0.55)) { revealedValue = true }
            hapticTrigger += 1
        }
    }

    /// Same-width placeholder digits so the numeric transition rolls into the real value.
    static func scrambled(_ value: String) -> String {
        String(value.map { $0.isNumber ? "0" : $0 })
    }
}

/// Slowly rotating god-rays behind the mascot. Pure SwiftUI shapes, no assets.
private struct RaysView: View {
    let color: Color
    let isBlock: Bool

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { canvas, size in
                let center = CGPoint(x: size.width / 2, y: size.height * 0.38)
                let count = isBlock ? 18 : 14
                let reach = max(size.width, size.height)
                let spin = t * (isBlock ? 0.22 : 0.14)
                for i in 0..<count {
                    let angle = spin + Double(i) / Double(count) * 2 * .pi
                    let spread = 0.07
                    var path = Path()
                    path.move(to: center)
                    path.addLine(to: CGPoint(x: center.x + cos(angle - spread) * reach, y: center.y + sin(angle - spread) * reach))
                    path.addLine(to: CGPoint(x: center.x + cos(angle + spread) * reach, y: center.y + sin(angle + spread) * reach))
                    path.closeSubpath()
                    canvas.fill(path, with: .radialGradient(
                        Gradient(colors: [color.opacity(0.28), color.opacity(0)]),
                        center: center, startRadius: 40, endRadius: reach * 0.7
                    ))
                }
            }
        }
        .blendMode(.plusLighter)
        .accessibilityHidden(true)
    }
}

/// One-shot confetti burst driven by elapsed time, so it needs no per-particle state.
private struct ConfettiView: View {
    let start: Date
    let isBlock: Bool

    private struct Particle {
        let angle: Double
        let speed: Double
        let spin: Double
        let size: CGFloat
        let hue: Color
        let isCoin: Bool
    }

    private static func particles(isBlock: Bool) -> [Particle] {
        var generator = SeededGenerator(seed: isBlock ? 7 : 3)
        let palette: [Color] = [
            Color(red: 1, green: 0.76, blue: 0.2), Color(red: 1, green: 0.55, blue: 0.1),
            .white, Color(red: 1, green: 0.9, blue: 0.55)
        ]
        return (0..<(isBlock ? 90 : 64)).map { _ in
            Particle(
                angle: Double.random(in: -.pi * 0.95 ... -.pi * 0.05, using: &generator),
                speed: Double.random(in: 380...820, using: &generator),
                spin: Double.random(in: -8...8, using: &generator),
                size: CGFloat.random(in: 6...12, using: &generator),
                hue: palette[Int.random(in: 0..<palette.count, using: &generator)],
                isCoin: Double.random(in: 0...1, using: &generator) < (isBlock ? 0.4 : 0.2)
            )
        }
    }

    var body: some View {
        let particles = Self.particles(isBlock: isBlock)
        TimelineView(.animation) { context in
            let elapsed = context.date.timeIntervalSince(start)
            Canvas { canvas, size in
                guard elapsed < 3.2 else { return }
                let origin = CGPoint(x: size.width / 2, y: size.height * 0.38)
                let gravity = 900.0
                let fade = max(0, 1 - max(0, elapsed - 2.0) / 1.2)
                for p in particles {
                    let x = origin.x + cos(p.angle) * p.speed * elapsed
                    let y = origin.y + sin(p.angle) * p.speed * elapsed + 0.5 * gravity * elapsed * elapsed
                    var ctx = canvas
                    ctx.opacity = fade
                    ctx.translateBy(x: x, y: y)
                    ctx.rotate(by: .radians(p.spin * elapsed))
                    let rect = CGRect(x: -p.size / 2, y: -p.size / 4, width: p.size, height: p.isCoin ? p.size : p.size / 2)
                    if p.isCoin {
                        ctx.fill(Path(ellipseIn: rect), with: .color(Color(red: 1, green: 0.72, blue: 0.1)))
                        ctx.stroke(Path(ellipseIn: rect.insetBy(dx: 1.5, dy: 1.5)), with: .color(.white.opacity(0.6)), lineWidth: 1)
                    } else {
                        ctx.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(p.hue))
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Deterministic confetti so screenshots and tests are stable.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E37_79B9_7F4A_7C15 | 1 }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

#Preview("Best share") {
    FleetCelebrationView(
        celebration: FleetCelebration(
            kind: .bestShareAllTime, deviceID: UUID(), minerName: "Workshop Gamma",
            value: "392.00M", detail: "New all-time best share difficulty"
        ),
        onViewMiner: {}, onDismiss: {}
    )
}

#Preview("Block") {
    FleetCelebrationView(
        celebration: FleetCelebration(
            kind: .blockFound, deviceID: UUID(), minerName: "Office Gamma",
            value: "912,345", detail: "BTC block found at this height"
        ),
        onViewMiner: {}, onDismiss: {}
    )
}
