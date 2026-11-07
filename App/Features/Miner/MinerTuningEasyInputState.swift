import Foundation

/// Uncommitted text is separate from the numeric draft. Invalid or partial input never replaces it.
struct MinerTuningEasyInputState {
    private(set) var text = ""
    private(set) var error: String?
    private(set) var isEdited = false

    mutating func reset(value: Double?) {
        text = value.map(MinerTuningDraft.numericText) ?? ""
        error = nil
        isEdited = false
    }

    mutating func receive(value: Double?, isFocused: Bool) {
        // A periodic reading must not erase an unfinished or invalid user edit.
        guard !isFocused, !isEdited else { return }
        reset(value: value)
    }

    mutating func edit(_ text: String, field: MinerTuningEasyField) {
        self.text = text
        isEdited = true
        _ = parsedValue(field: field)
    }

    mutating func commit(field: MinerTuningEasyField) -> Double? {
        guard isEdited, let value = parsedValue(field: field) else { return nil }
        text = MinerTuningDraft.numericText(value)
        isEdited = false
        return value
    }

    /// Valid in-progress text, staged as a draft without normalizing what the user is typing.
    mutating func stageWhileEditing(field: MinerTuningEasyField) -> Double? {
        guard isEdited else { return nil }
        return parsedValue(field: field)
    }

    private mutating func parsedValue(field: MinerTuningEasyField) -> Double? {
        do {
            let value = try field.value(from: text)
            error = nil
            return value
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }
}
