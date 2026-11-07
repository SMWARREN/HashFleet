import HashFleetCore
import Foundation

@MainActor
final class MinerSettingsEditor {
    private enum Page { case fields, editing, review, saving, result, discard }
    let device: MinerDevice
    private var original: MinerInfo
    private let writable: Bool
    private let unavailableReason: String?
    private var page = Page.fields
    private var category = MinerSettingsCategory.general
    private var selectedSlot: Int?
    private var selection = 0
    private var changes: [String: JSONValue] = [:]
    private var textBytes: [UInt8] = []
    private var message = ""
    private var resultVerified = false
    private var task: Task<Void, Never>?
    private var reviewOffset = 0
    private var reviewMaximum = 0
    private var usableSize = true
    private(set) var closed = false
    private(set) var quit = false

    init(miner: MinerStatusSnapshot, demo: Bool) {
        device = miner.device
        original = miner.info ?? MinerInfo(raw: [:])
        let slots = (try? MinerPoolSettings.slots(original)) ?? [:]
        let primary = MinerPoolSettings.exactID(original.raw["primaryPoolIndex"])
        selectedSlot = primary.flatMap { slots[$0] == nil ? nil : $0 } ?? slots.keys.sorted().first
        writable = !demo && miner.isOnline && miner.kind == .espMiner
        unavailableReason = demo ? "DEMO · preview only. No changes will be sent."
            : !miner.isOnline ? "Miner offline. Reconnect and refresh before editing."
            : miner.kind == .xmrig ? "This editor supports ESP-Miner settings. XMRig controls are available in the app." : nil
    }

    func cancel() { task?.cancel() }

    private var fields: [MinerSetting] {
        if poolSlots { return selectedSlot.map { MinerPoolSettings.fields(slot: $0) } ?? MinerPoolSettings.roles }
        return MinerSetting.all.filter { $0.category == category }
    }
    private var field: MinerSetting { fields[min(selection, fields.count - 1)] }
    private var draftText: String { String(lossyUTF8: textBytes) }
    private var poolSlots: Bool { category == .pools && MinerSetting.usesPoolSlots(original) }
    private var poolUnavailableReason: String? {
        guard poolSlots else { return nil }
        do {
            let slots = try MinerPoolSettings.slots(original)
            return slots.isEmpty ? "No configured pool slots were reported. Configure a slot on the miner, then reopen settings." : nil
        } catch { return error.localizedDescription }
    }
    private var reviewFields: [MinerSetting] { changes.keys.sorted().compactMap { MinerSetting.field(key: $0) } }

    /// Return true when changing screens, so buffered keystrokes cannot also confirm a write.
    func handle(_ key: TerminalKey) -> Bool {
        if case .byte(3) = key { quit = true; return true }
        if case .byte(4) = key { quit = true; return true }
        if !usableSize {
            if case .escape = key { closed = true; return true }
            return false
        }
        switch page {
        case .saving: return false
        case .editing: return handleEditing(key)
        case .review: return handleReview(key)
        case .result: return handleResult(key)
        case .discard: return handleDiscard(key)
        case .fields: return handleFields(key)
        }
    }

    private func handleEditing(_ key: TerminalKey) -> Bool {
        switch key {
        case .escape: page = .fields; message = ""; return true
        case .byte(13), .byte(10):
            do {
                let value = try field.parse(draftText)
                if field.matches(value, field.observed(in: original)) {
                    changes.removeValue(forKey: field.key)
                } else {
                    changes[field.key] = value
                }
                message = ""; page = .fields
            } catch { message = error.localizedDescription }
            return true
        case .byte(21): textBytes.removeAll()
        case .byte(127), .byte(8):
            var text = draftText
            if !text.isEmpty { text.removeLast() }
            textBytes = Array(text.utf8)
        case .byte(let byte) where byte >= 32 && textBytes.count < 1024: textBytes.append(byte)
        case .paste(let pasted):
            let text = TerminalText.safe(String(lossyUTF8: pasted))
            textBytes = Array((draftText + text).utf8.prefix(1024))
        default: break
        }
        return false
    }

