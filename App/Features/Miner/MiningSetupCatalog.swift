import Foundation
import HashFleetCore

/// Hardware compatibility result based strictly on reported ASIC model.
/// Never guesses or claims arbitrary algorithms are supported.
public enum MiningHardwareCompatibility: Hashable, Sendable {
    case verifiedCompatible(asicModel: String, algorithm: MiningAlgorithm)
    case unverified(asicModel: String?)

    public var isCompatible: Bool {
        if case .verifiedCompatible = self { return true }
        return false
    }

    public var statusBadge: String {
        switch self {
        case .verifiedCompatible(let asic, _):
            return "Reported model uses SHA-256d (\(asic))"
        case .unverified(let asic):
            if let asic, !asic.isEmpty {
                return "Unverified ASIC (\(asic))"
            }
            return "ASIC unverified · check compatibility"
        }
    }

    public var description: String {
        switch self {
        case .verifiedCompatible(let asic, let algo):
            return "Reported ASIC model \(asic) is a known"
                + " \(algo.title) hashing chip. Device and pool"
                + " network compatibility depends on installed"
                + " firmware and settings."
        case .unverified(let asic):
            if let asic, !asic.isEmpty {
                return "Reported ASIC model \(asic) is not in"
                    + " the verified SHA-256d database."
                    + " It may still work if compatible."
            }
            return "The miner did not report an ASIC model. SHA-256d compatibility cannot be verified automatically."
        }
    }
}

/// Hashing algorithm strictly limited to hardware-supported algorithms.
public enum MiningAlgorithm: String, Hashable, Sendable {
    case sha256d = "SHA-256d"

    public var title: String { rawValue }
    public var description: String {
        "Double-round SHA-256 proof-of-work algorithm used by Bitcoin and compatible SHA-256d chains."
    }
}

/// Coins verified for SHA-256d mining. Arbitrary tokens and non-SHA-256d chains (e.g. Ethereum) are never listed.
public enum MiningCoin: String, CaseIterable, Identifiable, Hashable, Sendable {
    case btc = "BTC"
    case bch = "BCH"
    case bc2 = "BC2"
    case bch2 = "BCH2"
    case xec = "XEC"
    case dgb = "DGB"

    public var id: String { rawValue }
    public var symbol: String { rawValue }

    public var fullName: String {
        switch self {
        case .btc: "Bitcoin"
        case .bch: "Bitcoin Cash"
        case .bc2: "Bitcoin II"
        case .bch2: "Bitcoin Cash 2"
        case .xec: "eCash"
        case .dgb: "DigiByte"
        }
    }

    public var algorithm: MiningAlgorithm {
        .sha256d
    }

    public var plainEnglishDescription: String {
        switch self {
        case .btc:
            return "The original SHA-256d proof-of-work blockchain network. High variance on solo mining pools."
        case .bch:
            return "A SHA-256d peer-to-peer electronic cash fork"
                + " with dynamic difficulty adjustment"
                + " and native CashAddr formatting."
        case .bc2:
            return "Independent SHA-256d proof-of-work chain (Bitcoin II)."
        case .bch2:
            return "Alternative SHA-256d chain."
        case .xec:
            return "eCash SHA-256d network with 2-decimal unit redenomination and avalanche post-consensus."
        case .dgb:
            return "DigiByte is a multi-algorithm proof-of-work"
                + " chain. Bitaxe hardware uses only its"
                + " SHA-256d mining endpoints, not Scrypt,"
                + " Skein, Qubit or Odocrypt."
        }
    }

    /// Evaluates hardware compatibility based on reported ASIC model.
    /// Uses exact documented model tokens (e.g. BM1370, BM1366, BM1397, BM1368, BM1362, BM1387).
    /// Rejects impostors like NOTBM1370 or BM1370FAKE.
    /// Unknown or empty models stay strictly unverified.
    public func checkCompatibility(reportedASIC: String?) -> MiningHardwareCompatibility {
        guard let asic = reportedASIC?.trimmingCharacters(in: .whitespacesAndNewlines), !asic.isEmpty else {
            return .unverified(asicModel: nil)
        }
        let normalized = asic.uppercased()
        let exactKnownSHA256dModels: Set<String> = ["BM1370", "BM1366", "BM1397", "BM1368", "BM1362", "BM1387"]
        if exactKnownSHA256dModels.contains(normalized) {
            return .verifiedCompatible(asicModel: asic, algorithm: .sha256d)
        }
        return .unverified(asicModel: asic)
    }

