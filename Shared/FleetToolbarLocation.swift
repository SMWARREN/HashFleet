import SwiftUI

/// Shared screens keep real native toolbars without asking AppKit for an iOS navigation bar.
enum FleetToolbarLocation {
    static var leading: ToolbarItemPlacement {
        #if os(macOS)
        .navigation
        #else
        .topBarLeading
        #endif
    }

    static var trailing: ToolbarItemPlacement {
        #if os(macOS)
        .primaryAction
        #else
        .topBarTrailing
        #endif
    }

    static var bar: ToolbarPlacement {
        #if os(macOS)
        .windowToolbar
        #else
        .navigationBar
        #endif
    }

    static var search: SearchFieldPlacement {
        #if os(macOS)
        .toolbar
        #else
        .navigationBarDrawer(displayMode: .always)
        #endif
    }
}

extension View {
    @ViewBuilder
    func fleetWindowToolbarChrome() -> some View {
        #if os(macOS)
        if #available(macOS 15.0, *) {
            self
                .toolbarBackground(FleetMacChrome.background, for: .windowToolbar)
                .toolbarBackground(.visible, for: .windowToolbar)
                .windowToolbarFullScreenVisibility(.visible)
        } else {
            self
                .toolbarBackground(FleetMacChrome.background, for: .windowToolbar)
                .toolbarBackground(.visible, for: .windowToolbar)
        }
        #else
        self
        #endif
    }

    @ViewBuilder
    func fleetToolbarButton() -> some View {
        #if os(macOS)
        self.buttonStyle(FleetMacToolbarButtonStyle()).labelStyle(.iconOnly)
        #else
        self
        #endif
    }

    @ViewBuilder
    func fleetToolbarMenu() -> some View {
        #if os(macOS)
        self.menuStyle(.button)
            .buttonStyle(FleetMacToolbarButtonStyle())
            .menuIndicator(.hidden)
            .labelStyle(.iconOnly)
        #else
        self
        #endif
    }
}

extension ToolbarContent {
    /// Branding and a plain title are not toolbar buttons. Keep the shared artwork and
    /// typography without adding a second, platform-generated rounded glass surround.
    /// Explicitly styled controls use this too, avoiding a second system glass pill.
    @ToolbarContentBuilder
    func fleetUnadornedToolbarBackground() -> some ToolbarContent {
        #if os(macOS)
        if #available(macOS 26.0, *) {
            self.sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
        #else
        self
        #endif
    }

    @ToolbarContentBuilder
    func fleetPersistentToolbarItem() -> some ToolbarContent {
        #if os(macOS)
        if #available(macOS 26.1, *) {
            self.visibilityPriority(.high)
        } else {
            self
        }
        #else
        self
        #endif
    }
}