    private func handleReview(_ key: TerminalKey) -> Bool {
        switch key {
        case .escape: page = .fields; textBytes = []; return true
        case .up, .byte(107): reviewOffset = max(0, reviewOffset - 1)
        case .down, .byte(106): reviewOffset = min(reviewMaximum, reviewOffset + 1)
        case .byte(13), .byte(10):
            guard draftText == "APPLY", writable else {
                message = "Type APPLY, then press Enter to send the reviewed changes."
                return true
            }
            apply(); return true
        case .byte(21): textBytes.removeAll()
        case .byte(127), .byte(8): if !textBytes.isEmpty { textBytes.removeLast() }
        case .byte(let byte) where (65...90).contains(byte) && textBytes.count < 5: textBytes.append(byte)
        default: break
        }
        return false
    }

    private func handleResult(_ key: TerminalKey) -> Bool {
        switch key {
        case .escape, .byte(13), .byte(10): page = .fields; message = ""; return true
        case .byte(113): closed = true; return true
        default: return false
        }
    }

    private func handleDiscard(_ key: TerminalKey) -> Bool {
        switch key {
        case .byte(121), .byte(89): closed = true; return true
        case .escape, .byte(110), .byte(78): page = .fields; return true
        default: return false
        }
    }

    private func handleFields(_ key: TerminalKey) -> Bool {
        switch key {
        case .escape, .byte(98), .byte(113):
            if changes.isEmpty { closed = true } else { page = .discard }
            return true
        case .byte(13), .byte(10):
            guard writable, poolUnavailableReason == nil else { return false }
            let value = changes[field.key] ?? field.observed(in: original)
            textBytes = Array((field.isSecret ? value?.stringValue ?? "" : value == nil ? "" : field.display(value)).utf8)
            page = .editing; message = ""; return true
        case .byte(117): changes.removeValue(forKey: field.key); message = ""
        case .byte(114):
            guard writable, !changes.isEmpty else { message = "Edit a value with Enter first."; return false }
            do {
                try MinerSetting.validate(changes, device: device, info: original)
                page = .review; reviewOffset = 0; textBytes = []; message = ""
            } catch { message = error.localizedDescription }
            return true
        default: handleFieldNavigation(key)
        }
        return false
    }

    private func handleFieldNavigation(_ key: TerminalKey) {
        switch key {
        case .up, .byte(107): selection = max(0, selection - 1); message = ""
        case .down, .byte(106): selection = min(fields.count - 1, selection + 1); message = ""
        case .left: changeCategory(-1)
        case .right, .byte(9): changeCategory(1)
        case .byte(91): changeSlot(-1)
        case .byte(93): changeSlot(1)
        case .byte(let byte) where (49...53).contains(byte):
            category = MinerSettingsCategory.allCases[Int(byte - 49)]; selection = 0; message = ""
        default: break
        }
    }

    private func changeCategory(_ direction: Int) {
        let all = MinerSettingsCategory.allCases
        category = all[(all.firstIndex(of: category)! + direction + all.count) % all.count]
        selection = 0; message = ""
    }

    private func changeSlot(_ direction: Int) {
        guard poolSlots, let slots = try? MinerPoolSettings.slots(original), !slots.isEmpty else { return }
        let ids = slots.keys.sorted()
        let index = selectedSlot.flatMap { ids.firstIndex(of: $0) } ?? 0
        selectedSlot = ids[(index + direction + ids.count) % ids.count]
        selection = 0; message = ""
    }

    private func apply() {
        page = .saving
        task = Task {
            do {
                let result = try await MinerSettingsWriter.apply(device: device, original: original, changes: changes)
                guard !Task.isCancelled else { return }
                if let info = result.info {
                    original = info
                    let slots = (try? MinerPoolSettings.slots(info)) ?? [:]
                    if selectedSlot.map({ slots[$0] == nil }) ?? true { selectedSlot = slots.keys.sorted().first }
                }
                resultVerified = result.verified
                message = result.message
                if result.verified { changes.removeAll() }
            } catch {
                guard !Task.isCancelled else { return }
                resultVerified = false
                message = error.localizedDescription
            }
            page = .result; task = nil
        }
    }

