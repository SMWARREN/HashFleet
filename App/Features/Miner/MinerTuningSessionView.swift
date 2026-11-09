import SwiftUI
import HashFleetCore

/// A board-aware tuning workspace shared by the iPhone and the Mac-designed-for-iPad app.
///
/// The firmware settings endpoint exposes one frequency field for the board, not a writable
/// frequency per ASIC. The numbered cards make the ASIC layout easy to scan while every card edits
/// the same board-wide setpoint. Values beyond the reported reference are allowed for deliberate
/// overclock review, but turn red and remain subject to the existing final APPLY gate.
struct MinerTuningSessionView: View {
    let device: MinerDevice
    @Bindable var store: FleetStore
    var insights: MiningInsightsStore?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #if !os(macOS)
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif
    @State private var setpoints = MinerTuningSetpointState()
    @State private var riskAcknowledged = false
    @State private var isApplying = false
    @State private var reviewedPayload: JSONValue?
    @State private var showApplyConfirmation = false
    @State private var journal: [MinerTuningJournalEntry] = []
    @State private var error: String?
    @State private var statusMessage: String?
    @State private var controlMode: MinerTuningControlMode = .easy
    @State private var showEasyDetails = false
    @State private var focusedEasyFields: Set<MinerTuningEasyField> = []
    @State private var invalidEasyFields: Set<MinerTuningEasyField> = []
    @State private var easyResetGeneration = 0

    private var isEditingCustomValue: Bool {
        #if os(macOS)
        // No software keyboard covers the review bar on Mac, and focus can linger indefinitely.
        false
        #else
        !focusedEasyFields.isEmpty
        #endif
    }
    /// Valid typing is staged immediately on Mac, so only invalid text blocks mode changes or Apply.
    private var hasUnfinishedEasyInput: Bool {
        #if os(macOS)
        !invalidEasyFields.isEmpty
        #else
        isEditingCustomValue || !invalidEasyFields.isEmpty
        #endif
    }

    init(device: MinerDevice, store: FleetStore, insights: MiningInsightsStore? = nil) {
        self.device = device
        self.store = store
        self.insights = insights
    }

    private var info: MinerInfo? { store.snapshot(for: device.id)?.info }

    /// Self-contained title identity so every entry point (quick link, card gear, dashboard,
    /// settings hub) shows the miner name and coin instead of relying on an inherited environment.
    private var navigationIdentity: MinerNavigationIdentity {
        let context = MinerMiningContext.resolve(info: info)
        let coin = context.pool?.coin
        return MinerNavigationIdentity(
            deviceName: device.name,
            poolName: context.pool == nil ? nil : context.providerLabel,
            coin: coin,
            market: coin.flatMap { insights?.coinMarkets[$0] }
        )
    }

    private var capabilityReport: MinerCapabilityReport? {
        store.capabilities.reports[device.id]
    }

    private var reference: MinerTuningReference? {
        guard let asic = capabilityReport?.asic else { return nil }
        return try? MinerTuningReference(json: asic)
    }

    private var configuredFrequency: Double? { MinerTuningSessionMath.validFrequency(info?.raw["frequency"]?.doubleValue) }
    private var actualFrequency: Double? { MinerTuningSessionMath.validFrequency(info?.raw["actualFrequency"]?.doubleValue) }
    private var configuredVoltage: Double? { MinerTuningSessionMath.validVoltage(info?.raw["coreVoltage"]?.doubleValue) }
    private var measuredVoltage: Double? { MinerTuningSessionMath.validMeasuredVoltage(diagnostics.electrical.actualCoreVoltageMV) }

    private var chipCount: Int {
        max(1, MinerTuningSessionMath.chipCount(reference: reference, info: info) ?? 1)
    }

    private var chipCountWasReported: Bool {
        MinerTuningSessionMath.chipCount(reference: reference, info: info) != nil
    }

