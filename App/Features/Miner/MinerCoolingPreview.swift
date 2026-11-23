import SwiftUI
import HashFleetCore

/// Validated configuration, not sensor data. A missing field never becomes an editable default.
struct MinerCoolingPreviewDraft: Equatable {
    enum Field: String {
        case target = "temptarget"
        case manual = "manualFanSpeed"
        case minimum = "minFanSpeed"

        var bounds: ClosedRange<Int> {
            switch self {
            case .target: MinerTuningDraft.coolingTargetBounds
            case .manual: MinerTuningDraft.manualFanSpeedBounds
            case .minimum: MinerTuningDraft.minimumFanSpeedBounds
            }
        }

        var title: String {
            switch self {
            case .target: "Temperature target"
            case .manual: "Manual fan speed"
            case .minimum: "Minimum fan speed"
            }
        }

        var suffix: String { self == .target ? "°C" : "%" }
        var spokenUnit: String { self == .target ? "degrees Celsius" : "percent" }
    }

    private(set) var automatic: Bool?
    private var values: [Field: Int] = [:]

    init(info: MinerInfo?) {
        automatic = info?.raw["autofanspeed"]?.boolValue
        for field: Field in [.target, .manual, .minimum] {
            if let number = info?.raw[field.rawValue]?.doubleValue,
               let value = Int(exactly: number), field.bounds.contains(value) {
                values[field] = value
            }
        }
    }

    subscript(field: Field) -> Int? { values[field] }

    var activeFields: [Field] {
        switch automatic {
        case true?: [.target, .minimum]
        case false?: [.manual]
        case nil: []
        }
    }

    func supportsMode(automatic: Bool) -> Bool {
        self.automatic != nil && self[automatic ? .target : .manual] != nil
    }

    mutating func select(automatic: Bool) {
        if supportsMode(automatic: automatic) { self.automatic = automatic }
    }

    func adjusted(_ field: Field, increasing: Bool) -> Int? {
        guard activeFields.contains(field), let current = self[field] else { return nil }
        let next = current + (increasing ? 1 : -1)
        return field.bounds.contains(next) ? next : nil
    }

    mutating func adjust(_ field: Field, increasing: Bool) {
        if let next = adjusted(field, increasing: increasing) { values[field] = next }
    }

    /// Copy only changed, active settings. A mode switch includes its reported active setpoint.
    func changes(from applied: Self) -> [String: JSONValue] {
        guard let automatic, supportsMode(automatic: automatic) else { return [:] }
        var changes: [String: JSONValue] = [:]
        let modeChanged = automatic != applied.automatic
        if modeChanged { changes["autofanspeed"] = .integer(automatic ? 1 : 0) }
        for field in activeFields {
            if let value = self[field], value != applied[field] || (modeChanged && field != .minimum) {
                changes[field.rawValue] = .integer(Int64(value))
            }
        }
        return changes
    }

    func applying(_ changes: [String: JSONValue]) -> Self {
        var applied = self
        if let mode = changes["autofanspeed"]?.boolValue { applied.select(automatic: mode) }
        for field in applied.activeFields {
            if let value = changes[field.rawValue]?.intValue, field.bounds.contains(value), self[field] != nil {
                applied.values[field] = value
            }
        }
        return applied
    }

    /// Unlike the offline fixture, a live mode change does not rewrite its unchanged setpoint.
    /// Use the same field validators as the standard Cooling page before selecting the changed keys.
    func liveChanges(from baseline: Self) throws -> [String: JSONValue] {
        guard let automatic, baseline.supportsMode(automatic: automatic), supportsMode(automatic: automatic) else {
            throw MinerToolError.message("Cooling configuration is unavailable. Refresh the miner first.")
        }
        var validated = try MinerTuningDraft.coolingPayload(
            automatic: automatic, manualSpeed: self[.manual].map(String.init) ?? "",
            target: self[.target].map(String.init) ?? ""
        ).objectValue ?? [:]
        if automatic, let minimum = self[.minimum], minimum != baseline[.minimum] {
            validated[Field.minimum.rawValue] = try MinerTuningDraft.minimumFanSpeedPayload(String(minimum))
                .objectValue?[Field.minimum.rawValue]
        }
        return validated.filter { key, _ in
            if key == "autofanspeed" { return automatic != baseline.automatic }
            guard let field = Field(rawValue: key) else { return false }
            return baseline[field] != nil && self[field] != baseline[field]
        }
    }
}

