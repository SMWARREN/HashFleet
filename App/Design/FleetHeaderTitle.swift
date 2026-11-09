import SwiftUI

/// The original iPad wordmark. Native chrome reuses the view, not a smaller
/// platform title or a separately approximated font recipe.
struct FleetHeaderTitle: View {
    var body: some View {
        Text("Hash Fleet")
            .fleetFont(.headline)
            .lineLimit(1)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            #if os(iOS)
            .accessibilityShowsLargeContentViewer { Text("Hash Fleet") }
            #endif
    }
}