    func render(width: Int, height: Int, palette: DashboardPalette) -> String {
        usableSize = width >= 44 && height >= 12
        var lines = [DashboardLine(" HASH FLEET / SETTINGS", style: palette.title),
                     DashboardLine(" \(device.name) · \(device.address)", style: palette.value)]
        var footer = ""
        if width < 44 || height < 12 {
            Self.note(&lines, "Resize to at least 45 columns × 12 rows to edit settings.", palette.warning, width: width)
            footer = " Esc back · Ctrl+C quit"
        } else {
            footer = renderPage(&lines, width: width, height: height, palette: palette)
        }
        lines = Array(lines.prefix(max(0, height - 2)))
        while lines.count < height - 2 { lines.append(DashboardLine()) }
        lines.append(DashboardLine(String(repeating: "─", count: width), style: palette.secondary))
        lines.append(DashboardLine(footer, style: palette.secondary))
        return "\u{1B}[H" + lines.prefix(height).map { $0.render(width: width) }.joined(separator: "\r\n") + "\u{1B}[J"
    }

    private static func note(_ lines: inout [DashboardLine], _ text: String, _ style: String, width: Int) {
        lines += TerminalText.wrapped(text, width: max(1, width - 2)).map { DashboardLine(" \($0)", style: style) }
    }

    /// Appends the body of the current page and returns its footer.
    private func renderPage(_ lines: inout [DashboardLine], width: Int, height: Int, palette: DashboardPalette) -> String {
        func note(_ text: String, _ style: String) { Self.note(&lines, text, style, width: width) }
        switch page {
        case .fields:
            return renderFields(&lines, width: width, height: height, palette: palette)
        case .editing:
            note(field.reviewTitle, palette.gold)
            note("Current: \(field.display(field.observed(in: original)))", palette.secondary)
            note(field.hint, palette.secondary)
            note("> \(field.isSecret ? String(repeating: "•", count: min(32, draftText.count)) : draftText)_", palette.value)
            if !message.isEmpty { note(message, palette.warning) }
            return " Enter stage · Ctrl+U clear · Esc cancel"
        case .review:
            return renderReview(&lines, width: width, height: height, palette: palette)
        case .saving:
            note("Applying reviewed changes…", palette.gold)
            note("Checking current settings, sending once, then reading them back.", palette.secondary)
            return " Ctrl+C quit · an in-flight write may still reach the miner"
        case .result:
            note(resultVerified ? "SAVED & VERIFIED" : "CHECK RESULT", resultVerified ? palette.good : palette.warning)
            note(message, resultVerified ? palette.good : palette.warning)
            return " Enter settings · q return to fleet"
        case .discard:
            note("Discard \(changes.count) pending changes and return to the fleet?", palette.warning)
            note("Discarding the draft does not undo any earlier request.", palette.secondary)
            return " y discard · n/Esc keep editing"
        }
    }

    private func renderFields(_ lines: inout [DashboardLine], width: Int, height: Int, palette: DashboardPalette) -> String {
        func note(_ text: String, _ style: String) { Self.note(&lines, text, style, width: width) }
        let tabs = MinerSettingsCategory.allCases.enumerated().map { index, value in
            (" \(index + 1) \(value.rawValue) ", value == category ? palette.selection : palette.secondary)
        }
        if width >= 64 {
            lines.append(DashboardLine(runs: tabs))
        } else {
            note("\(category.rawValue) · 1–5/Tab change section", palette.gold)
        }
        note("\(changes.count) pending changes · Enter edits the selected field", palette.secondary)
        if let unavailableReason { note(unavailableReason, palette.warning) }
        if let poolUnavailableReason {
            note(poolUnavailableReason, palette.warning)
        } else {
            if poolSlots, let selectedSlot {
                let primary = MinerPoolSettings.exactID(changes["primaryPoolIndex"] ?? original.raw["primaryPoolIndex"])
                let backup = MinerPoolSettings.exactID(changes["secondaryPoolIndex"] ?? original.raw["secondaryPoolIndex"])
                let role = [primary == selectedSlot ? "Primary" : nil, backup == selectedSlot ? "Backup" : nil]
                    .compactMap { $0 }.joined(separator: " + ")
                note("Slot \(selectedSlot)\(role.isEmpty ? "" : " · " + role) · [ / ] change slot", palette.gold)
            }
            renderFieldRows(&lines, width: width, height: height, palette: palette)
        }
        if !message.isEmpty { note(message, palette.warning) }
        return width >= 80 ? " 1–5/Tab section · ↑↓ select · Enter edit · r review · u undo · Esc back"
            : width >= 60 ? " ↑↓ select · Enter edit · r review · u undo · Esc back"
            : " ↑↓ pick · Enter edit · r review · Esc back"
    }

