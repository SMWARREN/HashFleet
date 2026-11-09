import SwiftUI

#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
import UniformTypeIdentifiers

/// A local, opt-in reveal control for one row. This is not app-wide masking or screenshot prevention.
/// The raw value is never inserted into the visible or accessibility tree while the row is masked.
struct FleetSensitiveValue: View {
    let title: String
    let value: String
    let identifier: String
    @Environment(\.scenePhase) private var scenePhase
    @State private var disclosure = FleetSensitiveValueDisclosure()
    @State private var didCopy = false

    private var visibleValue: String? {
        disclosure.visibleValue(for: value, isActive: scenePhase == .active)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title).foregroundStyle(FleetTheme.secondary)
                Spacer(minLength: 8)
                if let visibleValue {
                    Text(visibleValue.isEmpty ? "Not provided" : visibleValue)
                        .multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("\(identifier).value")
                } else {
                    Text("Hidden")
                        .foregroundStyle(FleetTheme.secondary)
                        .accessibilityLabel("\(title), Hidden")
                        .accessibilityIdentifier("\(identifier).masked")
                }
            }
            .fleetFont(.subheadline)

            HStack(spacing: 16) {
                if visibleValue != nil {
                    Button("Hide", systemImage: "eye.slash", action: hide)
                        .accessibilityLabel("Hide \(title)")
                        .accessibilityIdentifier("\(identifier).hide")
                    Button(didCopy ? "Copied" : "Copy", systemImage: "doc.on.doc", action: copy)
                        .disabled(value.isEmpty)
                        .accessibilityLabel(didCopy ? "\(title) copied" : "Copy \(title)")
                        .accessibilityHint("Copies to this device's clipboard for two minutes.")
                        .accessibilityIdentifier("\(identifier).copy")
                } else {
                    Button("Reveal", systemImage: "eye") {
                        disclosure.reveal(value, isActive: scenePhase == .active)
                        didCopy = false
                    }
                    .accessibilityLabel("Reveal \(title)")
                    .accessibilityHint("Shows this value in this row until hidden or you leave the screen.")
                    .accessibilityIdentifier("\(identifier).reveal")
                }
            }
            .fleetFont(.caption, weight: .semibold)
            .buttonStyle(.borderless)
            .tint(FleetTheme.accent)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { hide() }
        }
        .onChange(of: value) { _, _ in hide() }
        .onDisappear(perform: hide)
    }

    private func hide() {
        disclosure.hide()
        didCopy = false
    }

    private func copy() {
        didCopy = disclosure.copy(value, isActive: scenePhase == .active) { text in
#if canImport(UIKit)
            UIPasteboard.general.setItems(
                [[UTType.utf8PlainText.identifier: text]],
                options: [.localOnly: true, .expirationDate: Date.now.addingTimeInterval(120)]
            )
#else
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
#endif
        }
    }
}

/// Pure policy shared by the render and copy paths. Reveal authorizes exactly one value, so a row
/// reused for a different device cannot briefly expose the new address before onChange runs.
struct FleetSensitiveValueDisclosure: Equatable, Sendable {
    private var revealedValue: String?

    mutating func reveal(_ value: String, isActive: Bool) {
        revealedValue = isActive ? value : nil
    }

    mutating func hide() {
        revealedValue = nil
    }

    func visibleValue(for value: String, isActive: Bool) -> String? {
        guard isActive, revealedValue == value else { return nil }
        return value
    }

    @discardableResult
    func copy(_ value: String, isActive: Bool, write: (String) -> Void) -> Bool {
        guard let visible = visibleValue(for: value, isActive: isActive), !visible.isEmpty else { return false }
        write(visible)
        return true
    }
}
