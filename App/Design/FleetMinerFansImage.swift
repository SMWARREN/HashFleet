import SwiftUI

/// ASIC cooling fans in transparent graphite-and-gold artwork.
/// The onboarding card sits on `FleetTheme.charcoal`, which is 0x111111 in both light and
/// dark mode, so this graphic is intentionally appearance-independent: one master at 1x, 2x,
/// and 3x for the 96-point onboarding graphic. Do not add a light variant that can never render.
struct FleetMinerFansImage: View {
    var size: CGFloat = 96

    var body: some View {
        Image("MinerFans", bundle: nil)
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

#Preview("Dark") {
    FleetMinerFansImage()
        .padding()
        .background(FleetTheme.charcoal)
        .padding()
        .background(FleetTheme.canvas)
        .environment(\.colorScheme, .dark)
}

#Preview("Light") {
    FleetMinerFansImage()
        .padding()
        .background(FleetTheme.charcoal)
        .padding()
        .background(FleetTheme.canvas)
        .environment(\.colorScheme, .light)
}
