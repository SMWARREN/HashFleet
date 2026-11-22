import SwiftUI

#if canImport(UIKit)
import UIKit

/// A scene-owned, non-key window keeps alerts above sheets and pushed screens. Empty space
/// passes through to the app. Only a full-screen record ends editing in the presenting scene.
struct FleetNotificationWindowHost<Content: View>: UIViewRepresentable {
    let isEnabled: Bool
    let capturesAllTouches: Bool
    @ViewBuilder let content: () -> Content

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> FleetNotificationSceneAnchor {
        let anchor = FleetNotificationSceneAnchor()
        anchor.isUserInteractionEnabled = false
        anchor.onWindowChanged = { [weak coordinator = context.coordinator, weak anchor] in
            guard let anchor else { return }
            coordinator?.attach(to: anchor.window?.windowScene)
        }
        return anchor
    }

    func updateUIView(_ anchor: FleetNotificationSceneAnchor, context: Context) {
        context.coordinator.update(content: AnyView(content()), isEnabled: isEnabled, capturesAllTouches: capturesAllTouches)
        context.coordinator.attach(to: anchor.window?.windowScene)
    }

    static func dismantleUIView(_ anchor: FleetNotificationSceneAnchor, coordinator: Coordinator) {
        anchor.onWindowChanged = nil
        coordinator.detach()
    }

    @MainActor
    final class Coordinator {
        private(set) var window: FleetNotificationWindow?
        private var content = AnyView(EmptyView())
        private var isEnabled = false
        private var capturesAllTouches = false

        func update(content: AnyView, isEnabled: Bool, capturesAllTouches: Bool) {
            self.content = content
            self.isEnabled = isEnabled
            self.capturesAllTouches = capturesAllTouches
            updateWindow()
        }

        func attach(to scene: UIWindowScene?) {
            guard let scene else { detach(); return }
            if window?.windowScene !== scene {
                detach()
                let window = FleetNotificationWindow(windowScene: scene)
                window.windowLevel = .alert + 1
                window.backgroundColor = .clear
                self.window = window
            }
            updateWindow()
        }

        private func updateWindow() {
            guard let window else { return }
            let isModal = isEnabled && capturesAllTouches
            let opensModal = isModal && (window.isHidden || !window.capturesAllTouches)
            let root = AnyView(
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .coordinateSpace(name: FleetNotificationHitRegions.coordinateSpace)
                    .onPreferenceChange(FleetNotificationHitRegions.self) { [weak window] regions in
                        guard let window else { return }
                        window.updateInteractiveRegions(regions, contentInsets: window.safeAreaInsets)
                    }
            )
            if let host = window.rootViewController as? UIHostingController<AnyView> {
                host.rootView = root
            } else {
                let host = UIHostingController(rootView: root)
                host.view.backgroundColor = .clear
                window.rootViewController = host
            }
            window.capturesAllTouches = isModal
            window.rootViewController?.view.accessibilityViewIsModal = isModal
            window.isHidden = !isEnabled
            FleetInAppSurface.celebrationVisible = isModal
            if opensModal {
                // Keep the overlay non-key and clear the existing responder, not the form or sheet.
                // Wait one MainActor turn so focus updates do not occur during updateUIView.
                Task { @MainActor [weak window] in
                    guard let window, !window.isHidden, window.capturesAllTouches else { return }
                    window.windowScene?.keyWindow?.endEditing(true)
                }
            }
        }

        func detach() {
            FleetInAppSurface.celebrationVisible = false
            window?.isHidden = true
            window?.rootViewController = nil
            window?.windowScene = nil
            window = nil
        }
    }

}

final class FleetNotificationSceneAnchor: UIView {
    var onWindowChanged: (() -> Void)?
    override func didMoveToWindow() {
        super.didMoveToWindow()
        onWindowChanged?()
    }
}

#elseif canImport(AppKit)
/// Native macOS uses an in-window SwiftUI overlay instead of creating a second UIKit window.
/// Full-screen celebration content supplies its own backdrop and dismissal hit area. Inline banners
/// keep their natural hit area so unrelated controls remain usable beneath the overlay.
struct FleetNotificationWindowHost<Content: View>: View {
    let isEnabled: Bool
    let capturesAllTouches: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        Group {
            if isEnabled {
                if capturesAllTouches {
                    content().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    content().frame(maxWidth: .infinity, alignment: .top)
                }
            }
        }
        .allowsHitTesting(isEnabled)
        .accessibilityHidden(!isEnabled)
    }
}
#endif