    /// Resolves public market price if available from verified public data sources.
    /// BTC and BCH prices come from MiningInsightsStore.
    /// BC2, BCH2, and XEC market prices are not fetched and report unavailable (never invented).
    /// Prices are public market indications only; price does not equal mining profitability.
    @MainActor
    func publicPriceUSD(from insights: MiningInsightsStore?, now: Date = Date()) -> CoinPriceQuote {
        guard let insights else { return .unavailable(reason: "Live data has not loaded yet") }
        switch self {
        case .btc:
            if let priceResult = insights.network?.price,
               let usd = priceResult.value?.usd {
                let fresh = ChainObservation.isFresh(priceResult, now: now)
                return fresh ? .fresh(usd: usd, source: "mempool.space") : .stale(usd: usd, source: "mempool.space")
            }
            return .unavailable(reason: "Bitcoin price unavailable")
        case .bch:
            if let cashResult = insights.cash,
               let usd = cashResult.value?.usd {
                let fresh = ChainObservation.isFresh(cashResult, now: now)
                return fresh ? .fresh(usd: usd, source: "blockchair.com") : .stale(usd: usd, source: "blockchair.com")
            }
            return .unavailable(reason: "Bitcoin Cash price unavailable")
        case .bc2, .bch2, .xec, .dgb:
            return .unavailable(reason: "Public price is not tracked")
        }
    }
}

/// Price quote with freshness and honesty guarantees. Price does NOT equal mining profitability.
public enum CoinPriceQuote: Hashable, Sendable {
    case fresh(usd: Double, source: String)
    case stale(usd: Double, source: String)
    case unavailable(reason: String)

    public var displayText: String {
        switch self {
        case .fresh(let usd, _):
            return "$\(usd.formatted(.number.precision(.fractionLength(2))))"
        case .stale(let usd, _):
            return "$\(usd.formatted(.number.precision(.fractionLength(2)))) (stale)"
        case .unavailable:
            return "Price unavailable"
        }
    }

    public static let profitabilityDisclaimer = "Public price"
        + " is indicative only and does not equal mining"
        + " profitability. Low hashrate miners face extreme"
        + " variance and high difficulty on solo pools."
}

/// Mining pool operational mode: Solo vs Shared.
public enum PoolOperationMode: String, CaseIterable, Identifiable, Sendable {
    case solo = "Solo"
    case shared = "Shared"

    public var id: String { rawValue }
    public var title: String { rawValue }
    public var description: String {
        switch self {
        case .solo:
            return "Solo mining: If your miner finds an accepted"
                + " valid block, you receive the block reward"
                + " subject to pool payout rules and fees."
                + " Expect extreme variance with a small hashrate."
        case .shared:
            return "Shared or pooled mining: Miners combine hash power"
                + " to find blocks collectively. Rewards follow"
                + " each provider's payout scheme and minimum"
                + " payout thresholds."
        }
    }
}

/// Credential guidance for how user / worker format is structured by the pool.
public enum PoolCredentialGuidance: Hashable, Sendable {
    case walletAddressOnly(placeholder: String)
    case walletDotWorker(placeholder: String)
    case usernameDotWorker(placeholder: String)

    public var label: String {
        switch self {
        case .walletAddressOnly: return "Wallet address only"
        case .walletDotWorker: return "Wallet address + worker name"
        case .usernameDotWorker: return "Account username + worker name"
        }
    }

    public var prompt: String {
        switch self {
        case .walletAddressOnly(let placeholder):
            return "Enter your payout address for this coin. Format: \(placeholder)"
        case .walletDotWorker(let placeholder):
            return "Enter your coin payout address, followed by"
                + " an optional worker name."
                + " Format: \(placeholder)"
        case .usernameDotWorker(let placeholder):
            return "Requires an account registered with the pool."
                + " Enter your pool username and worker name."
                + " Format: \(placeholder)"
        }
    }
}

/// Unified pool preset definition supporting both Solo and Shared pools.
public struct MiningPoolPreset: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let coin: MiningCoin
    public let mode: PoolOperationMode
    public let server: String
    public let port: Int
    public let stratumProtocol: String
    public let documentationURL: URL
    public let credentialGuidance: PoolCredentialGuidance
    public let feeDescription: String

    public init(
        id: String,
        name: String,
        coin: MiningCoin,
        mode: PoolOperationMode,
        server: String,
        port: Int,
        stratumProtocol: String,
        documentationURL: URL,
        credentialGuidance: PoolCredentialGuidance,
        feeDescription: String
    ) {
        self.id = id
        self.name = name
        self.coin = coin
        self.mode = mode
        self.server = server
        self.port = port
        self.stratumProtocol = stratumProtocol
        self.documentationURL = documentationURL
        self.credentialGuidance = credentialGuidance
        self.feeDescription = feeDescription
    }

    public var displayTitle: String {
        "\(name) · \(coin.symbol) (\(mode.rawValue))"
    }

    public var endpointLabel: String {
        "\(server):\(port) · \(stratumProtocol)"
    }

    /// Generates field draft. Clears user unless transitioning from the exact same preset.
    func draft(previousPresetID: String?, currentUser: String) -> SoloPoolPresetFields {
        SoloPoolPresetFields(
            server: server,
            port: String(port),
            stratumProtocol: stratumProtocol,
            user: previousPresetID == id ? currentUser : ""
        )
    }
}

