import SwiftUI
import HashFleetCore

/// The revised editor is scoped to the live phone review and the offline simulator fixture.
/// The existing editor remains the destination everywhere else.
struct MinerTuningPreviewRoute: View {
    let device: MinerDevice
    let store: FleetStore
    let insights: MiningInsightsStore?
    @Environment(\.fleetGuidedDemo) private var guidedDemo
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    private var usesPreview: Bool {
        #if os(iOS)
        (store.isDemo ? NumberFirstPreview.tuning : NumberFirstPreview.usesLivePhoneLayouts)
            && horizontalSizeClass == .compact
            && !store.isPoolIconDemo && !guidedDemo && device.kind != .xmrig
        #else
        false
        #endif
    }

    var body: some View {
        if usesPreview, let info = store.snapshot(for: device.id)?.info {
            let availability = NumberFirstPreview.minerAvailability(info, device: device, store: store)
            let coin = MinerMiningContext.resolve(info: info).pool?.coin
            MinerTuningPreview(
                mode: store.preferences.dashboardMode, device: device, store: store, info: info,
                isDemo: store.isDemo, canEdit: availability.tuning, insights: insights
            )
            .environment(\.minerNavigationIdentity, MinerNavigationIdentity(
                deviceName: device.name, poolName: nil, coin: coin,
                market: coin.flatMap { insights?.coinMarkets[$0] }
            ))
        } else {
            MinerTuningSessionView(device: device, store: store, insights: insights)
        }
    }
}

/// The measurements and configured baselines are never replaced by a local edit or confirmation.
struct MinerTuningPreviewDraft {
    enum Field: String, CaseIterable, Identifiable {
        case frequency, coreVoltage
        var id: Self { self }
        var title: String { self == .frequency ? "Frequency" : "Core voltage" }
        var unit: String { self == .frequency ? "MHz" : "mV" }
        var step: Double { self == .frequency ? 1 : 5 }
        private var input: MinerTuningEasyField { self == .frequency ? .frequency : .voltage }

        func value(_ text: String) -> Double? { try? input.value(from: text) }

        func formatted(_ value: Double?) -> String {
            value.map { "\(MinerTuningDraft.numericText($0)) \(unit)" } ?? "Not reported"
        }
    }

    struct Change: Equatable, Identifiable {
        let field: Field
        let old: Double
        let new: Double
        var id: Field { field }
    }

    struct Review: Equatable, Identifiable {
        let id = UUID()
        let changes: [Change]
        let payload: JSONValue
        static func == (lhs: Self, rhs: Self) -> Bool { lhs.changes == rhs.changes && lhs.payload == rhs.payload }
    }

    let configured: [Field: Double]
    private(set) var text: [Field: String] = [:]

    static func configuration(from info: MinerInfo) -> [Field: Double] {
        let frequency = MinerTuningSessionMath.validFrequency(info.raw["frequency"]?.doubleValue)
        let voltage = MinerTuningSessionMath.validVoltage(info.raw["coreVoltage"]?.doubleValue)
        return [.frequency: frequency, .coreVoltage: voltage].compactMapValues { $0 }
    }

    init(info: MinerInfo) {
        configured = Self.configuration(from: info)
        reset()
    }

    var fields: [Field] { Field.allCases.filter { configured[$0] != nil } }

    func value(for field: Field) -> Double? { text[field].flatMap(field.value) }
    func next(_ field: Field, direction: Double) -> Double? {
        guard let value = value(for: field) else { return nil }
        let next = value + field.step * direction
        return field.value(MinerTuningDraft.numericText(next))
    }

    mutating func edit(_ field: Field, _ value: String) {
        guard configured[field] != nil else { return }
        text[field] = value
    }

    mutating func reset() { text = configured.mapValues(MinerTuningDraft.numericText) }

