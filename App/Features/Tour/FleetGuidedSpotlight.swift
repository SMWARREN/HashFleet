import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

// Building blocks for a *guided, restricted* preview session where the tour points at
// the app's real screens and controls instead of illustrated cards.
//
// Everything here is opt-in and additive:
// - `fleetGuidedDemo` defaults to `false` everywhere in the app.
// - `fleetTourTarget(_:)` is a complete no-op unless that flag is `true` in the
//   environment, so ordinary screens are byte-for-byte unchanged (no `.id`, no
//   anchor preference, no extra view wrapper behavior) outside a restricted demo.
// - The root owns turning the flag on for a specific guided session, collecting the
//   `FleetTourAnchorKey` anchors with a `GeometryReader`'s `proxy[anchor]`, and
//   deciding which real screen is currently on-screen. This file does not present any
//   screen, navigate anywhere, or read/write persistence itself.

// MARK: - Guided-demo environment flag

private struct FleetGuidedDemoKey: EnvironmentKey {
    static let defaultValue = false
}

private struct FleetGuidedTargetKey: EnvironmentKey { static let defaultValue = "" }

extension EnvironmentValues {
    var fleetGuidedTargetID: String {
        get { self[FleetGuidedTargetKey.self] }
        set { self[FleetGuidedTargetKey.self] = newValue }
    }
    /// True only inside the root's restricted guided-tour demo session. Defaults to
    /// `false`, so `fleetTourTarget` has zero effect unless a caller explicitly opts a
    /// subtree into the guided preview.
    var fleetGuidedDemo: Bool {
        get { self[FleetGuidedDemoKey.self] }
        set { self[FleetGuidedDemoKey.self] = newValue }
    }
}

// MARK: - Anchor collection

/// Collects named bounds anchors for real on-screen controls the guided tour may want
/// to spotlight. Only populated while `fleetGuidedDemo` is true; contributes nothing
/// (and costs nothing extra to diff/layout) in every ordinary app session.
struct FleetTourAnchorKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] { [:] }

    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        // Later writers (e.g. a control that re-renders after a route change) win, but
        // an id already present without a fresh value this pass is left alone.
        value.merge(nextValue()) { _, new in new }
    }
}

private struct FleetTourTargetModifier: ViewModifier {
    let id: String
    @Environment(\.fleetGuidedDemo) private var guided
    @Environment(\.fleetGuidedTargetID) private var requestedTarget

    func body(content: Content) -> some View {
        if guided {
            content
                // Stable identity lets a root `ScrollViewReader` `scrollTo(id)` a real
                // `List`/`ScrollView` row into view before the spotlight measures it.
                .id(id)
                .background {
                    if requestedTarget == id { FleetGuidedScrollMarker().accessibilityHidden(true) }
                }
                .anchorPreference(key: FleetTourAnchorKey.self, value: .bounds) { anchor in
                    [id: anchor]
                }
        } else {
            content
        }
    }
}

extension View {
    /// Marks a real control as a guided-tour target by name. Outside a restricted
    /// guided demo session (`fleetGuidedDemo == false`) this is a no-op: no `.id`, no
    /// anchor preference, no behavior change to the underlying view or its identity.
    func fleetTourTarget(_ id: String) -> some View {
        modifier(FleetTourTargetModifier(id: id))
    }
}

// MARK: - Pure geometry helper (host-runnable, no view/runtime dependency)

/// Rect validation extracted as a pure function so it is directly testable without
/// standing up SwiftUI hosting. Used to decide whether a measured anchor is safe to
/// draw a spotlight around, or whether the tour should show its "preparing" state
/// instead of an arbitrary/bogus rectangle.
enum FleetTourGeometry {
    /// Keep the same clearance on phone, tablet and desktop tour highlights.
    static var highlightOutset: CGFloat { FleetSurfaceSpacing.highlightOutset }

    /// A usable target rect must be finite, have positive size, and actually overlap
    /// the bounds it will be drawn into. This rejects degenerate anchors (a view that
    /// has not laid out yet, a zero-size placeholder) and anchors that measured to a
    /// coordinate space entirely outside the current screen.
    static func isValid(_ rect: CGRect, in bounds: CGRect) -> Bool {
        guard rect.origin.x.isFinite, rect.origin.y.isFinite,
              rect.width.isFinite, rect.height.isFinite,
              rect.width > 0, rect.height > 0,
              bounds.width > 0, bounds.height > 0 else { return false }
        return bounds.intersects(rect)
    }

