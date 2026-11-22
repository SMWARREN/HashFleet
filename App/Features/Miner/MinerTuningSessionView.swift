import SwiftUI
import HashFleetCore

/// A board-aware tuning workspace shared by the iPhone and the Mac-designed-for-iPad app.
///
/// The firmware settings endpoint exposes one frequency field for the board, not a writable
/// frequency per ASIC. The numbered cards make the ASIC layout easy to scan while every card edits
/// the same board-wide setpoint. Values beyond the reported reference are allowed for deliberate
/// overclock review, but turn red and remain subject to the existing final APPLY gate.
struct MinerTuningSessionView: View {
    struct InlineAdvanced {
        let isExpanded: Binding<Bool>
        let isBusy: Binding<Bool>
        let jumpToReview: () -> Void
    }

    let device: MinerDevice
    @Bindable var store: FleetStore
    var insights: MiningInsightsStore?
    private let reviewPresentation: Binding<Bool>?
    private let inlineAdvanced: InlineAdvanced?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    #if !os(macOS)
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif
    @State private(set) var setpoints = MinerTuningSetpointState()
    @State private var riskAcknowledged = false
    @State private var isApplying = false
    @State private var reviewedPayload: JSONValue?
    @State private var showApplyConfirmation = false
    @State private var journal: [MinerTuningJournalEntry] = []
    @State private var error: String?
    @State private var statusMessage: String?
    @State private var controlMode: MinerTuningControlMode = .easy
    @State private var showEasyDetails = false
    @FocusState private var focusedEasyField: MinerTuningEasyField?
    @State private var invalidEasyFields: Set<MinerTuningEasyField> = []
    @State private var easyResetGeneration = 0

    private var isStandaloneEssentials: Bool {
        #if os(iOS)
        inlineAdvanced == nil && reviewPresentation == nil && horizontalSizeClass == .compact
            && store.preferences.dashboardMode == .essentials
        #else
        false
        #endif
    }
    var compactAdvanced: Bool { inlineAdvanced != nil || isStandaloneEssentials }
    private var isActive: Bool { inlineAdvanced?.isExpanded.wrappedValue ?? true }
    var editsLocked: Bool { isApplying || showApplyConfirmation }

    private var isEditingCustomValue: Bool {
        #if os(macOS)
        // No software keyboard covers the review bar on Mac, and focus can linger indefinitely.
        false
        #else
        focusedEasyField != nil
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

    init(device: MinerDevice, store: FleetStore, insights: MiningInsightsStore? = nil,
         reviewPresentation: Binding<Bool>? = nil, inlineAdvanced: InlineAdvanced? = nil) {
        self.device = device
        self.store = store
        self.insights = insights
        self.reviewPresentation = reviewPresentation
        self.inlineAdvanced = inlineAdvanced
        _controlMode = State(initialValue: reviewPresentation == nil && inlineAdvanced == nil ? .easy : .advanced)
    }

    /// True when either dial is past the firmware's reported reference.
    var isAnyBeyondReference: Bool { isBeyondReference || isVoltageBeyondReference }

    var frequency: Double { setpoints.frequency ?? 0 }
    var coreVoltage: Double { setpoints.coreVoltage ?? 0 }
    var frequencyBinding: Binding<Double> {
        Binding(get: { frequency }, set: {
            setpoints.editFrequency($0)
            error = nil
            statusMessage = nil
        })
    }
    var voltageBinding: Binding<Double> {
        Binding(get: { coreVoltage }, set: {
            setpoints.editVoltage($0)
            error = nil
            statusMessage = nil
        })
    }
    var voltageRestriction: String? {
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
            && isActive
            && store.visibleDevices.contains(where: { $0.id == device.id && $0.address == device.address })
            && MinerWriteAvailability.allows(store.snapshot(for: device.id))
            && (inlineAdvanced == nil || info.map { NumberFirstPreview.minerAvailability($0, device: device, store: store).tuning } == true)
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
        presentedContent
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
                if isActive { loadJournal() }
                loadSetpointsIfAvailable()
            }
            .onChange(of: isActive) { _, active in
                if active {
                    loadJournal()
                    loadSetpointsIfAvailable()
                }
            }
            .onChange(of: editsLocked) { _, locked in
                inlineAdvanced?.isBusy.wrappedValue = locked
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
            .task(id: isActive ? device.id : nil) {
                guard isActive, !isDemo, capabilityReport?.asic == nil else { return }
                await store.capabilities.check(device: device, isDemo: false)
                loadSetpointsIfAvailable()
            }
    }

    @ViewBuilder private var presentedContent: some View {
        if let inlineAdvanced {
            if isActive {
                compactAdvancedContent
                    .toolbar {
                        ToolbarItem(placement: FleetToolbarLocation.trailing) { resetButton }
                        ToolbarItem(placement: FleetToolbarLocation.trailing) {
                            reviewShortcut(action: inlineAdvanced.jumpToReview)
                        }
                    }
            }
        } else {
            sessionPage
        }
    }

    private var sessionPage: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                if isStandaloneEssentials && pinsEasyReview {
                    advancedSwitch
                        .padding(.horizontal, FleetLayout.pagePadding)
                        .padding(.vertical, 8)
                        .fleetReadableWidth()
                        .background(FleetTheme.canvas)
                }
                sessionScroll(proxy: proxy)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("tuningSession.screen")
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
                    resetButton
                }
                if !isEditingCustomValue || FleetLayout.isMac {
                    ToolbarItem(placement: FleetToolbarLocation.trailing) {
                        reviewShortcut {
                            if controlMode == .easy { showEasyDetails = true }
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                                proxy.scrollTo(controlMode == .easy ? "tuningSession.easyDetails" : "tuningSession.applySection", anchor: .top)
                            }
                        }
                    }
                }
            }
            .fleetEditingDone(
                isEditingCustomValue,
                identifier: "\(easyControlPrefix(focusedEasyField ?? .frequency)).keyboardDone"
            ) { focusedEasyField = nil }
        }
    }

    private func sessionScroll(proxy: ScrollViewProxy) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: compactAdvanced ? 12 : 16) {
                if isStandaloneEssentials && !pinsEasyReview { advancedSwitch }
                if controlMode == .easy {
                    if !isStandaloneEssentials { modePicker }
                    easyControlsSection
                    if !pinsEasyReview {
                        timedReview.id("tuningSession.applySection")
                    }
                    easyDetails(proxy: proxy)
                } else if isStandaloneEssentials {
                    compactAdvancedContent
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
                        timedReview.id("tuningSession.applySection")
                    }
                    MinerTuningJournalCard(journal: journal)
                }
            }
            .fleetPageContainer(compactMaxWidth: FleetLayout.readableWidth)
        }
        .scrollIndicators(.hidden)
        .fleetEditingScroll()
        .fleetRevealEditingField(focusedEasyField, using: proxy)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if controlMode == .easy && pinsEasyReview && !isEditingCustomValue {
                timedReview
                    .fleetPageContainer(compactMaxWidth: FleetLayout.readableWidth)
                    .background(FleetTheme.canvas)
                    .accessibilityIdentifier("tuningSession.easyActionBar")
            }
        }
    }
}

