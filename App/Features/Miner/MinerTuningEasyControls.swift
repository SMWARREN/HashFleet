import SwiftUI

/// Direct draft entry. Leaving a field or dismissing its keyboard stages a value, never a write.
struct MinerTuningEasyControls: View {
    let title: String
    let field: MinerTuningEasyField
    @Binding var setpoint: Double
    let isBeyondReference: Bool
    let isRestricted: Bool
    let isEnabled: Bool
    let accessibilityPrefix: String
    let valueIdentifier: String
    var resetGeneration = 0
    var onFocusChanged: (Bool) -> Void = { _ in }
    var onValidityChanged: (Bool) -> Void = { _ in }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .subheadline) private var inputWidth = 96
    @ScaledMetric(relativeTo: .subheadline) private var iconWidth = 22
    @ScaledMetric(relativeTo: .caption) private var unitColumnWidth = 30
    @State private var input = MinerTuningEasyInputState()
    @FocusState private var isFocused: Bool

    private var warningColor: Color { isRestricted || isBeyondReference ? .red : FleetTheme.accent }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isEnabled {
                inputRow
                Text("Draft: \(MinerTuningDraft.numericText(setpoint)) \(field.unit)")
                    .fleetFont(.caption, design: .rounded)
                    .monospacedDigit()
                    .foregroundStyle(warningColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(valueIdentifier)
            } else {
                fieldLabel
                Text("Not reported")
                    .fleetFont(.subheadline)
                    .foregroundStyle(FleetTheme.secondary)
                    .accessibilityIdentifier(valueIdentifier)
                Text("A current reading is needed to edit.")
                    .fleetFont(.caption).foregroundStyle(FleetTheme.secondary)
            }
            if isRestricted {
                Label("Device limit", systemImage: "lock.shield.fill")
                    .fleetFont(.caption).foregroundStyle(.red)
            } else if isBeyondReference {
                Label("Over reference", systemImage: "exclamationmark.triangle.fill")
                    .fleetFont(.caption).foregroundStyle(.red)
            }
            if let error = input.error {
                Text(error)
                    .fleetFont(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("\(accessibilityPrefix).customError")
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.vertical, 7)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("\(accessibilityPrefix).easyControls")
        .onAppear { resetInput() }
        .onChange(of: resetGeneration) { _, _ in resetInput() }
        .onChange(of: isEnabled) { _, _ in resetInput() }
        .onChange(of: setpoint) { _, value in
            input.receive(value: isEnabled ? value : nil, isFocused: isFocused)
        }
        .onChange(of: isFocused) { _, focused in
            if !focused { commitInput() }
            onFocusChanged(focused)
        }
        .onDisappear { onFocusChanged(false) }
        #if !os(macOS)
        .toolbar {
            if isFocused {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { isFocused = false }
                        .accessibilityIdentifier("\(accessibilityPrefix).keyboardDone")
                }
            }
        }
        #endif
    }

    private var fieldLabel: some View {
        HStack(spacing: 10) {
            Image(systemName: field == .frequency ? "gauge.with.dots.needle.67percent" : "bolt")
                .foregroundStyle(FleetTheme.accent)
                .frame(width: iconWidth)
                .accessibilityHidden(true)
            Text(title).foregroundStyle(FleetTheme.ink)
        }
        .fleetFont(.subheadline)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var inputRow: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 10))
        return layout {
            fieldLabel
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
            HStack(spacing: 6) {
                inputField
                    .frame(width: dynamicTypeSize.isAccessibilitySize ? nil : inputWidth)
                Text(field.unit)
                    .fleetFont(.caption)
                    .foregroundStyle(FleetTheme.secondary)
                    .frame(width: unitColumnWidth, alignment: .leading)
            }
        }
    }

    private var inputField: some View {
        TextField("Enter \(field.unit)", text: Binding(get: { input.text }, set: {
            input.edit($0, field: field)
            #if os(macOS)
            // Stage valid typing immediately. On macOS a text field keeps focus when the user
            // clicks a non-focusable control, so waiting for focus loss never staged the draft.
            if let value = input.stageWhileEditing(field: field), value != setpoint {
                setpoint = value
            }
            #endif
            onValidityChanged(input.error == nil)
        }))
        .fleetFont(.title3, weight: .semibold, design: .rounded)
        .foregroundStyle(FleetTheme.accent)
        .textFieldStyle(.plain)
        .multilineTextAlignment(.trailing)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .monospacedDigit()
        .focused($isFocused)
        #if !os(macOS)
        .keyboardType(field == .frequency ? .decimalPad : .numberPad)
        #endif
        .onSubmit { isFocused = false }
        .accessibilityLabel("\(title) in \(field.unit)")
        .accessibilityHint("Stages the draft when you finish editing. Nothing is sent until you review and confirm Apply.")
        .accessibilityIdentifier("\(accessibilityPrefix).customInput")
    }

    private func resetInput() {
        input.reset(value: isEnabled ? setpoint : nil)
        isFocused = false
        onValidityChanged(true)
    }

    private func commitInput() {
        guard isEnabled else { return }
        if let value = input.commit(field: field) {
            setpoint = value
        } else if input.error == nil {
            input.receive(value: setpoint, isFocused: false)
        }
        onValidityChanged(input.error == nil)
    }
}