    private var diagnostics: MinerDiagnosticsModel {
        MinerDiagnosticsModel(info: info ?? MinerInfo(raw: [:]))
    }

    private var coreReadings: [MinerTuningCoreReading] {
        MinerTuningSessionMath.coreReadings(
            count: chipCount,
            primaryTemperature: diagnostics.thermal.primaryChipTempCelsius,
            secondaryTemperature: diagnostics.thermal.secondaryChipTempCelsius,
            voltageMillivolts: diagnostics.electrical.actualCoreVoltageMV
                ?? diagnostics.electrical.configuredCoreVoltageMV
        )
    }

    private var referenceMaximum: Double? { MinerTuningSessionMath.referenceMaximum(reference) }

    private var isBeyondReference: Bool {
        MinerTuningSessionMath.isBeyondReference(frequency, reference: reference)
    }

    private var controlRange: ClosedRange<Double> {
        MinerTuningSessionMath.controlRange(
            current: setpoints.frequencyBaseline ?? 1, reference: reference
        )
    }

    private var voltageReferenceMaximum: Double? { MinerTuningSessionMath.voltageReferenceMaximum(reference) }

    private var isVoltageBeyondReference: Bool {
        MinerTuningSessionMath.isVoltageBeyondReference(coreVoltage, reference: reference)
    }

    private var voltageRange: ClosedRange<Double> {
        MinerTuningSessionMath.voltageControlRange(
            current: setpoints.voltageBaseline ?? 1,
            reference: reference
        )
    }

    /// True when either dial is past the firmware's reported reference.
    private var isAnyBeyondReference: Bool { isBeyondReference || isVoltageBeyondReference }

    private var frequency: Double { setpoints.frequency ?? 0 }
    private var coreVoltage: Double { setpoints.coreVoltage ?? 0 }
    private var frequencyBinding: Binding<Double> {
        Binding(get: { frequency }, set: {
            setpoints.editFrequency($0)
            error = nil
            statusMessage = nil
        })
    }
    private var voltageBinding: Binding<Double> {
        Binding(get: { coreVoltage }, set: {
            setpoints.editVoltage($0)
            error = nil
            statusMessage = nil
        })
    }
    private var voltageRestriction: String? {
        MinerTuningHardwarePolicy.restriction(
            device: device, voltage: setpoints.voltageEdited ? setpoints.coreVoltage : nil, info: info
        )
    }

    private var changedFields: (frequency: Bool, coreVoltage: Bool) {
        (frequency: setpoints.frequencyEdited, coreVoltage: setpoints.voltageEdited)
    }

    private var isDemo: Bool { store.isDemo }

    private var canWrite: Bool {
        !isDemo
            && store.visibleDevices.contains(where: { $0.id == device.id && $0.address == device.address })
            && MinerWriteAvailability.allows(store.snapshot(for: device.id))
    }

    private var isOffline: Bool {
        !store.isDemo && !MinerWriteAvailability.allows(store.snapshot(for: device.id))
    }

    /// Only the dials the user actually moved are sent, so an untouched value is never rewritten.
    private var stagedPayload: JSONValue? { setpoints.payload }

    private var stagedPayloadData: Data? {
        guard let stagedPayload else { return nil }
        return try? JSONEncoder().encode(stagedPayload)
    }

    private var stagedJSON: String? { formattedJSON(stagedPayload) }