    /// The portion of `rect` (expanded by `outset` on every side) that is actually
    /// visible inside `bounds`. Returns `nil` when the rect is invalid or the visible
    /// remainder is empty, so callers never draw or hit-test a bogus/offscreen shape.
    static func clippedTarget(_ rect: CGRect, outset: CGFloat, in bounds: CGRect) -> CGRect? {
        guard isValid(rect, in: bounds) else { return nil }
        let expanded = rect.insetBy(dx: -outset, dy: -outset)
        let visible = expanded.intersection(bounds)
        return visible.isEmpty ? nil : visible
    }
}

// MARK: - Spotlight overlay

/// A restricted-preview overlay that dims the real screen behind it except for a
/// rounded-rect hole around one live target, and turns that hole into the only tappable
/// action. Fills whatever parent coordinate system it is placed in; the root is
/// responsible for sizing/positioning that parent to match the screen it is spotlighting
/// and for supplying `target` in that same coordinate space.
///
/// - No target (`target == nil`, or a rect that fails geometry validation) shows a
///   small, unobtrusive "Preparing this view…" badge instead of any tappable fallback.
/// - Taps outside the target are swallowed by a non-accessible scrim: this is a
///   controlled guided preview, not free exploration of the real screen underneath.
/// - Honours Reduce Motion: the tap cue is static, no pulse animation, when enabled.
/// - `isInteractive` (default `true`) distinguishes a real-control lesson from a purely
///   informational highlight. When `false` the spotlight only dims and borders the real
///   control, with no hand/tap cue and no `tour.tapTarget` button; instead it exposes a
///   non-hidden `tour.highlight` accessibility element at the exact validated target
///   geometry (label "Highlighted area: " + actionTitle), so tests can assert real
///   target geometry for read-only lessons too. The root's own Next control is what
///   advances a read-only highlight step.
struct FleetGuidedSpotlight: View {
    let target: CGRect?
    let actionTitle: String
    var isInteractive: Bool = true
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let cornerRadius: CGFloat = 16
    private let outset = FleetTourGeometry.highlightOutset

    var body: some View {
        GeometryReader { proxy in
            let bounds = CGRect(origin: .zero, size: proxy.size)
            let visible = target.flatMap { FleetTourGeometry.clippedTarget($0, outset: outset, in: bounds) }

            ZStack {
                scrim(hole: visible, in: bounds)

                if let rect = visible {
                    spotlightBorder(rect)
                    if isInteractive {
                        tapCue(rect)
                        targetButton(rect)
                    } else {
                        highlightElement(rect)
                    }
                } else {
                    preparingBadge(in: bounds)
                }
            }
            .frame(width: bounds.width, height: bounds.height)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tour.spotlight")
    }

    // MARK: Scrim

    /// One shape, even-odd filled, so the dim layer and its cut-out hole can never
    /// disagree about where taps land. Not exposed to VoiceOver: it adds no real
    /// content, it only withholds taps from the rest of the real screen underneath.
    private func scrim(hole: CGRect?, in bounds: CGRect) -> some View {
        Path { path in
            path.addRect(bounds)
            if let rect = hole {
                path.addRoundedRect(in: rect, cornerSize: CGSize(width: cornerRadius, height: cornerRadius))
            }
        }
        .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
        .contentShape(Rectangle())
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func spotlightBorder(_ rect: CGRect) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(FleetTheme.accent, lineWidth: 3)
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// A small hand/tap glyph, no external assets. Pulses gently unless Reduce Motion
    /// is on, in which case it stays put as a static cue.
    private func tapCue(_ rect: CGRect) -> some View {
        Image(systemName: "hand.tap.fill")
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(FleetTheme.charcoal)
            .padding(6)
            .background(FleetTheme.accent, in: Circle())
            .overlay(Circle().strokeBorder(FleetTheme.canvas, lineWidth: 1.5))
            .position(x: rect.maxX, y: rect.minY)
            .modifier(FleetTourCuePulse(reduceMotion: reduceMotion))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// The only tappable surface this overlay exposes. Sized and positioned to the
    /// clipped, on-screen portion of the real target's measured rect, never the full
    /// unclipped anchor.
    private func targetButton(_ rect: CGRect) -> some View {
        Button(action: action) {
            Rectangle().fill(Color.white.opacity(0.001))
                .frame(width: rect.width, height: rect.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(false)
        .allowsHitTesting(true)
        .position(x: rect.midX, y: rect.midY)
        .accessibilityIdentifier("tour.tapTarget")
        .accessibilityLabel(actionTitle)
    }

    /// The read-only counterpart of `targetButton`: an informational step exposes no
    /// button (nothing to tap, the root's own Next control advances the tour), but it
    /// does expose the exact, validated on-screen target geometry as a non-hidden
    /// accessibility element so tests can assert real target geometry for read-only
    /// lessons too, not just tappable ones.
    private func highlightElement(_ rect: CGRect) -> some View {
        Color.clear
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("tour.highlight")
            .accessibilityLabel("Highlighted area: \(actionTitle)")
    }

    private func preparingBadge(in bounds: CGRect) -> some View {
        Text("Preparing this view…")
            .fleetFont(.subheadline, weight: .semibold)
            .foregroundStyle(FleetTheme.panelInk)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(FleetTheme.soloSurface.opacity(0.95), in: Capsule())
            .position(x: bounds.midX, y: bounds.midY)
            .accessibilityIdentifier("tour.preparing")
            .accessibilityLabel("Preparing this view…")
    }
}

private struct FleetTourCuePulse: ViewModifier {
    let reduceMotion: Bool
    @State private var pulsing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(pulsing ? 1.12 : 1.0)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    pulsing = true
                }
            }
    }
}

#Preview("Spotlight on a target") {
    ZStack {
        FleetTheme.canvas
        VStack {
            Text("Real screen content behind the spotlight")
            Spacer()
        }
        .padding()
        FleetGuidedSpotlight(target: CGRect(x: 40, y: 120, width: 220, height: 48),
                             actionTitle: "Open Fleet",
                             action: {})
    }
}

#Preview("Preparing state") {
    ZStack {
        FleetTheme.canvas
        FleetGuidedSpotlight(target: nil, actionTitle: "Open Fleet", action: {})
    }
}