    var review: Review? {
        guard fields.allSatisfy({ value(for: $0) != nil }) else { return nil }
        let changes = fields.compactMap { field -> Change? in
            guard let old = configured[field], let new = value(for: field), old != new else { return nil }
            return Change(field: field, old: old, new: new)
        }
        // The draft contains changed fields only. The apply service validates it before transmission.
        guard let payload = try? MinerTuningSessionMath.tuningPayload(
            frequency: changes.first { $0.field == .frequency }?.new,
            coreVoltage: changes.first { $0.field == .coreVoltage }?.new, riskAcknowledged: true
        ) else { return nil }
        return Review(changes: changes, payload: payload)
    }
}

/// Infers neither measurements from setpoints nor setpoints from measurements.
struct MinerTuningPreviewReadings {
    let clock: Double?
    let voltage: Double?
    let hashrate: Double?
    let temperature: Double?

    init(info: MinerInfo) {
        clock = MinerTuningSessionMath.validFrequency(info.raw["actualFrequency"]?.doubleValue)
        voltage = MinerTuningSessionMath.validMeasuredVoltage(info.raw["coreVoltageActual"]?.doubleValue)
        hashrate = FleetFormat.sensor(info, keys: "hashRate", "hashrate")
        temperature = FleetFormat.sensor(info, keys: "temp", allowNegative: true)
    }
}

private struct MinerTuningPreview: View {
    let mode: FleetPreferences.DashboardMode
    let device: MinerDevice
    let store: FleetStore
    let info: MinerInfo
    let isDemo: Bool
    let readings: MinerTuningPreviewReadings
    let canEdit: Bool
    let insights: MiningInsightsStore?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var textSize
    #if os(iOS)
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif
    @FocusState private var focus: MinerTuningPreviewDraft.Field?
    @State private var draft: MinerTuningPreviewDraft
    @State private var draftIdentity: MinerInlineActionState.Identity?
    @State private var review: MinerTuningPreviewDraft.Review?
    @State private var applied: MinerTuningPreviewDraft.Review?
    @State private var attempted: MinerTuningPreviewDraft.Review?
    @State private var isApplying = false
    @State private var error: String?
    @State private var statusMessage: String?
    @State private var showsInlineAdvanced = false
    @State private var showsFullAdvanced = false
    @State private var inlineAdvancedIsBusy = false

    private var isEssentials: Bool { mode == .essentials }
    private var offersInlineAdvanced: Bool { isEssentials && (!draft.fields.isEmpty || showsInlineAdvanced) }

    init(mode: FleetPreferences.DashboardMode, device: MinerDevice, store: FleetStore, info: MinerInfo, isDemo: Bool,
         canEdit: Bool, insights: MiningInsightsStore?) {
        self.mode = mode
        self.device = device
        self.store = store
        self.info = info
        self.isDemo = isDemo
        readings = MinerTuningPreviewReadings(info: info)
        self.canEdit = canEdit
        self.insights = insights
        _draft = State(initialValue: MinerTuningPreviewDraft(info: info))
        _draftIdentity = State(initialValue: MinerInlineActionState.identity(from: info))
    }

