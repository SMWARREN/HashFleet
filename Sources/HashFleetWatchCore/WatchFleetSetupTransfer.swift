import Foundation

public enum WatchFleetSetupTransferError: Error, Equatable, Sendable, LocalizedError {
    case noMiners
    case tooManyMiners
    case duplicateIdentifier
    case duplicateEndpoint
    case unsupportedVersion

    public var errorDescription: String? {
        switch self {
        case .noMiners: "There are no miners to send."
        case .tooManyMiners: "A Watch can hold up to \(WatchFleetLimits.maximumMiners) miners."
        case .duplicateIdentifier, .duplicateEndpoint: "The miner list contains duplicates."
        case .unsupportedVersion: "This setup was made by a different version of Hash Fleet."
        }
    }
}

/// Configuration-only miner list that an iPhone can hand to the Watch. It never carries readings, secrets,
/// pool settings or Wi-Fi details.
public struct WatchFleetSetupTransfer: Codable, Identifiable, Equatable, Sendable {
    public static let currentVersion = 1

    public let id: UUID
    public let version: Int
    public let miners: [WatchMiner]

    public init(id: UUID = UUID(), miners: [WatchMiner]) throws {
        try Self.validate(miners)
        self.id = id
        self.version = Self.currentVersion
        self.miners = miners
    }

    private enum CodingKeys: String, CodingKey {
        case id, version, miners
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let version = try c.decode(Int.self, forKey: .version)
        guard version == Self.currentVersion else { throw WatchFleetSetupTransferError.unsupportedVersion }
        let id = try c.decode(UUID.self, forKey: .id)
        // Each miner revalidates its own address while decoding.
        let miners = try c.decode([WatchMiner].self, forKey: .miners)
        try Self.validate(miners)
        self.id = id
        self.version = version
        self.miners = miners
    }

    private static func validate(_ miners: [WatchMiner]) throws {
        guard !miners.isEmpty else { throw WatchFleetSetupTransferError.noMiners }
        guard miners.count <= WatchFleetLimits.maximumMiners else { throw WatchFleetSetupTransferError.tooManyMiners }
        guard Set(miners.map(\.id)).count == miners.count else { throw WatchFleetSetupTransferError.duplicateIdentifier }
        guard Set(miners.map(\.address)).count == miners.count else { throw WatchFleetSetupTransferError.duplicateEndpoint }
    }
}
