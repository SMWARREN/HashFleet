import Foundation
import HashFleetCore

extension MiningSetupCatalog {
    /// Braiins Pool: shared pool, requires registered Braiins username.worker.
    public static let sharedPresets: [MiningPoolPreset] = [
        MiningPoolPreset(
            id: "shared.ocean.btc",
            name: "OCEAN",
            coin: .btc,
            mode: .shared,
            server: "mine.ocean.xyz",
            port: 3334,
            stratumProtocol: "SV1",
            documentationURL: URL(string: "https://ocean.xyz/getstarted")!,
            credentialGuidance: .walletDotWorker(placeholder: "YOUR_BTC_ADDRESS.worker1"),
            feeDescription: "Non-custodial shared pool (TIDES scheme; see ocean.xyz for current fees & payout rules)"
        ),
        MiningPoolPreset(
            id: "shared.braiins.btc",
            name: "Braiins Pool",
            coin: .btc,
            mode: .shared,
            server: "stratum.braiins.com",
            port: 3333,
            stratumProtocol: "SV1",
            documentationURL: URL(string: "https://academy.braiins.com/braiins-pool/btc-mining-setup")!,
            credentialGuidance: .usernameDotWorker(placeholder: "YOUR_ACCOUNT_NAME.worker1"),
            feeDescription: "Shared reward distribution (account registration required; see braiins.com for terms)"
        )
    ]

    /// All presets combined.
    public static var allPresets: [MiningPoolPreset] {
        soloPresets + sharedPresets
    }

    /// Presets filtered by operation mode.
    public static func presets(for mode: PoolOperationMode) -> [MiningPoolPreset] {
        allPresets.filter { $0.mode == mode }
    }

    /// Presets filtered by coin.
    public static func presets(for coin: MiningCoin) -> [MiningPoolPreset] {
        allPresets.filter { $0.coin == coin }
    }
}