    private var pinsReadings: Bool {
        #if os(iOS)
        !textSize.isAccessibilitySize && verticalSizeClass != .compact
        #else
        false
        #endif
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                // A sibling of the scroll view stays tappable even when its content
                // has scrolled all the way to Review changes.
                if isEssentials && pinsReadings { pinnedHeader }
                tuningScroll(proxy: proxy)
                    .safeAreaInset(edge: .top, spacing: 0) {
                        if !isEssentials && pinsReadings { pinnedHeader }
                    }
            }
        }
        .background(FleetTheme.canvas)
        .foregroundStyle(FleetTheme.ink)
        .navigationTitle("Frequency & voltage")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { MinerNavigationTitle(pageTitle: "Frequency & voltage") }
            ToolbarItem(placement: FleetToolbarLocation.trailing) {
                if !showsInlineAdvanced, focus == nil, draft.text != draft.configured.mapValues(MinerTuningDraft.numericText) {
                    Button("Reset draft", systemImage: "arrow.counterclockwise") {
                        if isDemo { draft.reset() }
                        else if let draftIdentity, MinerInlineActionState.identity(from: info) == draftIdentity {
                            draft = MinerTuningPreviewDraft(info: info)
                        }
                        applied = nil
                        attempted = nil
                        error = nil
                        statusMessage = nil
                    }
                    .disabled(isApplying)
                    .labelStyle(.iconOnly)
                    .accessibilityIdentifier("tuning.preview.reset")
                }
            }
        }
        .fleetEditingDone(focus != nil, identifier: "tuning.preview.done") { focus = nil }
        .tint(FleetTheme.accent)
        .navigationDestination(isPresented: $showsFullAdvanced) {
            MinerTuningSessionView(device: device, store: store, insights: insights, reviewPresentation: $showsFullAdvanced)
        }
        .onChange(of: showsInlineAdvanced || showsFullAdvanced) { _, presented in
            // The detailed workspace owns its own draft. Refresh a clean Easy draft on return.
            if !presented, !isDemo, let draftIdentity, MinerInlineActionState.identity(from: info) == draftIdentity,
               draft.text == draft.configured.mapValues(MinerTuningDraft.numericText) {
                draft = MinerTuningPreviewDraft(info: info)
                statusMessage = nil
            }
        }
        .sheet(item: $review) { request in
            MinerTuningPreviewReview(request: request,
                                     canConfirm: !isEssentials && canEdit && request == draft.review
                                        && request != attempted && !isApplying,
                                     isLive: !isDemo,
                                     attemptMessage: request == attempted ? (error ?? statusMessage) : nil) {
                guard !isEssentials, canEdit, request == draft.review, request != attempted, !isApplying else { return }
                if isDemo {
                    applied = request
                    review = nil
                } else {
                    apply(request)
                }
            }
        }
    }

    private func tuningScroll(proxy: ScrollViewProxy) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !pinsReadings { tuningHeader }
                if !isEssentials { modePicker }
                if !showsInlineAdvanced {
                    if canEdit, !draft.fields.isEmpty {
                        editor
                        applyAction
                    } else {
                        Label("Tuning controls unavailable for this miner.", systemImage: "lock")
                            .fleetFont(.subheadline).foregroundStyle(FleetTheme.secondary)
                    }
                }
                // Keep the Advanced draft mounted, not its dials, when the switch is off.
                if isEssentials {
                    MinerTuningSessionView(device: device, store: store, insights: insights, inlineAdvanced: .init(
                        isExpanded: $showsInlineAdvanced, isBusy: $inlineAdvancedIsBusy,
                        jumpToReview: {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                                proxy.scrollTo("tuningSession.applySection", anchor: .top)
                            }
                        }
                    ))
                }
            }
            .fleetPageContainer(compactMaxWidth: FleetLayout.readableWidth)
        }
        .fleetEditingScroll()
        .fleetRevealEditingField(focus, using: proxy)
    }

    private var pinnedHeader: some View {
        tuningHeader
            .padding(.horizontal, FleetLayout.pagePadding)
            .padding(.vertical, 8)
            .fleetReadableWidth()
            .background(FleetTheme.canvas)
    }

    private var tuningHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            if offersInlineAdvanced {
                MinerTuningAdvancedSwitch(isOn: $showsInlineAdvanced)
                    .disabled(isApplying || inlineAdvancedIsBusy || focus != nil)
            }
            if !showsInlineAdvanced { readingHeader }
        }
    }

    private var readingHeader: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(isDemo ? "Demo only · No miner connected" : "Connected miner",
                  systemImage: isDemo ? "sparkles" : "antenna.radiowaves.left.and.right")
                .fleetFont(.footnote, weight: .semibold).foregroundStyle(FleetTheme.accent)
            MinerControlsCard {
                HStack(spacing: 8) {
                    Image(systemName: "waveform.path").accessibilityHidden(true)
                    Text("Current readings")
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("tuning.preview.readings")
                }
                .fleetFont(.headline, weight: .semibold)
                let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 10, alignment: .topLeading),
                                    count: textSize.isAccessibilitySize ? 2 : 4)
                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    metric("Hashrate", readings.hashrate.map { FleetFormat.hashrateWithUnit($0) } ?? "Not reported", id: "hashrate")
                    metric("Chip temp", FleetFormat.measurement(readings.temperature, unit: "°C"), id: "temperature")
                    metric("Clock", MinerTuningPreviewDraft.Field.frequency.formatted(readings.clock), id: "clock")
                    metric("Core voltage", MinerTuningPreviewDraft.Field.coreVoltage.formatted(readings.voltage), id: "voltage")
                }
            }
        }
    }

    private func metric(_ title: String, _ reading: String, id: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).fleetFont(.caption2).foregroundStyle(FleetTheme.secondary)
            Text(reading).fleetFont(.subheadline, weight: .semibold).monospacedDigit()
                .accessibilityIdentifier("tuning.preview.readings.\(id)")
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var editor: some View {
        MinerControlsCard {
            MinerControlsHeader(title: isEssentials ? "Adjust settings" : "Tuning draft",
                                subtitle: "Board-wide frequency and core voltage.",
                                symbol: "slider.horizontal.3")
            ForEach(draft.fields) { field in
                Divider().overlay(FleetTheme.separator).accessibilityHidden(true)
                fieldRow(field)
            }
        }
    }

    private func fieldRow(_ field: MinerTuningPreviewDraft.Field) -> some View {
        let layout = textSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(spacing: 8))
        return VStack(alignment: .leading, spacing: 4) {
            layout {
                VStack(alignment: .leading, spacing: 3) {
                    Text(field.title).fleetFont(.subheadline, weight: .semibold)
                    Text("Configured \(field.formatted(draft.configured[field]))")
                        .fleetFont(.caption2).foregroundStyle(FleetTheme.secondary).monospacedDigit()
                        .accessibilityIdentifier("tuning.preview.\(field.rawValue).configured")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 5) {
                    step(field, increasing: false)
                    fieldInput(field)
                    step(field, increasing: true)
                }
            }
            if draft.value(for: field) == nil, focus != field {
                Text(field == .frequency ? "Enter a valid frequency." : "Enter a valid whole-number voltage.")
                    .fleetFont(.caption).foregroundStyle(FleetTheme.warning)
                    .accessibilityIdentifier("tuning.preview.\(field.rawValue).error")
            }
        }
        .padding(.vertical, 3)
    }

    private func fieldInput(_ field: MinerTuningPreviewDraft.Field) -> some View {
        HStack(spacing: 4) {
            TextField("Value", text: Binding(get: { draft.text[field] ?? "" }, set: { edit(field, $0) }))
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .fleetFont(.subheadline, weight: .semibold)
                .foregroundStyle(FleetTheme.accent)
                .monospacedDigit()
                .focused($focus, equals: field)
                #if os(iOS)
                .keyboardType(field == .frequency ? .decimalPad : .numberPad)
                #endif
                .onSubmit { focus = nil }
                .frame(minHeight: 44)
                .accessibilityLabel("Draft \(field.title) in \(field.unit)")
                .accessibilityIdentifier("tuning.preview.\(field.rawValue).input")
            Text(field.unit).fleetFont(.caption2).foregroundStyle(FleetTheme.secondary).accessibilityHidden(true)
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 7)
        .frame(width: textSize.isAccessibilitySize ? nil : 104)
        .background(FleetTheme.raised, in: RoundedRectangle(cornerRadius: 10))
        .id(field)
    }

    private func edit(_ field: MinerTuningPreviewDraft.Field, _ value: String) {
        draft.edit(field, value)
        applied = nil
        attempted = nil
        error = nil
        statusMessage = nil
    }

    private func writeAuthorized(for request: MinerTuningPreviewDraft.Review) -> Bool {
        guard !store.isDemo, let draftIdentity,
              let snapshot = store.snapshot(for: device.id),
              let currentInfo = snapshot.info,
              MinerWriteAvailability.allows(
                snapshot, device: device, currentDevices: store.devices, isDemo: store.isDemo
              ),
              MinerInlineActionState.identity(from: currentInfo) == draftIdentity,
              MinerTuningPreviewDraft.configuration(from: currentInfo) == draft.configured,
              request == draft.review else { return false }
        return true
    }

    private func apply(_ request: MinerTuningPreviewDraft.Review) {
        guard !isApplying, request != attempted, canEdit, let draftIdentity, writeAuthorized(for: request) else {
            error = "The miner connection or configured settings changed. Check the current settings before trying again."
            return
        }
        let baseline = draft.configured
        attempted = request
        isApplying = true
        error = nil
        statusMessage = nil
        Task { @MainActor in
            defer { isApplying = false }
            do {
                let result = try await MinerTuningApplyService(session: store.session).apply(
                    device: device, payload: request.payload, isDemo: isDemo,
                    validatePreflight: { fresh in
                        guard MinerInlineActionState.identity(from: fresh) == draftIdentity,
                              MinerTuningPreviewDraft.configuration(from: fresh) == baseline else {
                            throw MinerTuningApplyService.ApplyError.blocked(
                                "The miner's configured tuning changed during review. No change was sent. Refresh and review the current settings."
                            )
                        }
                    },
                    writeAuthorized: { writeAuthorized(for: request) }
                )
                switch result {
                case .verified(let fresh):
                    guard store.devices.contains(where: {
                        $0.id == device.id && $0.address == device.address && $0.kind == device.kind
                    }), !store.isDemo, MinerInlineActionState.identity(from: fresh) == draftIdentity else {
                        error = "The miner changed after verification. Check its current settings before retrying."
                        return
                    }
                    store.recordSuccessfulInfo(fresh, for: device.id, at: .now)
                    draft = MinerTuningPreviewDraft(info: fresh)
                    statusMessage = "Fresh readback verified the change."
                    review = nil
                case .unverified(let message):
                    error = message
                }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func step(_ field: MinerTuningPreviewDraft.Field, increasing: Bool) -> some View {
        let next = draft.next(field, direction: increasing ? 1 : -1)
        return Button {
            if let next { edit(field, MinerTuningDraft.numericText(next)) }
        } label: {
            Image(systemName: increasing ? "plus" : "minus")
        }
        .buttonStyle(FleetPrimaryButtonStyle(tone: .secondary, size: .compact))
        .disabled(next == nil || focus != nil)
        .accessibilityLabel("\(increasing ? "Increase" : "Decrease") \(field.title.lowercased())")
        .accessibilityIdentifier("tuning.preview.\(field.rawValue).\(increasing ? "increase" : "decrease")")
    }

    private var applyAction: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(isEssentials
                     ? "Changing frequency or voltage can increase heat and power use and damage hardware."
                     : "Tuning changes can increase heat and power and damage hardware.")
                    .accessibilityIdentifier("tuning.preview.risk")
            } icon: {
                Image(systemName: "exclamationmark.triangle").accessibilityHidden(true)
            }
            .foregroundStyle(FleetTheme.warning)
            let proposal = draft.review
            Button(isEssentials ? "Apply Changes" : "Review Changes") {
                guard canEdit, focus == nil, let proposal, proposal != applied, proposal != attempted,
                      !isApplying else { return }
                if isEssentials {
                    if isDemo { applied = proposal }
                    else { apply(proposal) }
                } else {
                    review = proposal
                }
            }
            .buttonStyle(FleetPrimaryButtonStyle(size: .compact, fullWidth: true))
            .disabled(proposal == nil || proposal == applied || proposal == attempted || focus != nil || isApplying)
            .accessibilityIdentifier(isEssentials ? "tuning.preview.apply" : "tuning.preview.review")
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(FleetTheme.warning)
                    .accessibilityIdentifier("tuning.preview.result")
            } else if let statusMessage {
                Label(statusMessage, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(FleetTheme.positive)
                    .accessibilityIdentifier("tuning.preview.result")
            } else if isApplying {
                Label("Sending and checking current settings…", systemImage: "clock")
                    .foregroundStyle(FleetTheme.secondary)
            } else if applied != nil {
                Label(isEssentials ? "Applied in this demo. Nothing sent." : "Demo confirmed. No settings sent.",
                      systemImage: "checkmark.circle.fill")
                    .foregroundStyle(FleetTheme.positive)
                    .accessibilityIdentifier("tuning.preview.result")
            } else {
                Text(isEssentials ? "Changes stay here until you apply them." : "Nothing is sent while you edit.")
                    .foregroundStyle(FleetTheme.secondary)
            }
        }
        .fleetFont(.footnote)
    }

    private var modePicker: some View {
        Picker("Tuner mode", selection: Binding(
            get: { showsFullAdvanced ? MinerTuningControlMode.advanced : .easy },
            set: { showsFullAdvanced = $0 == .advanced }
        )) {
            ForEach(MinerTuningControlMode.allCases, id: \.self) { choice in
                Text(choice.displayName).tag(choice)
            }
        }
        .pickerStyle(.segmented)
        .disabled(isApplying || focus != nil || review != nil)
        .accessibilityIdentifier("tuning.preview.mode")
    }
}

