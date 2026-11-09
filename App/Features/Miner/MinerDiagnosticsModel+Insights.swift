import Foundation
import HashFleetCore

extension MinerDiagnosticsModel {
    /// Direction of the reported 1-minute hashrate average relative to the reported 1-hour
    /// average. Both inputs are values the miner reported; this never extrapolates or predicts.
    public enum HashrateTrend: String, Sendable, Equatable {
        case rising
        case steady
        case falling

        /// Calm, factual wording that names both inputs so nobody reads it as a prediction.
        public var title: String {
            switch self {
            case .rising: return "Rising (1-minute average above 1-hour average)"
            case .steady: return "Steady (1-minute average near 1-hour average)"
            case .falling: return "Falling (1-minute average below 1-hour average)"
            }
        }
    }

    /// Compares the reported 1-minute average against the reported 1-hour average.
    /// Returns nil when either average is missing or the 1-hour average is zero, because a
    /// relative comparison against an absent baseline would invent precision. A small tolerance
    /// band keeps normal sampling jitter from flip-flopping the label.
    public static func hashrateTrend(
        recent1m recent: Double?,
        baseline1h baseline: Double?,
        tolerance: Double = 0.02
    ) -> HashrateTrend? {
        guard let recent, let baseline,
              recent.isFinite, baseline.isFinite,
              recent >= 0, baseline > 0 else { return nil }
        let ratio = (recent - baseline) / baseline
        if ratio > tolerance { return .rising }
        if ratio < -tolerance { return .falling }
        return .steady
    }

    public var hashrateTrend: HashrateTrend? {
        Self.hashrateTrend(recent1m: hashrate.hashrate1mGHs, baseline1h: hashrate.hashrate1hGHs)
    }

    /// Calm, factual notes about gaps or explicit readings in the latest snapshot. Each note
    /// states a fact the miner reported (or failed to report); nothing here is a health verdict,
    /// a threshold alarm, or advice beyond what the telemetry itself says.
    public var attentionNotes: [String] {
        var notes: [String] = []
        if hashrate.currentHashrateGHs == nil {
            notes.append("Hashrate was not reported in the latest reading.")
        }
        if thermal.primaryChipTempCelsius == nil {
            notes.append("Chip temperature was not reported by the firmware.")
        }
        if let fan1 = thermal.fan1RPM, fan1 == 0 {
            // The firmware explicitly reported 0 RPM. Per the audited telemetry contract that
            // can mean stopped or an unreachable tach; say exactly that rather than guessing.
            notes.append("Primary fan reported 0 RPM (stopped, or tach unavailable).")
        }
        if let rejected = hashrate.rejectedSharePercentage, rejected > 0, let count = hashrate.sharesRejected, count > 0 {
            notes.append(
                "The pool rejected \(count.formatted()) share(s) "
                    + "(\(rejected.formatted(.number.precision(.fractionLength(2))))% of submissions)."
            )
        }
        return notes
    }
}
