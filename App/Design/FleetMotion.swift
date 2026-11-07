import SwiftUI

/// Small, availability-gated motion affordances shared by the fleet dashboard.
///
/// The iOS 17 branch intentionally leaves navigation on the system default. The
/// iOS 18 zoom is opt-in at each call site so Reduce Motion can remove both the
/// source registration and the destination transition without changing layout.
extension View {
    @ViewBuilder
    func fleetMinerTransitionSource<ID: Hashable>(
        id: ID,
        in namespace: Namespace.ID,
        enabled: Bool
    ) -> some View {
        #if os(iOS)
        if #available(iOS 18.0, *), enabled {
            matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
        #else
        self
        #endif
    }

    @ViewBuilder
    func fleetMinerNavigationTransition<ID: Hashable>(
        sourceID: ID,
        in namespace: Namespace.ID,
        enabled: Bool
    ) -> some View {
        #if os(iOS)
        if #available(iOS 18.0, *), enabled {
            navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        } else {
            self
        }
        #else
        self
        #endif
    }

    /// Gives the deliberate appearance toggle a single native symbol bounce
    /// rather than adding motion to telemetry-driven or continuously visible UI.
    @ViewBuilder
    func fleetAppearanceSymbolEffect(trigger: Int, enabled: Bool) -> some View {
        if #available(iOS 17.0, *), enabled {
            symbolEffect(.bounce, options: .speed(1.15), value: trigger)
        } else {
            self
        }
    }
}

/// One-shot, state-keyed entrance and emphasis motion shared by dashboard, detail,
/// achievements, onboarding and settings surfaces.
///
/// Policy (docs/research/native-motion.md): every effect is gated on
/// `accessibilityReduceMotion`; under Reduce Motion the view renders immediately
/// with no interpolation. Entrances fire once per view appearance because the
/// driver state is reset in `onAppear`, never by a plain re-render.
struct FleetStaggeredEntranceModifier: ViewModifier {
    /// Position of this view within its reveal sequence (0-based).
    let index: Int
    /// Milliseconds of delay per step; total delay is capped so late items still settle quickly.
    var stepMilliseconds: Double = 40
    /// Ambient Reduce Motion setting supplied by the call site.
    let reduceMotion: Bool

    @State private var shown = false

    private var delay: TimeInterval {
        Double(min(index, 8)) * stepMilliseconds / 1_000
    }

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 12)
            .animation(
                shown ? nil : .easeOut(duration: 0.32).delay(delay),
                value: shown
            )
            .onAppear {
                guard !reduceMotion, !shown else { return }
                shown = true
            }
            .onDisappear {
                // Reset once per appearance so returning to the screen reveals again.
                shown = false
            }
    }
}

extension View {
    /// Staggered fade + small-offset entrance keyed to a real `onAppear`, not to re-renders.
    ///
    /// Under Reduce Motion the content is presented immediately with no animation.
    func fleetStaggeredEntrance(index: Int, reduceMotion: Bool, stepMilliseconds: Double = 40) -> some View {
        modifier(FleetStaggeredEntranceModifier(
            index: index,
            stepMilliseconds: stepMilliseconds,
            reduceMotion: reduceMotion
        ))
    }

    /// Subtle scroll-linked scale/opacity for miner cards (iOS 17 `scrollTransition`).
    ///
    /// The effect is intentionally small so telemetry readings stay legible while a
    /// card travels under the navigation bar, and it collapses to no motion under
    /// Reduce Motion.
    @ViewBuilder
    func fleetMinerCardScrollTransition(reduceMotion: Bool) -> some View {
        if #available(iOS 17.0, *), !reduceMotion {
            scrollTransition(.animated(.easeOut(duration: 0.2))) { content, phase in
                content
                    .scaleEffect(phase.isIdentity ? 1 : 0.975)
                    .opacity(phase.isIdentity ? 1 : 0.82)
            }
        } else {
            self
        }
    }
}

/// Emphasizes a status dot exactly once when its miner crosses an online/offline
/// boundary, rather than pulsing continuously.
///
/// The driver is the card's derived online state, so ordinary telemetry updates
/// (hashrate, temperature, uptime) never retrigger it. The initial value on a
/// fresh appearance is captured without animating.
struct FleetStatusTransitionPulseModifier: ViewModifier {
    /// The current online/offline presentation state of the miner.
    let isOnline: Bool
    let color: Color
    let reduceMotion: Bool

    /// Bumped only when `isOnline` actually changes; drives the one-shot ring.
    @State private var pulseTrigger = 0
    @State private var previousOnline: Bool?

    func body(content: Content) -> some View {
        content
            .overlay {
                // One outward ripple per online/offline transition. The ring starts at the
                // dot's edge and expands to transparent, then stays hidden until the state
                // changes again. Never rendered under Reduce Motion.
                if #available(iOS 17.0, *), !reduceMotion, pulseTrigger > 0 {
                    RippleRing(color: color, trigger: pulseTrigger)
                }
            }
            .onChange(of: isOnline) { _, newValue in
                defer { previousOnline = newValue }
                guard let previousOnline, previousOnline != newValue, !reduceMotion else { return }
                pulseTrigger += 1
            }
    }
}

/// The expanding stroke used by `fleetStatusTransitionPulse`. Kept as its own view so
/// the ring's state is owned per pulse rather than fighting the modifier's own body.
private struct RippleRing: View {
    let color: Color
    let trigger: Int

    @State private var expanded = false

    var body: some View {
        Circle()
            .stroke(color.opacity(expanded ? 0 : 0.7), lineWidth: 1.5)
            .scaleEffect(expanded ? 2.4 : 1)
            .onAppear {
                withAnimation(.easeOut(duration: 0.6)) { expanded = true }
            }
            .accessibilityHidden(true)
            .id(trigger)
    }
}

extension View {
    /// One-shot status-dot pulse ring for a genuine online/offline transition.
    ///
    /// Under Reduce Motion the dot keeps its plain idle appearance.
    func fleetStatusTransitionPulse(isOnline: Bool, color: Color, reduceMotion: Bool) -> some View {
        modifier(FleetStatusTransitionPulseModifier(
            isOnline: isOnline,
            color: color,
            reduceMotion: reduceMotion
        ))
    }
}
