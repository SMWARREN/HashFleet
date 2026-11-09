import HashFleetCore
import Foundation

enum MinerSettingsCategory: String, CaseIterable {
    case general = "General", cooling = "Cooling", tuning = "Tuning", display = "Display", pools = "Pools"
}

struct MinerSetting {
    enum Input { case text, hostname, integer(Int, Int), decimal, toggle, rotation, poolHost, password, protocolName }
    let key: String
    let title: String
    let category: MinerSettingsCategory
    let input: Input
    let hint: String
    var isSecret: Bool { if case .password = input { return true }; return false }
    var reviewTitle: String {
        MinerPoolSettings.location(key).map { "Slot \($0.id) · \(title)" } ?? title
    }

    static func field(key: String) -> MinerSetting? {
        if let location = MinerPoolSettings.location(key) {
            return MinerPoolSettings.fields(slot: location.id).first { $0.key == key }
        }
        return (all + MinerPoolSettings.roles).first { $0.key == key }
    }

    func observed(in info: MinerInfo) -> JSONValue? {
        guard !isSecret else { return nil }
        if let location = MinerPoolSettings.location(key) {
            return (try? MinerPoolSettings.slots(info))?[location.id]?[location.field]
        }
        return info.raw[key]
    }

    // Matches the app's MinerTuningDraft and the audited firmware encoding constraints.
    // These ranges are not a claim that a clock, voltage or fan setting is safe for a board.
    static let all: [MinerSetting] = [
        .init(key: "hostname", title: "Hostname", category: .general, input: .hostname, hint: "1–32 letters, digits or hyphens; stored in lowercase."),
        .init(key: "statsFrequency", title: "History interval (s)", category: .general, input: .integer(0, 65535), hint: "0 disables the miner's on-device history."),
        .init(key: "autofanspeed", title: "Automatic fan", category: .cooling, input: .toggle, hint: "Enter on or off. Manual mode requires a reported or staged fan speed."),
        .init(key: "manualFanSpeed", title: "Manual fan (%)", category: .cooling, input: .integer(0, 100), hint: "Used with automatic fan off. Lower airflow can raise temperatures."),
        .init(key: "minFanSpeed", title: "Minimum fan (%)", category: .cooling, input: .integer(0, 99), hint: "Used with automatic fan on."),
        .init(key: "temptarget", title: "Target temp (°C)", category: .cooling, input: .integer(35, 66), hint: "Automatic fan temperature target: 35–66 °C."),
        .init(key: "frequency", title: "Frequency (MHz)", category: .tuning, input: .decimal, hint: "Clock changes affect heat, power and stability. Use your board's limits."),
        .init(key: "coreVoltage", title: "Core voltage (mV)", category: .tuning, input: .integer(1, 65535), hint: "Voltage changes can damage hardware. Gamma 601a is limited to 1150 mV."),
        .init(key: "rotation", title: "Rotation (degrees)", category: .display, input: .rotation, hint: "0, 90, 180 or 270 degrees."),
        .init(key: "invertscreen", title: "Invert display", category: .display, input: .toggle, hint: "Enter on or off."),
        .init(
            key: "displayTimeout", title: "Display timeout (min)", category: .display, input: .integer(-1, 65535),
            hint: "-1 keeps the display on, 0 turns it off, and positive values set idle minutes."
        ),
        .init(key: "stratumURL", title: "Primary pool host", category: .pools, input: .poolHost, hint: "Pool hostname only; set its port separately. Existing password is kept."),
        .init(key: "stratumPort", title: "Primary pool port", category: .pools, input: .integer(1, 65535), hint: "Port from 1 through 65535."),
        .init(key: "stratumUser", title: "Primary worker", category: .pools, input: .text, hint: "Pool username or wallet.worker, up to 255 UTF-8 bytes."),
        .init(key: "fallbackStratumURL", title: "Backup pool host", category: .pools, input: .poolHost, hint: "Pool hostname only. Existing password is kept."),
        .init(key: "fallbackStratumPort", title: "Backup pool port", category: .pools, input: .integer(1, 65535), hint: "Port from 1 through 65535."),
        .init(key: "fallbackStratumUser", title: "Backup worker", category: .pools, input: .text, hint: "Pool username or wallet.worker, up to 255 UTF-8 bytes."),
        .init(key: "stratumPassword", title: "Primary password", category: .pools, input: .password, hint: "Type a replacement; an empty value clears it. Esc keeps the existing password."),
        .init(key: "fallbackStratumPassword", title: "Backup password", category: .pools, input: .password, hint: "Type a replacement; an empty value clears it. Esc keeps the existing password."),
        .init(key: "stratumProtocol", title: "Primary protocol", category: .pools, input: .protocolName, hint: "SV1 or SV2, as supported by this pool and firmware."),
        .init(key: "fallbackStratumProtocol", title: "Backup protocol", category: .pools, input: .protocolName, hint: "SV1 or SV2, as supported by this pool and firmware.")
    ]

