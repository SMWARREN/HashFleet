import SwiftUI

/// Keep the same semantic sections on both platforms. A native Mac List is an outline,
/// not the rounded, grouped settings surface used by the iPad app.
struct FleetSettingsList<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        #if os(macOS)
        FleetSettingsColumn { content }
        #else
        List { content }
            .listStyle(.insetGrouped)
            .listRowSpacing(12)
            .fleetReadableForm()
        #endif
    }
}

/// Scrollable container for settings that are expressed as explicit Fleet surfaces.
/// iOS retains its native Form, while macOS avoids AppKit's unrelated grouped-form chrome.
struct FleetSettingsForm<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        #if os(macOS)
        FleetSettingsColumn { content }
            .environment(\.fleetSettingsIsForm, true)
        #else
        Form { content }
            .listRowSpacing(12)
            .fleetReadableForm()
        #endif
    }
}

#if os(macOS)
private struct FleetSettingsColumn<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            FleetSectionGrid(spacing: FleetLayout.sectionSpacing, minimumRows: 2) {
                content
            }
            .fleetPageContainer()
        }
        .scrollIndicators(.visible)
        .fleetFont(.body)
        .labeledContentStyle(FleetSettingsValueStyle())
        .buttonStyle(FleetSettingsActionStyle())
        .toggleStyle(FleetSettingsSwitchStyle())
    }
}
#endif
