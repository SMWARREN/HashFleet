import Foundation
import Observation
import HashFleetCore

/// Normalized summary statistics for a supported mining pool.
struct ConnectedPoolStats: Hashable, Sendable {
    let hashRate1hrHPS: Double?
    let hashRate1dHPS: Double?
    let users: Int?
    let workers: Int?
    let bestShare: Double?

    init(
        hashRate1hrHPS: Double? = nil,
        hashRate1dHPS: Double? = nil,
        users: Int? = nil,
        workers: Int? = nil,
        bestShare: Double? = nil
    ) {
        self.hashRate1hrHPS = hashRate1hrHPS
        self.hashRate1dHPS = hashRate1dHPS
        self.users = users
        self.workers = workers
        self.bestShare = bestShare
    }
}

/// Normalized account statistics for a supported mining pool account.
struct ConnectedAccountStats: Hashable, Sendable {
    let hashRate1hrHPS: Double?
    let hashRate1dHPS: Double?
    let workersCount: Int?
    let shares: Double?
    let bestShare: Double?
    let bestEver: Double?
    let lastShare: Date?

    init(
        hashRate1hrHPS: Double? = nil,
        hashRate1dHPS: Double? = nil,
        workersCount: Int? = nil,
        shares: Double? = nil,
        bestShare: Double? = nil,
        bestEver: Double? = nil,
        lastShare: Date? = nil
    ) {
        self.hashRate1hrHPS = hashRate1hrHPS
        self.hashRate1dHPS = hashRate1dHPS
        self.workersCount = workersCount
        self.shares = shares
        self.bestShare = bestShare
        self.bestEver = bestEver
        self.lastShare = lastShare
    }
}

enum ConnectedAccountResult: Hashable, Sendable {
    case found(MiningDataResult<ConnectedAccountStats>)
    case notFound(fetchedAt: Date)
    case failed(MiningInsightsError)
}

struct PoolKey: Hashable, Sendable {
    let provider: MiningPoolProvider
    let coin: MiningPoolCoin?
}

struct AccountKey: Hashable, Sendable {
    let provider: MiningPoolProvider
    let coin: MiningPoolCoin?
    let address: String
    let host: String
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.provider == rhs.provider && lhs.coin == rhs.coin && lhs.address == rhs.address
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(provider); hasher.combine(coin); hasher.combine(address)
    }
}

/// One unique pool/account presentation in the fleet-wide Pool Stats Hub.
/// Multiple miners that resolve to the same public statistics lookup share one card.
struct PoolStatsHubEntry: Identifiable, Equatable {
    struct EntryIdentity: Hashable {
        let provider: MiningPoolProvider
        let coin: MiningPoolCoin?
        let address: String?
    }

    struct Membership: Equatable {
        let deviceID: UUID
        let minerName: String
        let pool: ConfiguredMiningPool
    }

    let id: EntryIdentity
    let pool: ConfiguredMiningPool
    let minerNames: [String]

    static func grouped(_ memberships: [Membership]) -> [Self] {
        let supported = memberships.compactMap { membership -> (EntryIdentity, Membership)? in
            guard let provider = membership.pool.provider,
                  provider == .ckpool || provider == .soloFury || provider == .soloPool
            else { return nil }
            let address = membership.pool.address?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (
                EntryIdentity(
                    provider: provider,
                    coin: membership.pool.coin,
                    address: address?.isEmpty == false ? address : nil
                ),
                membership
            )
        }
        return Dictionary(grouping: supported, by: \.0)
            .map { id, group in
                let memberships = group.map(\.1)
                let representative = memberships.first(where: { $0.pool.isActive == true }) ?? memberships[0]
                return Self(
                    id: id,
                    pool: representative.pool,
                    minerNames: Array(Set(memberships.map(\.minerName))).sorted()
                )
            }
            .sorted { lhs, rhs in
                let lhsName = lhs.pool.providerName ?? lhs.id.provider.rawValue
                let rhsName = rhs.pool.providerName ?? rhs.id.provider.rawValue
                if lhsName != rhsName { return lhsName < rhsName }
                if lhs.pool.coin?.ticker != rhs.pool.coin?.ticker {
                    return (lhs.pool.coin?.ticker ?? "") < (rhs.pool.coin?.ticker ?? "")
                }
                return lhs.minerNames.joined(separator: "\u{0}") < rhs.minerNames.joined(separator: "\u{0}")
            }
    }
}