    func parse(_ draft: String) throws -> JSONValue {
        if isSecret {
            guard draft.utf8.count <= 255, TerminalText.safe(draft) == draft, draft != "*****" else {
                throw SettingsError.message("Use up to 255 bytes without control characters. ***** is reserved; press Esc to keep the current password.")
            }
            return .string(draft)
        }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf8.count <= 255, TerminalText.safe(text) == text else {
            throw SettingsError.message("Enter a value of 1–255 bytes without control characters.")
        }
        switch input {
        case .password: return .string(draft)
        case .protocolName:
            guard ["SV1", "SV2"].contains(text.uppercased()) else { throw SettingsError.message("Enter SV1 or SV2.") }
            return .string(text.uppercased())
        case .text: return .string(text)
        case .hostname: return try parseHostname(text)
        case .poolHost: return try parsePoolHost(text)
        case .integer(let low, let high): return try parseInteger(text, low, high)
        case .decimal: return try parseDecimal(text)
        case .toggle: return try parseToggle(text)
        case .rotation:
            let value = try parseInteger(text, 0, 270)
            guard [0, 90, 180, 270].contains(value.intValue ?? -1) else {
                throw SettingsError.message("Choose 0, 90, 180 or 270 degrees.")
            }
            return value
        }
    }

    private func parseInteger(_ text: String, _ low: Int, _ high: Int) throws -> JSONValue {
        guard text.range(of: "^-?[0-9]+$", options: .regularExpression) != nil,
            let value = Int64(text), value >= low, value <= high else {
            throw SettingsError.message("\(title) requires a whole number from \(low) through \(high).")
        }
        return .integer(value)
    }

    private func parseHostname(_ text: String) throws -> JSONValue {
        let host = text.lowercased()
        guard host.utf8.count <= 32,
            host.range(of: "^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$", options: .regularExpression) != nil else {
            throw SettingsError.message("Use a hostname of 1–32 letters, digits or hyphens, with no leading or trailing hyphen.")
        }
        return .string(host)
    }

    private func parsePoolHost(_ text: String) throws -> JSONValue {
        let device = MinerDevice(name: "", address: text)
        guard !text.contains("://"), !text.contains("/"), let url = try? device.validatedURL(), url.port == nil else {
            throw SettingsError.message("Enter a pool hostname without a scheme, path or port.")
        }
        return .string(text)
    }

    private func parseDecimal(_ text: String) throws -> JSONValue {
        guard text.count <= 64, text.range(of: "^[0-9]+(?:\\.[0-9]+)?$", options: .regularExpression) != nil,
            let number = Double(text), number.isFinite, Float(number).isFinite, (1...65535).contains(number) else {
            throw SettingsError.message(
                "Enter a finite decimal from 1 through 65535 MHz. This is a firmware encoding bound, not a safe clock range."
            )
        }
        return .number(number)
    }

    private func parseToggle(_ text: String) throws -> JSONValue {
        switch text.lowercased() {
        case "on", "true", "1": return .integer(1)
        case "off", "false", "0": return .integer(0)
        default: throw SettingsError.message("Enter on or off.")
        }
    }

    func display(_ value: JSONValue?) -> String {
        if isSecret { return value == nil ? "Keep current" : value == .string("") ? "Clear password" : "•••••• (replace)" }
        guard let value else { return "Not reported" }
        if case .toggle = input, let boolean = value.boolValue { return boolean ? "on" : "off" }
        if case .bool = value { return "Not reported" }
        return value.stringValue.map(TerminalText.safe) ?? "Not reported"
    }

    func matches(_ expected: JSONValue?, _ observed: JSONValue?) -> Bool {
        if isSecret { return false }
        guard let expected, let observed else { return expected == nil && observed == nil }
        if case .toggle = input { return expected.boolValue != nil && expected.boolValue == observed.boolValue }
        switch input {
        case .integer, .decimal, .rotation:
            guard let a = expected.doubleValue, let b = observed.doubleValue else { return false }
            return key == "frequency" ? abs(a - b) <= 0.01 : a == b
        default: return expected == observed
        }
    }

    static func usesPoolSlots(_ info: MinerInfo) -> Bool {
        ["pools", "activePoolIndex", "primaryPoolIndex", "secondaryPoolIndex"].contains { info.raw[$0] != nil }
    }

