import SwiftUI

/// Keeps a settings value picker in the same label/value row on both platforms.
/// Native popup-button chrome is not part of the shared card design.
struct FleetSettingsPicker<Value: Hashable, Options: View>: View {
    let title: String
    let valueTitle: String
    let valueColor: Color
    @Binding var selection: Value
    private let options: Options

    init(
        _ title: String,
        valueTitle: String,
        selection: Binding<Value>,
        valueColor: Color = FleetTheme.secondary,
        @ViewBuilder options: () -> Options
    ) {
        self.title = title
        self.valueTitle = valueTitle
        self.valueColor = valueColor
        _selection = selection
        self.options = options()
    }

    var body: some View {
        #if os(macOS)
        HStack(spacing: 12) {
            Text(title).foregroundStyle(FleetTheme.ink)
            Spacer(minLength: 8)
            Menu {
                Picker(title, selection: $selection) { options }
            } label: {
                HStack(spacing: 8) {
                    Text(valueTitle).foregroundStyle(valueColor)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(valueColor)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .fleetDesignedMenu()
            .accessibilityLabel(title)
            .accessibilityValue(valueTitle)
        }
        .fleetFont(.body)
        #else
        Picker(title, selection: $selection) { options }
        #endif
    }
}

#if os(macOS)
/// List actions use the same full-width text rows as the iPad, not AppKit's small
/// tinted push-button bezels. Explicit primary/destructive control styles still win.
struct FleetSettingsActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fleetFont(.body)
            .foregroundStyle(configuration.role == .destructive ? Color.red : FleetTheme.ink)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
            .opacity(isEnabled ? (configuration.isPressed ? 0.65 : 1) : 0.35)
    }
}

/// Native LabeledContent otherwise clusters its value beside the label. The shared
/// settings design puts values on a common trailing edge and stacks only if needed.
struct FleetSettingsValueStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                configuration.label.fixedSize()
                Spacer(minLength: 12)
                configuration.content
                    .multilineTextAlignment(.trailing)
                    .fixedSize()
            }
            VStack(alignment: .leading, spacing: 6) {
                configuration.label
                configuration.content
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A shared-color switch with the iPad design footprint and the real Toggle binding.
/// The accessibility representation retains native checkbox actions and keyboard semantics.
struct FleetSettingsSwitchStyle: ToggleStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
                configuration.isOn.toggle()
            }
        } label: {
            HStack(spacing: 16) {
                configuration.label
                    .foregroundStyle(FleetTheme.ink)
                Spacer(minLength: 8)
                Capsule()
                    .fill(configuration.isOn ? FleetTheme.accent : FleetTheme.secondary.opacity(0.22))
                    .frame(width: 51, height: 31)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle()
                            .fill(Color.white)
                            .padding(2)
                            .frame(width: 31, height: 31)
                            .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
                    }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
                .toggleStyle(.checkbox)
        }
    }
}
#endif

extension View {
    @ViewBuilder
    func fleetSettingsNavigationRow() -> some View {
        #if os(macOS)
        VStack(alignment: .leading, spacing: FleetSettingsSeparator.clearance) {
            self
                .buttonStyle(.plain)
                .frame(minHeight: 44)
                .padding(.vertical, 10)
            FleetSettingsSeparator()
        }
        #else
        self
        #endif
    }

    @ViewBuilder
    func fleetSettingsRowSeparator() -> some View {
        #if os(macOS)
        VStack(alignment: .leading, spacing: FleetSettingsSeparator.clearance) {
            self
            FleetSettingsSeparator()
        }
        #else
        self
        #endif
    }
}