extension MinerTuningSessionView {
    private var acknowledgementKey: String {
        "app.hashfleet.tuningRiskAcknowledged.\(device.id.uuidString)"
    }

    private var advancedSwitch: some View {
        MinerTuningAdvancedSwitch(isOn: Binding(
            get: { controlMode == .advanced },
            set: { controlMode = $0 ? .advanced : .easy }
        ))
        .disabled(editsLocked || hasUnfinishedEasyInput)
    }

    private var resetButton: some View {
        Button("Reset draft", systemImage: "arrow.counterclockwise") { restoreDraft() }
            .labelStyle(.iconOnly)
            .disabled((!hasStagedChange && !hasUnfinishedEasyInput) || editsLocked)
            .accessibilityIdentifier("tuningSession.reset")
    }

    private func reviewShortcut(action: @escaping () -> Void) -> some View {
        Button("Review JSON and apply", systemImage: "arrow.down.to.line.compact", action: action)
            .labelStyle(.iconOnly)
            .accessibilityIdentifier("tuningSession.jump.apply")
    }

    private var compactAdvancedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            TimelineView(.periodic(from: .now, by: MinerSnapshotFreshness.refreshInterval)) { _ in
                if isDemo || !canWrite {
                    Label(isDemo ? "Demo · no changes are sent" : "Read only · tuning changes unavailable",
                          systemImage: "lock.fill")
                        .fleetFont(.footnote)
                        .foregroundStyle(FleetTheme.warning)
                        .accessibilityIdentifier("tuningSession.writeRestriction")
                }
            }
            safetyCard
            advancedControlsSection
            timedReview.id("tuningSession.applySection")
        }
    }

    private var modePicker: some View {
        Picker("Tuner mode", selection: Binding(get: { controlMode }, set: { mode in
            if let reviewPresentation, mode == .easy {
                reviewPresentation.wrappedValue = false
            } else {
                controlMode = mode
            }
        })) {
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
            accessibilityPrefix: easyControlPrefix(field),
            valueIdentifier: field == .frequency ? "tuningSession.frequencyValue" : "tuningSession.voltageValue",
            resetGeneration: easyResetGeneration,
            sessionFocus: $focusedEasyField,
            onValidityChanged: { valid in
                if valid { invalidEasyFields.remove(field) } else { invalidEasyFields.insert(field) }
            }
        )
    }

    private func easyControlPrefix(_ field: MinerTuningEasyField) -> String {
        field == .frequency ? "tuningSession.master" : "tuningSession.voltage"
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

    private var safetyCard: some View {
        MinerTuningSafetyCard(
            riskAcknowledged: $riskAcknowledged,
            isBeyondReference: isAnyBeyondReference,
            hasReference: referenceMaximum != nil || voltageReferenceMaximum != nil,
            voltageRestriction: voltageRestriction,
            compact: compactAdvanced
        )
    }

    private var reviewSection: some View {
        MinerTuningReview(
            mode: controlMode, compactAdvanced: compactAdvanced, summary: changeSummary, stagedJSON: stagedJSON,
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
        focusedEasyField = nil
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
}