/// The demo has no send closure. Only the separate live phone route supplies a destination.
struct MinerCoolingPreview: View {
    struct LiveDestination {
        let target: String
        let save: @MainActor (MinerCoolingPreviewDraft, MinerCoolingPreviewDraft) async throws -> MinerCoolingPreviewDraft
    }

    let mode: FleetPreferences.DashboardMode
    let info: MinerInfo?
    let canEdit: Bool
    private let live: LiveDestination?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var applied: MinerCoolingPreviewDraft
    @State private var draft: MinerCoolingPreviewDraft
    @State private var review: Review?
    @State private var result: String?
    @State private var failure: String?
    @State private var saveTask: Task<Void, Never>?

    init(mode: FleetPreferences.DashboardMode, info: MinerInfo?, canEdit: Bool, live: LiveDestination? = nil) {
        self.mode = mode
        self.info = info
        self.canEdit = canEdit
        self.live = live
        // Seed once. Updating a reading must not overwrite a user's draft.
        let initial = MinerCoolingPreviewDraft(info: info)
        _applied = State(initialValue: initial)
        _draft = State(initialValue: initial)
    }

    struct Review: Identifiable {
        let id = UUID()
        let changes: [String: JSONValue]
        let json: String
    }

    private var changes: [String: JSONValue] {
        if live != nil { return (try? draft.liveChanges(from: applied)) ?? [:] }
        return draft.changes(from: applied)
    }
    private var isApplying: Bool { saveTask != nil }
    private var showsControls: Bool {
        (canEdit || isApplying) && draft.automatic.map { draft.supportsMode(automatic: $0) } == true
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let live {
                    Label(live.target, systemImage: "network")
                        .fleetFont(.footnote, weight: .semibold)
                        .foregroundStyle(FleetTheme.secondary)
                } else {
                    Label("Demo only · No miner connected", systemImage: "sparkles")
                        .fleetFont(.footnote, weight: .semibold)
                        .foregroundStyle(FleetTheme.accent)
                }
                readings
                if showsControls {
                    controls.disabled(isApplying)
                    Label("Too little cooling can overheat a miner. Thermal protection settings are unchanged.",
                          systemImage: "exclamationmark.triangle")
                        .fleetFont(.footnote)
                        .foregroundStyle(FleetTheme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                    actions
                } else {
                    Label("Cooling controls unavailable for this miner.", systemImage: "lock")
                        .fleetFont(.subheadline)
                        .foregroundStyle(FleetTheme.secondary)
                }
                if review == nil, let failure {
                    failureNotice(failure)
                }
            }
            .fleetPageContainer(compactMaxWidth: FleetLayout.readableWidth)
        }
        .accessibilityIdentifier("settings.cooling.preview")
        .background(FleetTheme.canvas)
        .navigationTitle("Cooling")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .principal) { MinerNavigationTitle(pageTitle: "Cooling") } }
        .sheet(item: $review) { request in reviewSheet(request) }
        .onDisappear { saveTask?.cancel() }
        // While saving, the post-write refresh can publish before the task has examined its result.
        // Reconcile once it finishes, including on a mismatch, without hiding its error message.
        .onChange(of: live == nil || isApplying ? nil : MinerCoolingPreviewDraft(info: info)) { _, value in
            guard let latest = value, latest != applied else { return }
            if !changes.isEmpty && failure == nil {
                failure = "Cooling settings changed on the miner. Review the latest values before applying."
            }
            result = nil
            review = nil
            applied = latest
            draft = latest
        }
    }

    private var readings: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        let temperature = info.flatMap { FleetFormat.sensor($0, keys: "temp", allowNegative: true) }
        let speed = info.flatMap { FleetFormat.sensor($0, keys: "fanspeed") }.flatMap { $0 <= 100 ? $0 : nil }
        let rpm = info.flatMap { FleetFormat.sensor($0, keys: "fanrpm") }
        return MinerControlsCard {
            Label(live != nil && !canEdit ? "Last reported readings" : "Current readings", systemImage: "thermometer")
                .fleetFont(.headline, weight: .semibold)
                .accessibilityAddTraits(.isHeader)
            layout {
                reading("Chip temperature", value: FleetFormat.measurement(temperature, unit: "°C"), id: "temperatureReading")
                reading("Fan speed", value: FleetFormat.measurement(speed, unit: "%"),
                        detail: rpm.map { FleetFormat.measurement($0, unit: "RPM") }, id: "fanSpeedReading")
            }
        }
    }

    private func reading(_ title: String, value: String, detail: String? = nil, id: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).fleetFont(.caption).foregroundStyle(FleetTheme.secondary)
            Text(value).fleetFont(.title2, weight: .bold).monospacedDigit()
                .accessibilityIdentifier("settings.cooling.\(id)")
            if let detail { Text(detail).fleetFont(.caption).foregroundStyle(FleetTheme.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var controls: some View {
        MinerControlsCard {
            Label("Fan control", systemImage: "fan")
                .fleetFont(.headline, weight: .semibold)
                .accessibilityAddTraits(.isHeader)
            modeSelector
            Text(draft.automatic == true ? "Adjusts fan speed to reach your target." : "Keeps the fan at the speed you set.")
                .fleetFont(.caption).foregroundStyle(FleetTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(draft.activeFields, id: \.self) { field in
                if let value = draft[field] {
                    Divider().overlay(FleetTheme.separator)
                    adjuster(field, value: value)
                }
            }
        }
    }

    private var modeTitle: String { draft.automatic == true ? "Automatic" : "Manual" }

    @ViewBuilder private var modeSelector: some View {
        if draft.supportsMode(automatic: true) && draft.supportsMode(automatic: false) {
            if dynamicTypeSize.isAccessibilitySize {
                // Keep one selector while letting the visible label grow instead of truncating inside a segment.
                let selection = Binding(get: { draft.automatic == true }, set: selectMode(automatic:))
                Menu {
                    Picker("Fan mode", selection: selection) {
                        Text("Automatic").tag(true)
                        Text("Manual").tag(false)
                    }
                } label: {
                    HStack {
                        Text(modeTitle)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.up.chevron.down")
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(FleetPrimaryButtonStyle(tone: .secondary, size: .compact, fullWidth: true))
                .accessibilityLabel("Fan mode")
                .accessibilityValue(modeTitle)
                .accessibilityIdentifier("cooling.mode.menu")
            } else {
                HStack(spacing: 0) {
                    modeButton("Automatic", automatic: true, id: "cooling.mode.automatic")
                    modeButton("Manual", automatic: false, id: "cooling.mode.manual")
                }
                .background(FleetTheme.raised, in: Capsule())
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Fan mode")
            }
        } else {
            Text("\(modeTitle) mode")
                .fleetFont(.subheadline, weight: .semibold)
                .accessibilityIdentifier("cooling.mode.fixed")
        }
    }

    private func modeButton(_ title: String, automatic: Bool, id: String) -> some View {
        let selected = draft.automatic == automatic
        return Button {
            selectMode(automatic: automatic)
        } label: {
            Text(title)
                .fleetFont(.subheadline, weight: .semibold)
                .foregroundStyle(selected ? FleetTheme.ink : FleetTheme.secondary)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background {
                    if selected { Capsule().fill(FleetTheme.ink.opacity(0.14)).padding(3) }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(id)
    }

    private func selectMode(automatic: Bool) {
        guard canEdit, !isApplying, draft.automatic != automatic, draft.supportsMode(automatic: automatic) else { return }
        draft.select(automatic: automatic)
        result = nil
        failure = nil
    }

    private func adjuster(_ field: MinerCoolingPreviewDraft.Field, value: Int) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            Text(field.title)
                .fleetFont(.subheadline, weight: .semibold)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(true)
            HStack(spacing: 6) {
                stepButton(field, increasing: false)
                Text("\(value) \(field.suffix)")
                    .fleetFont(.title3, weight: .semibold).monospacedDigit()
                    .frame(minWidth: 58, maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil)
                    .accessibilityLabel("\(field.title): \(value) \(field.spokenUnit)")
                    .accessibilityIdentifier("cooling.\(field.rawValue).value")
                stepButton(field, increasing: true)
            }
        }
    }

    private func stepButton(_ field: MinerCoolingPreviewDraft.Field, increasing: Bool) -> some View {
        Button {
            draft.adjust(field, increasing: increasing)
            result = nil
            failure = nil
        } label: {
            Image(systemName: increasing ? "plus" : "minus")
        }
        .buttonStyle(FleetPrimaryButtonStyle(tone: .secondary, size: .compact))
        .buttonRepeatBehavior(.enabled)
        .disabled(draft.adjusted(field, increasing: increasing) == nil)
        .accessibilityLabel("\(increasing ? "Increase" : "Decrease") \(field.title.lowercased())")
        .accessibilityIdentifier("cooling.\(field.rawValue).\(increasing ? "increase" : "decrease")")
    }

    var actions: some View {
        let direct = mode == .essentials
        let title = direct ? "Apply Changes" : "Review Changes"
        let pending = direct && isApplying
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                guard canEdit, !isApplying, !changes.isEmpty else { return }
                if direct {
                    apply(changes)
                } else if let json = try? JSONValue.object(changes).prettyPrinted() {
                    review = Review(changes: changes, json: json)
                }
            } label: {
                FleetPendingButtonLabel(title: title, pendingTitle: "Applying…", isPending: pending)
            }
            .buttonStyle(FleetPrimaryButtonStyle(size: .compact, fullWidth: true))
            .disabled(!canEdit || changes.isEmpty || isApplying)
            .accessibilityLabel(pending ? "Applying…" : title)
            .accessibilityIdentifier("cooling.commit")

            if let result {
                Label(result, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(FleetTheme.positive)
                    .accessibilityIdentifier("cooling.result")
            } else if failure == nil {
                Text(changes.isEmpty ? "No pending changes." : "Changes stay here until you \(direct ? "apply" : "review and apply") them.")
                    .foregroundStyle(FleetTheme.secondary)
                    .opacity(isApplying ? 0 : 1)
                    .accessibilityHidden(isApplying)
            }
        }
        .fleetFont(.footnote)
    }

    private func failureNotice(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .fleetFont(.footnote).foregroundStyle(FleetTheme.warning)
            .accessibilityIdentifier("cooling.error")
    }

    func reviewSheet(_ request: Review) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(live.map { "Apply these cooling settings to \($0.target)? Nothing is sent until you apply." }
                         ?? "Review the cooling settings for this change. This demo does not send a request.")
                        .fleetFont(.subheadline).foregroundStyle(FleetTheme.secondary)
                    MinerControlsCard {
                        Label("JSON preview", systemImage: "curlybraces")
                            .fleetFont(.headline, weight: .semibold)
                        Text(request.json)
                            .fleetFont(.body, design: .monospaced)
                            .textSelection(.enabled)
                            .accessibilityIdentifier("cooling.review.json")
                    }
                    Button {
                        apply(request.changes)
                    } label: {
                        FleetPendingButtonLabel(title: "Apply Changes", pendingTitle: "Applying…", isPending: isApplying)
                    }
                    .buttonStyle(FleetPrimaryButtonStyle(size: .compact, fullWidth: true))
                    .disabled(!canEdit || !showsControls || isApplying || request.changes != changes)
                    .accessibilityLabel(isApplying ? "Applying…" : "Apply Changes")
                    .accessibilityIdentifier("cooling.review.apply")
                    if let failure { failureNotice(failure) }
                }
                .fleetPageContainer(compactMaxWidth: FleetLayout.readableWidth)
            }
            .background(FleetTheme.canvas)
            .navigationTitle("Review cooling changes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { review = nil }
                        .disabled(isApplying)
                        .accessibilityIdentifier("cooling.review.cancel")
                }
            }
        }
        .interactiveDismissDisabled(isApplying)
    }

    private func apply(_ changes: [String: JSONValue]) {
        guard canEdit, showsControls, !isApplying, !changes.isEmpty, self.changes == changes else { return }
        if let live {
            let baseline = applied, requested = draft
            failure = nil
            result = nil
            saveTask = Task { @MainActor in
                defer { saveTask = nil }
                do {
                    let readback = try await live.save(baseline, requested)
                    applied = readback
                    draft = readback
                    result = "Cooling changes verified on \(live.target)."
                    review = nil
                } catch {
                    failure = error.localizedDescription
                }
            }
            return
        }
        applied = applied.applying(changes)
        draft = applied
        result = "Applied in this demo. Nothing sent."
        review = nil
    }
}
