import Foundation

/// One entry from the firmware's `/api/system/scoreboard` endpoint: the device's own authoritative,
/// NVS-persisted top best-share hashes (per coin, merged and ranked by difficulty). Unlike the app's
/// polling-derived best-share detection, this is the ASIC's own permanent record and survives
/// reboots/reconnects/app reinstalls, making it the "concrete list" ground truth for best shares.
public struct MinerScoreboardEntry: Codable, Hashable, Sendable {
    public let difficulty: Double
    public let jobId: String
    public let extranonce2: String
    public let ntime: UInt32
    public let nonce: String
    public let versionBits: String
    /// Present on newer firmware (multi-coin builds); absent on older single-coin builds.
    public let coin: String?
    public let poolIndex: Int?

    enum CodingKeys: String, CodingKey {
        case difficulty
        case jobId = "job_id"
        case extranonce2
        case ntime
        case nonce
        case versionBits = "version_bits"
        case coin
        case poolIndex
    }

    /// `ntime` is the block header time embedded in the share's job, seconds since epoch — the
    /// share's real occurrence time, not when the app happened to poll and notice it.
    public var occurredAt: Date { Date(timeIntervalSince1970: TimeInterval(ntime)) }
}