    private func formattedJSON(_ payload: JSONValue?) -> String? {
        guard let payload else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(payload) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private var hasStagedChange: Bool { setpoints.hasChanges }

    private var snapshotDate: Date? { store.snapshot(for: device.id)?.updatedAt }
    private var pinsEasyReview: Bool {
        #if os(macOS)
        // The bottom safe-area inset never renders inside the Mac split-view detail stack,
        // which hid Apply entirely. Keep the review inline on Mac.
        false
        #else
        !dynamicTypeSize.isAccessibilitySize && verticalSizeClass != .compact
        #endif
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if controlMode == .easy {
                        modePicker
                        easyControlsSection
                        if !pinsEasyReview {
                            timedReview.id("tuningSession.applySection")
                        }
                        easyDetails(proxy: proxy)
                    } else {
                        TimelineView(.periodic(from: .now, by: MinerSnapshotFreshness.refreshInterval)) { _ in
                            MinerTuningSessionHeader(
                                deviceName: device.name,
                                isDemo: isDemo,
                                isOffline: isOffline,
                                chipCount: chipCount,
                                chipCountWasReported: chipCountWasReported,
                                controlMode: controlMode
                            )
                        }
                        modePicker
                        safetyCard
                        advancedControlsSection
                        liveContextCard
                        MinerTuningReferenceCard(reference: reference, isDemo: isDemo)
                        LazyVStack(alignment: .leading, spacing: 16) {
                            asicSection(proxy: proxy)
                            #if os(macOS)
                            reviewSection
                            .id("tuningSession.applySection")
                            #else
                            TimelineView(.periodic(from: .now, by: MinerSnapshotFreshness.refreshInterval)) { _ in
                                reviewSection
                            }
                            .id("tuningSession.applySection")
                            #endif
                        }
                        MinerTuningJournalCard(journal: journal)
                    }
                }
                .fleetPageContainer(compactMaxWidth: FleetLayout.readableWidth)
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if controlMode == .easy && pinsEasyReview && !isEditingCustomValue {
                    timedReview
                        .fleetPageContainer(compactMaxWidth: FleetLayout.readableWidth)
                        .background(FleetTheme.canvas)
                        .accessibilityIdentifier("tuningSession.easyActionBar")
                }
            }
            .background(FleetTheme.canvas)
            .foregroundStyle(FleetTheme.ink)
            .navigationTitle("Frequency & voltage")
            .fleetPerformanceScreen("Frequency & voltage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    MinerNavigationTitle(pageTitle: "Frequency & voltage")
                }
                ToolbarItem(placement: FleetToolbarLocation.trailing) {
                    Button("Restore", systemImage: "arrow.counterclockwise") { restoreDraft() }
                        .labelStyle(.iconOnly)
                        .disabled((!hasStagedChange && !hasUnfinishedEasyInput) || isApplying || showApplyConfirmation)
                        .accessibilityLabel("Reset draft")
                        .accessibilityIdentifier("tuningSession.reset")
                }
                ToolbarItem(placement: FleetToolbarLocation.trailing) {
                    Button {
                        if controlMode == .easy { showEasyDetails = true }
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                            proxy.scrollTo(controlMode == .easy ? "tuningSession.easyDetails" : "tuningSession.applySection", anchor: .top)
                        }
                    } label: {
                        Image(systemName: "arrow.down.to.line.compact")
                    }
                    .accessibilityLabel("Review JSON and apply")
                    .accessibilityIdentifier("tuningSession.jump.apply")
                }
            }
            .tint(FleetTheme.accent)
            .environment(\.minerNavigationIdentity, navigationIdentity)
            .alert("Apply tuning change?", isPresented: $showApplyConfirmation) {
                Button("Cancel", role: .cancel) { reviewedPayload = nil }
                Button("Apply", role: .destructive) { applyStagedChange() }
            } message: {
                Text(
                    "This sends one settings JSON update to \(device.name) and keeps you on this tuning session.\n\n"
                        + (formattedJSON(reviewedPayload) ?? "No valid tuning payload is staged.")
                )
            }
            .onAppear {
                riskAcknowledged = UserDefaults.standard.bool(forKey: acknowledgementKey)
                loadJournal()
                loadSetpointsIfAvailable()
            }
            .onChange(of: snapshotDate) { _, _ in
                loadSetpointsIfAvailable()
            }
            .onChange(of: riskAcknowledged) { _, acknowledged in
                UserDefaults.standard.set(acknowledged, forKey: acknowledgementKey)
            }
            .onChange(of: capabilityReport?.checkedAt) { _, _ in
                loadSetpointsIfAvailable()
            }
            .task(id: device.id) {
                guard !isDemo, capabilityReport?.asic == nil else { return }
                await store.capabilities.check(device: device, isDemo: false)
                loadSetpointsIfAvailable()
            }
            .accessibilityIdentifier("tuningSession.screen")
        }
    }
}