    private func renderFieldRows(_ lines: inout [DashboardLine], width: Int, height: Int, palette: DashboardPalette) {
        let available = max(1, height - lines.count - 5)
        let first = (selection / available) * available
        for index in first..<min(first + available, fields.count) {
            let item = fields[index]
            let label = "\(index == selection ? " › " : "   ")\(changes[item.key] == nil ? " " : "*") " + item.title
            let labelWidth = min(31, width / 2 + 5)
            lines.append(DashboardLine(runs: [
                (TerminalText.fit(label, labelWidth), index == selection ? palette.selection : palette.secondary),
                (" " + item.display(changes[item.key] ?? item.observed(in: original)),
                    changes[item.key] == nil ? palette.value : palette.gold)
            ]))
        }
        if fields.count > available {
            Self.note(&lines, "Fields \(first + 1)–\(min(first + available, fields.count))/\(fields.count) · ↑↓ scroll",
                palette.secondary, width: width)
        }
    }

    private func reviewLines(width: Int, palette: DashboardPalette) -> [DashboardLine] {
        var review: [DashboardLine] = []
        func reviewNote(_ text: String, _ style: String) {
            review += TerminalText.wrapped(text, width: width - 2).map { DashboardLine(" \($0)", style: style) }
        }
        for item in reviewFields {
            reviewNote(item.reviewTitle, palette.secondary)
            reviewNote("\(item.display(item.observed(in: original))) → \(item.display(changes[item.key]))", palette.gold)
        }
        let hardwareKeys = ["frequency", "coreVoltage", "manualFanSpeed", "autofanspeed", "minFanSpeed", "temptarget"]
        if changes.keys.contains(where: { hardwareKeys.contains($0) }) {
            reviewNote(
                "Clock, voltage and cooling changes affect heat, power and stability. "
                    + "APPLY confirms you reviewed these values for this hardware.",
                palette.warning
            )
        }
        if changes.keys.contains(where: { MinerPoolSettings.location($0) != nil }) {
            reviewNote(
                "Edited slots retain all reported TLS and advanced options. "
                    + "Passwords stay unchanged unless listed above. Pool changes can reconnect mining.",
                palette.secondary
            )
        } else { reviewNote("Only these fields are sent. No restart is automatic.", palette.secondary) }
        return review
    }

    private func renderReview(_ lines: inout [DashboardLine], width: Int, height: Int, palette: DashboardPalette) -> String {
        func note(_ text: String, _ style: String) { Self.note(&lines, text, style, width: width) }
        note("REVIEW · \(changes.count) changes to this miner", palette.gold)
        let review = reviewLines(width: width, palette: palette)
        let visible = max(1, height - lines.count - 5)
        reviewMaximum = max(0, review.count - visible)
        reviewOffset = min(reviewOffset, reviewMaximum)
        lines += review.dropFirst(reviewOffset).prefix(visible)
        if reviewMaximum > 0 {
            note("Review lines \(reviewOffset + 1)–\(min(review.count, reviewOffset + visible))/\(review.count) · ↑↓ scroll",
                palette.secondary)
        }
        if !message.isEmpty { note(message, palette.warning) }
        return " APPLY + Enter: \(draftText)_ · Esc edit"
    }
}

private extension String {
    /// Decodes UTF-8, substituting U+FFFD for malformed bytes (same repair as `String(decoding:as:)`).
    init(lossyUTF8 bytes: [UInt8]) {
        var scalars = String.UnicodeScalarView()
        var iterator = bytes.makeIterator()
        var decoder = UTF8()
        decoding: while true {
            switch decoder.decode(&iterator) {
            case .scalarValue(let scalar): scalars.append(scalar)
            case .emptyInput: break decoding
            case .error: scalars.append("\u{FFFD}")
            }
        }
        self.init(scalars)
    }
}