private struct MinerTuningPreviewReview: View {
    let request: MinerTuningPreviewDraft.Review
    let canConfirm: Bool
    let isLive: Bool
    let attemptMessage: String?
    let confirm: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var acknowledged = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(isLive
                         ? "Review the board-wide changes. Confirming sends only the displayed fields, then checks a fresh readback."
                         : "Review the board-wide changes below. This demo does not contact a miner.")
                        .fleetFont(.subheadline).foregroundStyle(FleetTheme.secondary)
                    MinerControlsCard {
                        ForEach(request.changes) { change in
                            LabeledContent(change.field.title) {
                                Text("\(change.field.formatted(change.old)) → \(change.field.formatted(change.new))")
                                    .monospacedDigit()
                                    .accessibilityIdentifier("tuning.preview.change.\(change.field.rawValue)")
                            }
                        }
                    }
                    if let json = try? request.payload.prettyPrinted() {
                        MinerControlsCard {
                            Label("JSON preview", systemImage: "curlybraces").fleetFont(.headline, weight: .semibold)
                            Text(json).fleetFont(.body, design: .monospaced).textSelection(.enabled)
                                .accessibilityIdentifier("tuning.preview.json")
                        }
                    }
                    Toggle("I understand the hardware risks", isOn: $acknowledged)
                        .fleetFont(.subheadline)
                        .accessibilityIdentifier("tuning.preview.acknowledge")
                    if let attemptMessage {
                        Label(attemptMessage, systemImage: "exclamationmark.triangle.fill")
                            .fleetFont(.footnote).foregroundStyle(FleetTheme.warning)
                            .accessibilityIdentifier("tuning.preview.result")
                    }
                    Button(isLive ? "Confirm & Apply" : "Confirm Demo Change", action: confirm)
                        .buttonStyle(FleetPrimaryButtonStyle(size: .compact, fullWidth: true))
                        .disabled(!acknowledged || !canConfirm)
                        .accessibilityIdentifier("tuning.preview.confirm")
                }
                .padding(.bottom, textSize.isAccessibilitySize ? 16 : 0)
                .fleetPageContainer(compactMaxWidth: FleetLayout.readableWidth)
            }
            .background(FleetTheme.canvas)
            .foregroundStyle(FleetTheme.ink)
            .navigationTitle("Review tuning changes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.accessibilityIdentifier("tuning.preview.cancel")
                }
            }
            .tint(FleetTheme.accent)
        }
    }
}