#Preview("Read-only highlight, no tap") {
    ZStack {
        FleetTheme.canvas
        VStack {
            Text("Real screen content behind the spotlight")
            Spacer()
        }
        .padding()
        FleetGuidedSpotlight(target: CGRect(x: 40, y: 120, width: 220, height: 48),
                             actionTitle: "Hashrate reading",
                             isInteractive: false,
                             action: {})
    }
}

/// Scrolls the measured target itself, not a guessed offset, within its actual UIKit scroll host.
#if canImport(UIKit)
private struct FleetGuidedScrollMarker: UIViewRepresentable {
    func makeUIView(context: Context) -> Marker { Marker() }
    func updateUIView(_ view: Marker, context: Context) { view.scheduleReveal() }
    final class Marker: UIView {
        private var revealTask: Task<Void, Never>?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil { scheduleReveal() } else { revealTask?.cancel() }
        }
        func scheduleReveal() {
            guard window != nil, revealTask == nil else { return }
            revealTask = Task { @MainActor [weak self] in
                for _ in 0..<4 {
                    try? await Task.sleep(for: .milliseconds(200))
                    guard !Task.isCancelled, let self, self.window != nil else { return }
                    var ancestor = self.superview
                    while let view = ancestor {
                        if let scroll = view as? UIScrollView {
                            var rect = self.convert(self.bounds, to: scroll).insetBy(dx: 0, dy: -12)
                            // At large text sizes a card may exceed the viewport. Reveal its
                            // heading and first reading, rather than scrolling to its bottom.
                            rect.size.height = min(rect.height, max(1, scroll.bounds.height - 24))
                            if rect.width > 0 && rect.height > 0 { scroll.scrollRectToVisible(rect, animated: false) }
                            break
                        }
                        ancestor = view.superview
                    }
                }
            }
        }
    }
}
#else
/// The native tour reveals the measured target through its actual AppKit scroll hierarchy.
private struct FleetGuidedScrollMarker: NSViewRepresentable {
    func makeNSView(context: Context) -> Marker { Marker() }
    func updateNSView(_ view: Marker, context: Context) { view.scheduleReveal() }

    final class Marker: NSView {
        private var revealTask: Task<Void, Never>?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil { scheduleReveal() } else { revealTask?.cancel(); revealTask = nil }
        }

        func scheduleReveal() {
            guard window != nil, revealTask == nil else { return }
            revealTask = Task { @MainActor [weak self] in
                defer { self?.revealTask = nil }
                for _ in 0..<4 {
                    do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
                    guard let self, self.window != nil,
                          let scroll = self.enclosingScrollView,
                          let document = scroll.documentView else { return }
                    var rect = self.convert(self.bounds, to: document).insetBy(dx: 0, dy: -12)
                    rect.size.height = min(rect.height, max(1, scroll.contentView.bounds.height - 24))
                    if rect.width > 0, rect.height > 0 { document.scrollToVisible(rect) }
                }
            }
        }
    }
}
#endif
