import SwiftUI
import HashFleetCore

/// Reusable layout-stable neutral skeleton placeholder elements for HashFleet.
///
/// Designed to maintain layout dimensions during initial asynchronous fetches
/// without layout shifting, fake zero values, or unnecessary timer-driven redraws.
/// A soft light band (adapted from ShipSwift `SWShimmer`) sweeps only while the placeholder is
/// on screen. Skeletons exist only before the first reading, so the animation ends when data
/// arrives and the placeholder is removed. Loaded screens never shimmer. Reduce Motion, or
/// `shimmers: false`, keeps the plain static block.
/// Supports VoiceOver with honest "Loading" accessibility label.
struct FleetLoadingSkeleton: View {
    var width: CGFloat?
    var height: CGFloat = 16
    var cornerRadius: CGFloat = 4
    var label: String = "Loading"
    var tint: Color = FleetTheme.secondary.opacity(0.18)
    var shimmers = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape
            .fill(tint)
            .frame(width: width, height: height)
            .overlay {
                if shimmers && !reduceMotion {
                    FleetShimmerBand().clipShape(shape)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
    }
}

/// One soft band sweeping left to right with a short pause. A single repeating offset
/// animation, no timeline or per-frame view rebuilds.
private struct FleetShimmerBand: View {
    @State private var phase: CGFloat = -1

    var body: some View {
        GeometryReader { geometry in
            let band = max(geometry.size.width * 0.6, 24)
            LinearGradient(
                colors: [.clear, .white.opacity(0.28), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: band, height: geometry.size.height)
            .offset(x: -band + (phase + 1) / 2 * (geometry.size.width + band))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.3).delay(0.5).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
    }
}

/// Shared first-load policy. Existing and cached data always win over placeholders.
enum MinerLoadingPolicy {
    static func shouldShowSkeleton(info: MinerInfo?, error: String?, isDemo: Bool) -> Bool {
        !isDemo && info == nil && error == nil
    }
}
