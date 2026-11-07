import HashFleetCore

extension MinerTuningSessionView {
    func formattedVoltage(_ value: Double?) -> String {
        guard let value else { return "Not reported" }
        return "\(MinerTuningDraft.numericText(value)) mV"
    }

    func formattedFrequency(_ value: Double?) -> String {
        guard let value else { return "Not reported" }
        return "\(MinerTuningDraft.numericText(value)) MHz"
    }
}