extension MinerTuningSessionView {
    private var acknowledgementKey: String {
        "app.hashfleet.tuningRiskAcknowledged.\(device.id.uuidString)"
    }

    private var modePicker: some View {
        Picker("Tuner mode", selection: $controlMode) {
            ForEach(MinerTuningControlMode.allCases, id: \.self) { mode in
                Text(mode.displayName).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .disabled(isApplying || showApplyConfirmation || hasUnfinishedEasyInput)
        .accessibilityIdentifier("tuningSession.controlMode")
    }

    /// On Mac a TimelineView collapses to zero height inside the ScrollView/safe-area inset, which
    /// hid the whole review and Apply button. Snapshot updates already re-render this section.
    @ViewBuilder private var timedReview: some View {
        #if os(macOS)
        reviewSection
        #else
        TimelineView(.periodic(from: .now, by: MinerSnapshotFreshness.refreshInterval)) { _ in reviewSection }
        #endif
    }

    /// Both board-wide inputs stay visible, with frequency above core voltage.
    private var easyControlsSection: some View {
        MinerControlsCard {
            MinerControlsHeader(title: "Tuning", subtitle: "Board-wide frequency and core voltage.",
                                symbol: "slider.horizontal.3")
            Divider().overlay(FleetTheme.separator)
            easyControl(.frequency)
            Divider().overlay(FleetTheme.separator)
            easyControl(.voltage)
        }
        .disabled(isApplying || showApplyConfirmation)
        .accessibilityIdentifier("tuningSession.easyControlsSection")
    }

    private func easyControl(_ field: MinerTuningEasyField) -> some View {
        MinerTuningEasyControls(
            title: field == .frequency ? "Frequency" : "Core voltage", field: field,
            setpoint: field == .frequency ? frequencyBinding : voltageBinding,
            isBeyondReference: field == .frequency ? isBeyondReference : isVoltageBeyondReference,
            isRestricted: field == .voltage && voltageRestriction != nil,
            isEnabled: field == .frequency ? setpoints.frequency != nil : setpoints.coreVoltage != nil,
            accessibilityPrefix: field == .frequency ? "tuningSession.master" : "tuningSession.voltage",
            valueIdentifier: field == .frequency ? "tuningSession.frequencyValue" : "tuningSession.voltageValue",
            resetGeneration: easyResetGeneration,
            onFocusChanged: { focused in
                if focused { focusedEasyFields.insert(field) } else { focusedEasyFields.remove(field) }
            },
            onValidityChanged: { valid in
                if valid { invalidEasyFields.remove(field) } else { invalidEasyFields.insert(field) }
            }
        )
    }

    private func easyDetails(proxy: ScrollViewProxy) -> some View {
        DisclosureGroup(isExpanded: $showEasyDetails) {
            VStack(alignment: .leading, spacing: 16) {
                MinerTuningPayloadView(stagedJSON: stagedJSON)
                liveContextCard
                MinerTuningReferenceCard(reference: reference, isDemo: isDemo)
                asicSection(proxy: proxy)
                MinerTuningJournalCard(journal: journal)
            }
            .padding(.top, 12)
        } label: {
            Text("Technical details")
                .fleetFont(.subheadline, weight: .semibold)
                .frame(minHeight: 48)
                .id("tuningSession.easyDetails")
                .accessibilityIdentifier("tuningSession.easyDetails")
        }
        .disabled(isApplying || showApplyConfirmation)
    }

    /// Car-style instrument cluster: frequency "tach" beside a core-voltage gauge, with a strip
    /// that compares what is staged against what the miner runs now.
    private var advancedControlsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            MinerTuningDialPair(
                frequency: MinerTuningDial(
                    title: "Frequency",
                    unit: "MHz",
                    setpoint: frequencyBinding,
                    range: controlRange,
                    liveValue: actualFrequency,
                    configuredValue: configuredFrequency,
                    referenceMaximum: referenceMaximum,
                    isBeyondReference: isBeyondReference,
                    isEnabled: setpoints.frequency != nil,
                    referenceOptions: reference?.frequencyOptions ?? [],
                    step: 1,
                    coarseStep: 10,
                    accessibilityPrefix: "tuningSession.master",
                    valueIdentifier: "tuningSession.frequencyValue"
                ),
                voltage: MinerTuningDial(
                    title: "Core voltage",
                    unit: "mV",
                    setpoint: voltageBinding,
                    range: voltageRange,
                    liveValue: measuredVoltage,
                    configuredValue: configuredVoltage,
                    referenceMaximum: voltageReferenceMaximum,
                    isBeyondReference: isVoltageBeyondReference,
                    isRestricted: voltageRestriction != nil,
                    isEnabled: setpoints.coreVoltage != nil,
                    referenceOptions: reference?.voltageOptions ?? [],
                    step: 5,
                    coarseStep: 25,
                    accessibilityPrefix: "tuningSession.voltage",
                    valueIdentifier: "tuningSession.voltageValue"
                )
            )
            .disabled(isApplying || showApplyConfirmation)
            if setpoints.frequency != nil && setpoints.coreVoltage != nil {
                MinerTuningDeltaStrip(
                    stagedFrequency: frequency,
                    configuredFrequency: configuredFrequency,
                    stagedVoltage: coreVoltage,
                    configuredVoltage: configuredVoltage
                )
            }
            Text(
                "Frequency and core voltage are board-wide. Only the dials you move are sent, and nothing is sent while you drag."
            )
            .fleetFont(.caption)
            .foregroundStyle(FleetTheme.secondary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tuningSession.advancedControlsSection")
    }

    private func asicSection(proxy: ScrollViewProxy) -> some View {
        MinerTuningASICRail(
            proxy: proxy,
            chipCount: chipCount, coreReadings: coreReadings,
            frequency: setpoints.frequency,
            stagedVoltage: setpoints.coreVoltage,
            referenceMaximum: referenceMaximum,
            isAnyBeyondReference: isAnyBeyondReference
        )
    }

    private var safetyCard: some View {
        MinerTuningSafetyCard(
            riskAcknowledged: $riskAcknowledged,
            isBeyondReference: isAnyBeyondReference,
            hasReference: referenceMaximum != nil || voltageReferenceMaximum != nil,
            voltageRestriction: voltageRestriction
        )
    }

    private var reviewSection: some View {
        MinerTuningReview(
            mode: controlMode, summary: changeSummary, stagedJSON: stagedJSON,
            riskAcknowledged: $riskAcknowledged, isBeyondReference: isAnyBeyondReference,
            voltageRestriction: voltageRestriction, isDemo: isDemo, isOffline: isOffline,
            isApplying: isApplying,
            canApply: !isApplying && !hasUnfinishedEasyInput && voltageRestriction == nil && hasStagedChange
                && riskAcknowledged && canWrite && stagedPayloadData != nil,
            error: invalidEasyFields.isEmpty ? error : "Correct the unfinished input or reset the draft before applying.",
            statusMessage: statusMessage
        ) {
            reviewedPayload = stagedPayload
            showApplyConfirmation = true
        }
    }

    private var changeSummary: String {
        var changes: [String] = []
        if setpoints.frequencyEdited {
            changes.append("Frequency: \(formattedFrequency(setpoints.frequencyBaseline)) → \(formattedFrequency(frequency))")
        }
        if setpoints.voltageEdited {
            changes.append("Voltage: \(formattedVoltage(setpoints.voltageBaseline)) → \(formattedVoltage(coreVoltage))")
        }
        return changes.isEmpty ? "Choose a value. Nothing is sent while you edit." : changes.joined(separator: "\n")
    }

    private func loadSetpointsIfAvailable() {
        guard !isApplying else { return }
        setpoints.observe(configuredFrequency: configuredFrequency, configuredVoltage: configuredVoltage, reference: reference)
    }

    private func restoreDraft() {
        setpoints.restore(configuredFrequency: configuredFrequency, configuredVoltage: configuredVoltage, reference: reference)
        easyResetGeneration += 1
        invalidEasyFields.removeAll()
        focusedEasyFields.removeAll()
        error = nil
        statusMessage = nil
    }

    private func loadJournal() {
        guard journal.isEmpty else { return }
        journal = MinerTuningJournalStore.load(deviceID: device.id)
        if journal.isEmpty {
            recordJournal(
                title: "Session opened",
                detail: "Watching the current frequency, core voltage and live miner readings."
            )
        }
    }

    private func recordJournal(title: String, detail: String) {
        journal = MinerTuningJournalStore.record(title: title, detail: detail, to: journal, deviceID: device.id)
    }

    private func applyStagedChange() {
        guard !isApplying, !hasUnfinishedEasyInput, riskAcknowledged, canWrite, voltageRestriction == nil,
            let payload = reviewedPayload, payload == stagedPayload else {
            error = "The reviewed change is no longer available. Review the draft and connection before applying."
            return
        }
        let summary = appliedSummary(changedFields)
        isApplying = true
        error = nil
        statusMessage = nil
        Task { @MainActor in
            defer {
                isApplying = false
                loadSetpointsIfAvailable()
            }
            do {
                let result = try await MinerTuningApplyService().apply(
                    device: device, payload: payload, isDemo: isDemo, writeAuthorized: { canWrite }
                )
                switch result {
                case .verified(let readback):
                    if store.visibleDevices.contains(where: { $0.id == device.id && $0.address == device.address }), !isDemo {
                        store.recordSuccessfulInfo(readback, for: device.id, at: .now)
                    }
                    setpoints.restore(
                        configuredFrequency: readback.raw["frequency"]?.doubleValue,
                        configuredVoltage: readback.raw["coreVoltage"]?.doubleValue,
                        reference: reference
                    )
                    statusMessage = "Verified \(summary) with a fresh miner readback."
                    recordJournal(title: "Tuning applied", detail: "Verified board-wide setpoints: \(summary).")
                case .unverified(let message):
                    error = message
                    recordJournal(title: "Verification pending", detail: message)
                }
                reviewedPayload = nil
            } catch {
                self.error = error.localizedDescription
                recordJournal(title: "Tuning request failed", detail: error.localizedDescription)
            }
        }
    }

    private func appliedSummary(_ changed: (frequency: Bool, coreVoltage: Bool)) -> String {
        var parts: [String] = []
        if changed.frequency { parts.append(formattedFrequency(frequency)) }
        if changed.coreVoltage { parts.append(formattedVoltage(coreVoltage)) }
        return parts.joined(separator: " and ")
    }

    private var liveContextCard: some View {
        MinerTuningLiveContextCard(
            configuredFrequency: formattedFrequency(configuredFrequency), measuredFrequency: formattedFrequency(actualFrequency),
            configuredVoltage: formattedVoltage(configuredVoltage), measuredVoltage: formattedVoltage(measuredVoltage),
            asicErrors: hardwareErrorText, isChecking: store.capabilities.checking.contains(device.id)
        )
    }

    private var hardwareErrorText: String {
        guard let info else { return "Not reported" }
        return MinerShareSummary(info: info).firmwareErrorPercentageDisplay ?? "Not reported"
    }
}
