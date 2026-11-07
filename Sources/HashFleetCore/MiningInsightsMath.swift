import Foundation

public struct SoloMiningEstimate: Hashable, Sendable {
    public let expectedBlocks: Double
    public let probabilityAtLeastOne: Double
    /// Nil for zero hashrate or when the expected duration exceeds finite Double range.
    public let expectedTimeToBlock: TimeInterval?
    /// Consensus subsidy only, before pool fees and without transaction fees.
    public let blockSubsidyBTC: Double?
    public let subsidyValueUSD: Double?

    public init(
        expectedBlocks: Double,
        probabilityAtLeastOne: Double,
        expectedTimeToBlock: TimeInterval? = nil,
        blockSubsidyBTC: Double? = nil,
        subsidyValueUSD: Double? = nil
    ) {
        self.expectedBlocks = expectedBlocks
        self.probabilityAtLeastOne = probabilityAtLeastOne
        self.expectedTimeToBlock = expectedTimeToBlock
        self.blockSubsidyBTC = blockSubsidyBTC
        self.subsidyValueUSD = subsidyValueUSD
    }
}

/// A constant-hashrate, constant-difficulty Poisson approximation. This is not a payout prediction.
public enum SoloMiningMath {
    public static func estimate(
        hashrateHPS: Double,
        difficulty: Double,
        duration: TimeInterval,
        height: Int? = nil,
        bitcoinPriceUSD: Double? = nil
    ) -> SoloMiningEstimate? {
        guard hashrateHPS.isFinite, hashrateHPS >= 0, difficulty.isFinite, difficulty > 0,
            duration.isFinite, duration >= 0
        else { return nil }

        let logRate = hashrateHPS > 0 ? log(hashrateHPS) - log(difficulty) - 32 * log(2) : -.infinity
        // Use the direct expression when safe for its precision and log-space for extreme inputs.
        let rate = (hashrateHPS / difficulty) / 4_294_967_296
        let directLambda = rate * duration
        let lambda: Double
        if hashrateHPS == 0 || duration == 0 {
            lambda = 0
        } else if directLambda.isFinite && directLambda > 0 {
            lambda = directLambda
        } else {
            let recovered = exp(logRate + log(duration))
            // Do not emit infinity as a displayable expected block count.
            guard recovered.isFinite else { return nil }
            lambda = recovered
        }
        let expectedTime = hashrateHPS > 0 ? (rate > 0 && rate.isFinite ? 1 / rate : exp(-logRate)) : .infinity
        let subsidy = height.flatMap(blockSubsidyBTC(atHeight:))
        let valueUSD: Double? = {
            guard let subsidy, let price = bitcoinPriceUSD, price.isFinite, price > 0 else { return nil }
            let result = subsidy * price
            return result.isFinite ? result : nil
        }()
        return SoloMiningEstimate(
            expectedBlocks: lambda,
            probabilityAtLeastOne: -expm1(-lambda),
            expectedTimeToBlock: expectedTime.isFinite ? expectedTime : nil,
            blockSubsidyBTC: subsidy,
            subsidyValueUSD: valueUSD
        )
    }

    /// Bitcoin mainnet's integer-satoshi subsidy at this exact height, including final satoshi truncation.
    public static func blockSubsidyBTC(atHeight height: Int) -> Double? {
        guard height >= 0 else { return nil }
        let halvings = height / 210_000
        guard halvings < 64 else { return 0 }
        let satoshis: UInt64 = 5_000_000_000 >> halvings
        return Double(satoshis) / 100_000_000
    }
}