    static func validate(_ changes: [String: JSONValue], device: MinerDevice, info: MinerInfo) throws {
        for (key, value) in changes {
            guard let field = field(key: key) else { throw SettingsError.message("Unknown setting.") }
            _ = try field.parse(field.isSecret ? value.stringValue ?? "*****" : field.display(value))
            if field.category == .pools, usesPoolSlots(info), MinerPoolSettings.location(key) == nil,
                !MinerPoolSettings.roles.contains(where: { $0.key == key }) {
                throw SettingsError.message("This firmware manages pool slots. Reopen Pools to edit the reported slot configuration.")
            }
        }
        let payload = try MinerPoolSettings.payload(changes: changes, info: info)
        guard try JSONEncoder().encode(JSONValue.object(payload)).count < 10_240 else {
            throw SettingsError.message("This request exceeds the miner's 10 KiB limit. Apply fewer slots at once; certificates cannot be shortened or omitted.")
        }
        let host = (try? device.validatedURL())?.host?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        if host == "192.0.2.221" || info.raw["boardVersion"]?.stringValue?.lowercased() == "601a",
           let voltage = changes["coreVoltage"]?.doubleValue, voltage > 1150 {
            throw SettingsError.message("Gamma 601a has a 1150 mV core-voltage ceiling. Lower the staged voltage.")
        }
        let mode = (changes["autofanspeed"] ?? info.raw["autofanspeed"])?.boolValue
        if changes["manualFanSpeed"] != nil, mode != false {
            throw SettingsError.message("Set Automatic fan to off before changing manual fan speed.")
        }
        if changes["minFanSpeed"] != nil || changes["temptarget"] != nil {
            guard mode == true else { throw SettingsError.message("Turn Automatic fan on before changing its minimum speed or target.") }
        }
        if changes["autofanspeed"] != nil {
            let required = mode == true ? "temptarget" : "manualFanSpeed"
            let field = all.first { $0.key == required }!
            guard let value = changes[required] ?? info.raw[required], (try? field.parse(field.display(value))) != nil else {
                throw SettingsError.message("Set \(field.title) before switching fan mode; the miner has not reported a usable value.")
            }
        }
    }
}

enum SettingsError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self {
        case .message(let message): message
        }
    }
}

enum MinerSettingsWriter {
    struct Result { let info: MinerInfo?; let verified: Bool; let message: String }

    static func apply(device: MinerDevice, original: MinerInfo, changes: [String: JSONValue]) async throws -> Result {
        guard device.kind == .espMiner, !changes.isEmpty else { throw SettingsError.message("No writable settings selected.") }
        try MinerSetting.validate(changes, device: device, info: original)
        let payload = try MinerPoolSettings.payload(changes: changes, info: original)
        let body = try JSONEncoder().encode(JSONValue.object(payload))
        guard body.count < 10_240 else {
            throw SettingsError.message("This request exceeds the miner's 10 KiB limit. Apply fewer slots at once; certificates cannot be shortened or omitted.")
        }
        let client = MinerAPIClient(device: device)
        let fresh: MinerInfo
        do { fresh = try await client.info() } catch { throw SettingsError.message("Could not read fresh settings. Nothing was sent; reconnect and reopen settings.") }
        try Task.checkCancellation()
        try MinerSetting.validate(changes, device: device, info: fresh)
        try MinerPoolSettings.checkBaseline(changes: changes, original: original, fresh: fresh)
        for key in ["ASICModel", "boardVersion", "macAddr"] {
            if let before = original.raw[key], let now = fresh.raw[key], before != now {
                throw SettingsError.message("The miner identity changed during editing. Nothing was sent; reopen settings.")
            }
        }
        var compared = Set(changes.keys)
        if !compared.isDisjoint(with: ["autofanspeed", "manualFanSpeed", "minFanSpeed", "temptarget"]) {
            compared.formUnion(["autofanspeed", "manualFanSpeed", "temptarget"])
        }
        for field in compared.compactMap({ MinerSetting.field(key: $0) }) where !field.isSecret {
            guard field.matches(field.observed(in: original), field.observed(in: fresh)) else {
                throw SettingsError.message("\(field.title) changed since you opened settings. Nothing was sent; reopen settings to review fresh values.")
            }
        }
        try Task.checkCancellation()
        do { _ = try await client.execute(.settings, body: body) } catch {
            // A timeout can happen after the firmware saved a request. Never retry it automatically
            // or echo a remote response body that could contain credentials.
            return Result(info: nil, verified: false,
                message: "The write could not be confirmed. It may have reached the miner. Check fresh settings before trying again; no retry was sent.")
        }
        do {
            let readback = try await client.info()
            let fields = changes.keys.compactMap { MinerSetting.field(key: $0) }
            let passwordChanged = fields.contains(where: \.isSecret)
            let matched = fields.filter { !$0.isSecret }
                .allSatisfy { $0.matches(changes[$0.key], $0.observed(in: readback)) }
                && MinerPoolSettings.matches(payload, original: original, readback: readback)
            if matched, passwordChanged {
                return Result(info: readback, verified: false,
                    message: "Request accepted. Non-password settings verified; the miner hides passwords, so their new values cannot be verified. Check the pool connection before retrying.")
            }
            return Result(info: readback, verified: matched, message: matched
                ? "Saved and verified against fresh miner settings."
                : "Request accepted, but fresh settings do not match every change. Your draft is kept. Check the miner before trying again.")
        } catch {
            return Result(info: nil, verified: false,
                message: "Request accepted, but fresh settings could not be read. Your draft is kept. Reconnect and check the miner before trying again.")
        }
    }
}
