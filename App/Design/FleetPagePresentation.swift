import SwiftUI
#if os(iOS)
import UIKit
#endif

private struct FleetFullWindowPresentationKey: EnvironmentKey {
    static let defaultValue = false
}

/// Guided screens render real content, but their unreachable destinations and window chrome
/// must not compete with the native workspace that owns the tour. iOS keeps its own preview stack.
#if os(macOS)
private struct FleetAppNavigation<Decorated: View>: View {
    @Environment(\.fleetGuidedDemo) private var guidedDemo
    // Erase only the native base at this boundary. Repeating the entire growing Self
    // in both branches of every decorator otherwise causes exponential generic lowering.
    let base: AnyView
    let decorate: (AnyView) -> Decorated

    @ViewBuilder var body: some View {
        if guidedDemo {
            base
        } else {
            decorate(base)
        }
    }
}
#endif

extension EnvironmentValues {
    var fleetFullWindowPresentation: Bool {
        get { self[FleetFullWindowPresentationKey.self] }
        set { self[FleetFullWindowPresentationKey.self] = newValue }
    }
}

/// Policy for app-owned pages. iPhone keeps its compact sheet presentation;
/// iPad and native Mac use the owning navigation stack.
enum FleetPagePresentationPolicy {
    static func usesInAppNavigation(isPhone: Bool, forMac: Bool) -> Bool {
        forMac || !isPhone
    }

    @MainActor static var usesInAppPages: Bool {
        #if os(macOS)
        true
        #elseif os(iOS)
        usesInAppNavigation(
            isPhone: UIDevice.current.userInterfaceIdiom == .phone,
            forMac: FleetLayout.isMac
        )
        #else
        false
        #endif
    }
}

/// Use the existing navigation stack for iPad/Mac page content, while giving
/// compact iPhone roots their own stack when one is not already supplied.
struct FleetPageNavigationStack<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        if FleetPagePresentationPolicy.usesInAppPages {
            content
        } else {
            NavigationStack { content }
        }
    }
}

private struct FleetItemPageNavigationModifier<Item: Identifiable, Page: View>: ViewModifier {
    @Binding var item: Item?
    let onDismiss: (() -> Void)?
    let destinationContent: (Item) -> Page
    @State private var retainedDestinationItem: Item?

    init(
        item: Binding<Item?>,
        onDismiss: (() -> Void)?,
        destinationContent: @escaping (Item) -> Page
    ) {
        self._item = item
        self.onDismiss = onDismiss
        self.destinationContent = destinationContent
    }

    func body(content base: Content) -> some View {
        let isPresented = Binding<Bool>(
            get: { item != nil },
            set: { presented in
                if presented {
                    retainedDestinationItem = item
                } else {
                    item = nil
                }
            }
        )

        base
            .navigationDestination(isPresented: isPresented) {
                if let value = item ?? retainedDestinationItem {
                    destinationContent(value)
                        .environment(\.fleetFullWindowPresentation, true)
                        .environment(\.fleetStandalonePage, false)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onDisappear {
                            // A nested push or canceled interactive pop can also make the
                            // destination disappear while its source item is still present.
                            // Keep that payload until the binding is nil and this destination
                            // actually leaves the navigation stack.
                            guard item?.id == nil,
                                  retainedDestinationItem?.id == value.id else { return }
                            retainedDestinationItem = nil
                        }
                } else {
                    EmptyView()
                }
            }
            .onChange(of: item?.id) { previousID, currentID in
                if let item {
                    retainedDestinationItem = item
                }
                if previousID != nil && currentID == nil {
                    onDismiss?()
                }
            }
    }
}

extension View {
    #if os(macOS)
    func fleetAppNavigation<Decorated: View>(
        @ViewBuilder _ decorate: @escaping (AnyView) -> Decorated
    ) -> some View {
        FleetAppNavigation(base: AnyView(self), decorate: decorate)
    }
    #else
    func fleetAppNavigation<Decorated: View>(
        @ViewBuilder _ decorate: (AnyView) -> Decorated
    ) -> some View {
        decorate(AnyView(self))
    }
    #endif

    @ViewBuilder
    func fleetPagePresentation<Page: View>(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Page
    ) -> some View {
        fleetAppNavigation { base in
            if FleetPagePresentationPolicy.usesInAppPages {
                base.navigationDestination(isPresented: isPresented) {
                    content()
                        .environment(\.fleetFullWindowPresentation, true)
                        .environment(\.fleetStandalonePage, false)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .onChange(of: isPresented.wrappedValue) { wasPresented, isPresented in
                    if wasPresented && !isPresented {
                        onDismiss?()
                    }
                }
            } else {
                base.sheet(isPresented: isPresented, onDismiss: onDismiss, content: content)
            }
        }
    }

    @ViewBuilder
    func fleetPagePresentation<Item: Identifiable, Page: View>(
        item: Binding<Item?>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> Page
    ) -> some View {
        fleetAppNavigation { base in
            if FleetPagePresentationPolicy.usesInAppPages {
                base.modifier(FleetItemPageNavigationModifier(
                    item: item,
                    onDismiss: onDismiss,
                    destinationContent: content
                ))
            } else {
                base.sheet(item: item, onDismiss: onDismiss, content: content)
            }
        }
    }
}
