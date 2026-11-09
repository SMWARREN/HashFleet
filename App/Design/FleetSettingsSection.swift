import SwiftUI

/// Shared, static introduction for informational settings pages. Artwork never
/// dictates the text height, and long copy grows instead of compressing or scaling.
struct FleetSettingsIntroduction<Icon: View>: View {
    let title: String
    let message: String
    let identifier: String
    @ViewBuilder var icon: Icon

    var body: some View {
        FleetSettingsSection {
            FleetSettingsRow(showsSeparator: false) {
                VStack(alignment: .leading, spacing: 12) {
                    icon
                    Text(title)
                        .fleetFont(.title2, weight: .bold)
                        .foregroundStyle(FleetTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(message)
                        .fleetFont(.body)
                        .foregroundStyle(FleetTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(identifier)
            }
        }
        .fleetSectionFullWidth()
    }
}

private struct FleetSettingsIsFormKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var fleetSettingsIsForm: Bool {
        get { self[FleetSettingsIsFormKey.self] }
        set { self[FleetSettingsIsFormKey.self] = newValue }
    }
}

/// A settings group whose palette and surface do not depend on the platform's native
/// Form/List chrome. iOS keeps native Section/List semantics but gives each row its
/// own rounded surface. Native macOS draws the content on one shared section surface.
struct FleetSettingsSection<Content: View>: View {
    @Environment(\.fleetSettingsIsForm) private var isForm
    private let title: String?
    private let header: AnyView?
    private let footer: AnyView?
    private let surface: Color?
    private let contentInsets: EdgeInsets
    private let listRowInsets: EdgeInsets?
    private let hidesListRowSeparators: Bool
    private let content: Content

    init(
        _ title: String? = nil,
        footer: String? = nil,
        surface: Color? = FleetTheme.surface,
        contentInsets: EdgeInsets = EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16),
        listRowInsets: EdgeInsets? = nil,
        hidesListRowSeparators: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.header = nil
        self.footer = footer.map { AnyView(Text($0)) }
        self.surface = surface
        self.contentInsets = contentInsets
        self.listRowInsets = listRowInsets
        self.hidesListRowSeparators = hidesListRowSeparators
        self.content = content()
    }

    init(
        header: AnyView?,
        footer: AnyView? = nil,
        surface: Color? = FleetTheme.surface,
        contentInsets: EdgeInsets = EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16),
        listRowInsets: EdgeInsets? = nil,
        hidesListRowSeparators: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.title = nil
        self.header = header
        self.footer = footer
        self.surface = surface
        self.contentInsets = contentInsets
        self.listRowInsets = listRowInsets
        self.hidesListRowSeparators = hidesListRowSeparators
        self.content = content()
    }

    init(
        @ViewBuilder content: () -> Content,
        @ViewBuilder header: () -> some View,
        @ViewBuilder footer: () -> some View = { EmptyView() },
        surface: Color? = FleetTheme.surface,
        contentInsets: EdgeInsets = EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16),
        listRowInsets: EdgeInsets? = nil,
        hidesListRowSeparators: Bool = true
    ) {
        self.title = nil
        self.header = AnyView(header())
        self.footer = AnyView(footer())
        self.surface = surface
        self.contentInsets = contentInsets
        self.listRowInsets = listRowInsets
        self.hidesListRowSeparators = hidesListRowSeparators
        self.content = content()
    }

    var body: some View {
        #if os(macOS)
        FleetSectionChromeLayout {
            VStack(alignment: .leading, spacing: 0) {
                if let title {
                    Text(title)
                        .fleetFont(.headline)
                        .foregroundStyle(FleetTheme.ink)
                        .padding(.horizontal, 16)
                        .accessibilityAddTraits(.isHeader)
                } else if let header {
                    header
                        .fleetFont(.headline)
                        .foregroundStyle(FleetTheme.ink)
                        .padding(.horizontal, 16)
                        .accessibilityAddTraits(.isHeader)
                }
            }

            VStack(alignment: .leading, spacing: isForm ? 8 : 0) {
                content
            }
            .padding(contentInsets)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                if let surface {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(surface)
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                if let footer {
                    footer
                        .fleetFont(.footnote)
                        .foregroundStyle(FleetTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 16)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .layoutValue(key: FleetSectionSurfaceKey.self, value: surface != nil)
        .layoutValue(key: FleetSectionAutomaticFullWidthKey.self, value: surface == nil)
        #else
        Section {
            content
        } header: {
            if let title {
                Text(title)
                    .fleetFont(.headline)
                    .foregroundStyle(FleetTheme.ink)
            } else if let header {
                header
                    .fleetFont(.headline)
                    .foregroundStyle(FleetTheme.ink)
            }
        } footer: {
            if let footer {
                footer
            }
        }
        .listRowBackground(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(surface ?? Color.clear)
        )
        .listSectionSeparator(.hidden)
        .modifier(FleetSettingsListRowModifiers(
            insets: listRowInsets ?? contentInsets,
            hidesSeparators: hidesListRowSeparators
        ))
        #endif
    }

    /// Native cards own an accessibility group. An iOS Section does not, so
    /// applying its identifier would replace the identifiers of every child row.
    /// Keep the native geometry anchor without hiding iPad control identities.
    @ViewBuilder
    func fleetSettingsSectionIdentifier(_ identifier: String) -> some View {
        #if os(macOS)
        self.accessibilityIdentifier(identifier)
        #else
        self
        #endif
    }
}

/// Gives native controls the same minimum touch height as the iPad settings rows.
/// The iOS branch returns the original control unchanged inside its existing List/Form.
struct FleetSettingsRow<Content: View>: View {
    @Environment(\.fleetSettingsIsForm) private var isForm
    private let content: Content
    private let showsSeparator: Bool

    init(showsSeparator: Bool = true, @ViewBuilder content: () -> Content) {
        self.showsSeparator = showsSeparator
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
        #if os(macOS)
        VStack(spacing: showsSeparator ? FleetSettingsSeparator.clearance : 0) {
            content
                .padding(.vertical, isForm ? 0 : 8)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            if showsSeparator {
                FleetSettingsSeparator()
            }
        }
        #else
        content
        #endif
    }
}

#if os(macOS)
/// A separator is outside the preceding control's hit region, never an overlay on its edge.
struct FleetSettingsSeparator: View {
    static let clearance: CGFloat = 8

    var body: some View {
        FleetTheme.separator
            .frame(height: 0.5)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
#endif

private struct FleetSettingsListRowModifiers: ViewModifier {
    let insets: EdgeInsets?
    let hidesSeparators: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if let insets {
            content
                .listRowInsets(insets)
                .listRowSeparator(hidesSeparators ? .hidden : .visible)
        } else {
            content.listRowSeparator(hidesSeparators ? .hidden : .visible)
        }
    }
}
