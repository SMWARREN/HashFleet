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
            .fleetEditingScroll()
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
            .fleetEditingScroll()
            .fleetReadableForm()
        #endif
    }
}

extension View {
    /// Let the system resize the scrollable viewport for the keyboard. An upward scroll can
    /// reveal more of the form without forcing a dismissal, and dragging down can dismiss it.
    @ViewBuilder func fleetEditingScroll() -> some View {
        #if os(iOS)
        scrollDismissesKeyboard(.interactively)
        #else
        self
        #endif
    }

    /// Reveal the entire focused box, not just the caret. The caller sets the same ID on the
    /// field (or on its containing form row) so grouped Forms and ScrollViews keep native layout.
    @ViewBuilder func fleetRevealEditingField<ID: Hashable>(_ field: ID?) -> some View {
        #if os(iOS)
        ScrollViewReader { proxy in fleetRevealEditingField(field, using: proxy) }
        #else
        self
        #endif
    }

    @ViewBuilder func fleetRevealEditingField<ID: Hashable>(
        _ field: ID?, using proxy: ScrollViewProxy
    ) -> some View {
        #if os(iOS)
        modifier(FleetEditingFieldReveal(field: field, proxy: proxy))
        #else
        self
        #endif
    }

    /// A full-height multiline box can be taller than a landscape editing viewport.
    /// Shorten only the focused editor in that layout; the text inside remains scrollable.
    @ViewBuilder func fleetMultilineInputHeight(_ height: CGFloat, editing: Bool) -> some View {
        #if os(iOS)
        modifier(FleetMultilineInputHeight(height: height, editing: editing))
        #else
        frame(minHeight: height)
        #endif
    }

    /// Numeric pads and multiline editors don't have a Return key that ends editing.
    /// Keep Done above the form, not in a second bar taking space above the keyboard.
    @ViewBuilder func fleetEditingDone(
        _ isEditing: Bool, identifier: String, action: @escaping () -> Void
    ) -> some View {
        #if os(iOS)
        toolbar {
            if isEditing && !FleetLayout.isMac {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: action)
                        .accessibilityHint("Dismisses the keyboard without submitting")
                        .accessibilityIdentifier(identifier)
                }
            }
        }
        #else
        self
        #endif
    }
}

#if os(iOS)
private struct FleetEditingFieldReveal<ID: Hashable>: ViewModifier {
    let field: ID?
    let proxy: ScrollViewProxy
    @State private var viewport: CGSize?

    func body(content: Content) -> some View {
        content
            .safeAreaPadding(.bottom, field == nil ? 0 : 16)
            .onChange(of: field) { _, field in
                if let field { proxy.scrollTo(field, anchor: .center) }
            }
            .onGeometryChange(for: CGSize.self) { geometry in
                CGSize(width: geometry.size.width, height: geometry.size.height - geometry.safeAreaInsets.bottom)
            } action: { new in
                let old = viewport
                viewport = new
                // The keyboard may arrive after focus changes. Do not drive the scroll during
                // dismissal, when the view grows and the user's downward drag owns the offset.
                guard let old, new.height > 0, new.height < old.height || new.width != old.width,
                      let field else { return }
                proxy.scrollTo(field, anchor: .center)
            }
    }
}

private struct FleetMultilineInputHeight: ViewModifier {
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    let height: CGFloat
    let editing: Bool

    func body(content: Content) -> some View {
        let compactHeight: CGFloat? = editing && verticalSizeClass == .compact ? min(height, 72) : nil
        content.frame(minHeight: compactHeight ?? height, maxHeight: compactHeight)
    }
}
#endif

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
