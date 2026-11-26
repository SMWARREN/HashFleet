import HashFleetCore
import Foundation

/// Driver-aware capability and field rules for the CLI, matching the iOS and macOS apps.
enum MinerDriverProfile {
    static let axeOSFamilies: Set<String> = [
        "bitaxe", "nerdqaxe", "nerdoctaxe", "bitfortun", "bitforge", "warpaxe"
    ]

    static func resolvedFamily(device: MinerDevice, info: MinerInfo) -> String {
        let explicit = (device.firmwareFamily ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !explicit.isEmpty { return explicit }
        if let detected = MinerFirmwareAdapter.detectedFamily(from: info), !detected.isEmpty {
            return detected
        }
        if let rawFamily = info.raw["firmwareFamily"]?.stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines), !rawFamily.isEmpty {
            return rawFamily
        }
        if (try? device.validatedURL())?.port == MinerFirmwareAdapter.portCgminer {
            return "canaan"
        }
        return "bitaxe"
    }

    static func resolvedDevice(_ device: MinerDevice, info: MinerInfo) -> MinerDevice {
        var updated = device
        let existing = (device.firmwareFamily ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if existing.isEmpty {
            updated.firmwareFamily = resolvedFamily(device: device, info: info)
        }
        return updated
    }

    static func capabilities(device: MinerDevice, info: MinerInfo) -> MinerDriverCapabilities {
        let family = resolvedFamily(device: device, info: info)
        return MinerDriverCapabilities.forFamily(family, info: info)
    }

    static func isAxeOS(_ family: String) -> Bool {
        axeOSFamilies.contains(family.lowercased())
    }

    /// True for firmwares whose automatic fan mode uses a temperature target.
    /// ThorOS, NMAxe, and Canaan Avalon do not use `temptarget`.
    static func supportsAutoFanTarget(_ family: String) -> Bool {
        let lower = family.lowercased()
        return isAxeOS(lower) || lower == "axeforge" || lower == "harloos"
    }

    /// False for Canaan Avalon, where `FanR` is live duty and auto/manual mode is not reported.
    static func reportsFanMode(_ family: String) -> Bool {
        let lower = family.lowercased()
        return lower != "canaan" && lower != "canaannano3"
    }

    /// Matches `MinerCoolingPreviewDraft.automaticMode`: bool, or non-zero integer (including PID `2`).
    static func automaticFanFlag(_ value: JSONValue?) -> Bool? {
        if let flag = value?.boolValue { return flag }
        guard let number = value?.doubleValue, number.isFinite, number >= 0 else { return nil }
        return number != 0
    }

    static func supportsKey(_ key: String, device: MinerDevice, info: MinerInfo) -> Bool {
        let family = resolvedFamily(device: device, info: info).lowercased()
        let caps = MinerDriverCapabilities.forFamily(family, info: info)
        guard !caps.isReadOnly else { return false }

        if MinerPoolSettings.location(key) != nil
            || MinerPoolSettings.roles.contains(where: { $0.key == key }) {
            return caps.canSetPool && isAxeOS(family)
        }
        return supportsStandardKey(key, family: family, caps: caps)
    }

    private static func supportsStandardKey(
        _ key: String,
        family: String,
        caps: MinerDriverCapabilities
    ) -> Bool {
        switch key {
        case "hostname":
            return isAxeOS(family) || family == "harloos"
        case "statsFrequency":
            return isAxeOS(family)
        case "workmode":
            return caps.canSetWorkmode
        case "autofanspeed", "manualFanSpeed":
            return caps.canSetFan
        case "minFanSpeed":
            return caps.canSetFan && (isAxeOS(family) || family == "axeforge")
        case "temptarget":
            return caps.canSetFan && supportsAutoFanTarget(family)
        case "frequency":
            return caps.canSetFrequency
        case "coreVoltage":
            // Canaan reports measured chip average (PVT_V0) rather than an mV setpoint.
            return caps.canSetVoltage && family != "canaan"
        case "rotation", "displayTimeout":
            return isAxeOS(family) || family == "axeforge"
        case "invertscreen":
            return isAxeOS(family)
        case "stratumProtocol", "fallbackStratumProtocol":
            return caps.canSetPool && isAxeOS(family)
        case "stratumURL", "stratumPort", "stratumUser", "stratumPassword",
             "fallbackStratumURL", "fallbackStratumPort", "fallbackStratumUser", "fallbackStratumPassword":
            return caps.canSetPool
        default:
            return false
        }
    }

    static func adjustedField(_ setting: MinerSetting, device: MinerDevice, info: MinerInfo) -> MinerSetting {
        let family = resolvedFamily(device: device, info: info).lowercased()
        let caps = MinerDriverCapabilities.forFamily(family, info: info)
        switch setting.key {
        case "manualFanSpeed":
            let low = caps.fanMinPct
            let hint = low > 0
                ? "Manual fan duty (\(low)–100%). Lower airflow can raise temperatures."
                : setting.hint
            return MinerSetting(
                key: setting.key, title: setting.title, category: setting.category,
                input: .integer(low, 100), hint: hint
            )
        case "minFanSpeed" where family == "axeforge":
            return MinerSetting(
                key: setting.key, title: setting.title, category: setting.category,
                input: .integer(10, 100), hint: "Minimum automatic fan speed: 10–100%."
            )
        case "temptarget" where family == "axeforge":
            return MinerSetting(
                key: setting.key, title: setting.title, category: setting.category,
                input: .integer(40, 70), hint: "Automatic fan temperature target: 40–70 °C."
            )
        case "temptarget" where family == "harloos":
            return MinerSetting(
                key: setting.key, title: setting.title, category: setting.category,
                input: .integer(30, 70), hint: "Automatic fan temperature target: 30–70 °C."
            )
        default:
            return setting
        }
    }

    static func field(key: String, device: MinerDevice, info: MinerInfo) -> MinerSetting? {
        guard let base = MinerSetting.field(key: key) else { return nil }
        return adjustedField(base, device: device, info: info)
    }

    static func fields(
        for category: MinerSettingsCategory,
        device: MinerDevice,
        info: MinerInfo
    ) -> [MinerSetting] {
        MinerSetting.all
            .filter { $0.category == category && supportsKey($0.key, device: device, info: info) }
            .map { adjustedField($0, device: device, info: info) }
    }

    static func availableCategories(device: MinerDevice, info: MinerInfo) -> [MinerSettingsCategory] {
        let family = resolvedFamily(device: device, info: info).lowercased()
        let caps = MinerDriverCapabilities.forFamily(family, info: info)
        guard !caps.isReadOnly else { return [] }
        return MinerSettingsCategory.allCases.filter { category in
            if category == .pools, caps.canSetPool, isAxeOS(family), MinerSetting.usesPoolSlots(info) {
                return true
            }
            return !fields(for: category, device: device, info: info).isEmpty
        }
    }
}
