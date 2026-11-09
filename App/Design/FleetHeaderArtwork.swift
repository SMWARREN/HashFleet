import SwiftUI

/// Keep the original leading artwork separate from the centered app title.
struct FleetHeaderArtwork: View {
    #if os(macOS)
    private let artworkSize: CGFloat = 44
    #else
    private let artworkSize: CGFloat = 34
    #endif

    var body: some View {
        Image("HashFleetHeader")
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(width: artworkSize, height: artworkSize)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityHidden(true)
    }
}
