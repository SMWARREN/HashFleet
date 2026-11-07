import SwiftUI

/// One-shot change effects adapted from ShipSwift's `SWChangeEffect` (`swRise`, `SWShine`).
/// Each effect runs only for a moment after a real increase, never on first appearance and never
/// while idle, so it adds no steady CPU cost. Reduce Motion turns them off.

/// Decides when a live reading genuinely went up. Missing readings are ignored, the first reading
/// is only recorded, and a drop (miner reboot or session reset) re-baselines without firing.
struct FleetIncreaseDetector<Value: Comparable> {
    private(set) var last: Value?

    init(last: Value? = nil) { self.last = last }

    /// Returns the previous value when `newValue` is an increase over it, otherwise nil.
    mutating func observe(_ newValue: Value?) -> Value? {
        guard let newValue else { return nil }
        defer { last = newValue }
        guard let last, newValue > last else { return nil }
        return last
    }
}

enum FleetShareRiseText {
    /// "+1", "+12". Large jumps (the app was asleep or a poll was missed) are capped so the
    /// floater stays short.
    static func text(previous: Int, current: Int) -> String? {
        let delta = current - previous
        guard delta > 0 else { return nil }
        return delta > 999 ? "+999+" : "+\(delta)"
    }
}

// MARK: - Rise

private struct FleetRiseItem: Identifiable {
    let id = UUID()
    let birth: Date
    let text: String
    let drift: Double
}

private struct FleetShareRiseModifier: ViewModifier {
    let value: Int?
    let color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var detector = FleetIncreaseDetector<Int>()
    @State private var items: [FleetRiseItem] = []

    private let lifetime = 1.1
    private let riseDistance = 26.0

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topLeading) {
                if !items.isEmpty {
                    // The timeline only runs while a floater is alive, then pauses.
                    TimelineView(.animation(paused: items.isEmpty)) { context in
                        Canvas { graphics, size in
                            for item in items {
                                let age = context.date.timeIntervalSince(item.birth)
                                guard age >= 0, age <= lifetime else { continue }
                                let life = age / lifetime
                                let eased = 1 - pow(1 - life, 2)
                                let alpha = life < 0.15 ? life / 0.15 : (life < 0.6 ? 1 : 1 - (life - 0.6) / 0.4)
                                let label = graphics.resolve(
                                    Text(item.text)
                                        .font(.system(size: 13, weight: .bold, design: .rounded))
                                        .foregroundStyle(color)
                                )
                                graphics.opacity = alpha
                                graphics.draw(
                                    label,
                                    at: CGPoint(x: size.width / 2 + item.drift, y: size.height / 2 - eased * riseDistance)
                                )
                            }
                        }
                    }
                    .frame(width: 80, height: 60)
                    .offset(x: 10, y: -30)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .onAppear { _ = detector.observe(value) }
            .onChange(of: value) { _, newValue in
                guard let previous = detector.observe(newValue), let newValue,
                      !reduceMotion,
                      let text = FleetShareRiseText.text(previous: previous, current: newValue) else { return }
                let now = Date.now
                items = items.filter { now.timeIntervalSince($0.birth) < lifetime }
                    + [FleetRiseItem(birth: now, text: text, drift: .random(in: -6...6))]
                // Drop finished floaters so the timeline pauses again.
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(lifetime + 0.1))
                    let cutoff = Date.now
                    items = items.filter { cutoff.timeIntervalSince($0.birth) < lifetime }
                }
            }
    }
}

// MARK: - Shine

private struct FleetRecordShineModifier: ViewModifier {
    let value: Decimal?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var detector = FleetIncreaseDetector<Decimal>()
    @State private var trigger = 0

    func body(content: Content) -> some View {
        content
            .overlay {
                if trigger > 0, !reduceMotion {
                    GeometryReader { geometry in
                        let band = max(geometry.size.width * 0.6, 24)
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.85), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: band)
                        .rotationEffect(.degrees(14))
                        .phaseAnimator([false, true], trigger: trigger) { view, swept in
                            view.offset(x: swept ? geometry.size.width + band : -band * 1.5)
                        } animation: { swept in
                            swept ? .easeInOut(duration: 0.8) : nil
                        }
                    }
                    .mask { content }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .onAppear { _ = detector.observe(value) }
            .onChange(of: value) { _, newValue in
                guard detector.observe(newValue) != nil else { return }
                trigger += 1
            }
            #if os(iOS)
            .sensoryFeedback(.success, trigger: trigger)
            #endif
    }
}

extension View {
    /// Floats a short "+N" above the view when an accepted-share count goes up.
    func fleetShareRise(_ value: Int?, color: Color = FleetTheme.positive) -> some View {
        modifier(FleetShareRiseModifier(value: value, color: color))
    }

    /// Sweeps one highlight across a best-share number when it beats its previous value.
    func fleetRecordShine(_ value: Decimal?) -> some View {
        modifier(FleetRecordShineModifier(value: value))
    }
}