/// Comprehensive native catalog for SHA-256d guided pool and coin setup.
public enum MiningSetupCatalog {
    /// Official Solo presets (from verified SoloPoolPreset endpoints: CKPool and SoloFury).
    /// Fees change over time; users should check documentationURL for current fee schedules.
    public static let soloPresets: [MiningPoolPreset] = [
        MiningPoolPreset(
            id: "solo.solopool.dgb", name: "SoloPool", coin: .dgb, mode: .solo,
            server: "us1.solopool.org", port: 8004, stratumProtocol: "SV1",
            documentationURL: URL(string: "https://dgb-sha.solopool.org/help")!,
            credentialGuidance: .walletDotWorker(placeholder: "YOUR_DGB_ADDRESS.worker1"),
            feeDescription: "Official SHA-256 pool: 2% fee, 250K"
                + " share difficulty on port 8004. Small miners"
                + " may submit shares infrequently. Verify"
                + " current terms on the pool site."
        ),
        MiningPoolPreset(
            id: "solo.ckpool.btc",
            name: "CKPool",
            coin: .btc,
            mode: .solo,
            server: "stratum.ckpool.org",
            port: 3333,
            stratumProtocol: "SV1",
            documentationURL: URL(string: "https://solo.ckpool.org/")!,
            credentialGuidance: .walletDotWorker(placeholder: "YOUR_BTC_ADDRESS.worker1"),
            feeDescription: "See official site for current block-find fee schedule"
        ),
        MiningPoolPreset(
            id: "solo.solofury.btc",
            name: "SoloFury",
            coin: .btc,
            mode: .solo,
            server: "btc.solofury.com",
            port: 6060,
            stratumProtocol: "SV1",
            documentationURL: URL(string: "https://solofury.com/start/")!,
            credentialGuidance: .walletDotWorker(placeholder: "YOUR_BTC_ADDRESS.worker1"),
            feeDescription: "See official site for current fee schedule"
        ),
        MiningPoolPreset(
            id: "solo.solofury.bch",
            name: "SoloFury",
            coin: .bch,
            mode: .solo,
            server: "bch.solofury.com",
            port: 7070,
            stratumProtocol: "SV1",
            documentationURL: URL(string: "https://solofury.com/start/")!,
            credentialGuidance: .walletDotWorker(placeholder: "YOUR_BCH_ADDRESS.worker1"),
            feeDescription: "See official site for current fee schedule"
        ),
        MiningPoolPreset(
            id: "solo.solofury.bc2",
            name: "SoloFury",
            coin: .bc2,
            mode: .solo,
            server: "bc2.solofury.com",
            port: 8080,
            stratumProtocol: "SV1",
            documentationURL: URL(string: "https://solofury.com/start/")!,
            credentialGuidance: .walletDotWorker(placeholder: "YOUR_BC2_ADDRESS.worker1"),
            feeDescription: "See official site for current fee schedule"
        ),
        MiningPoolPreset(
            id: "solo.solofury.bch2",
            name: "SoloFury",
            coin: .bch2,
            mode: .solo,
            server: "bch2.solofury.com",
            port: 8585,
            stratumProtocol: "SV1",
            documentationURL: URL(string: "https://solofury.com/start/")!,
            credentialGuidance: .walletDotWorker(placeholder: "YOUR_BCH2_ADDRESS.worker1"),
            feeDescription: "See official site for current fee schedule"
        ),
        MiningPoolPreset(
            id: "solo.solofury.xec",
            name: "SoloFury",
            coin: .xec,
            mode: .solo,
            server: "xec.solofury.com",
            port: 9090,
            stratumProtocol: "SV1",
            documentationURL: URL(string: "https://solofury.com/start/")!,
            credentialGuidance: .walletDotWorker(placeholder: "YOUR_XEC_ADDRESS.worker1"),
            feeDescription: "See official site for current fee schedule"
        )
    ]

    /// Standard shared pools verified from official sources.
    /// OCEAN: non-custodial shared pool, payout address used as username directly.
}
