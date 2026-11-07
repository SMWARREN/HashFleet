import Foundation
import Testing
import HashFleetCore

/// Explicit authorization boundary: the operator must provide an existing private Info JSON file.
/// Ordinary tests never read the file or perform these account requests. No miner is contacted.
/// Keep all diagnostics independent of raw data, local paths, wallet addresses and response URLs.
@Suite("Authorized configured-account live smoke",
       .enabled(if: !(ProcessInfo.processInfo.environment["HASHFLEET_PRIVATE_INFO_FILE"] ?? "").isEmpty),
       .timeLimit(.minutes(3)))
struct SoloFuryConfiguredAccountsLiveTests {
    @Test func authorizedConfiguredAccountsDecodeThroughProductionClientsWithoutPrivateOutput() async throws {
        guard let info = readAuthorizedInfoFile() else {
            Issue.record("Authorized private Info file could not be read or decoded.")
            return
        }
        let recognized = ConfiguredMiningPool.resolve(info: info)
            .filter { $0.provider != nil && $0.coin != nil }
        guard !recognized.isEmpty else {
            Issue.record("No recognized configured accounts were resolved from the authorized Info file.")
            return
        }
        for (index, pool) in recognized.enumerated() {
            try await verify(pool: pool, index: index)
        }
    }

    private func readAuthorizedInfoFile() -> MinerInfo? {
        guard let path = ProcessInfo.processInfo.environment["HASHFLEET_PRIVATE_INFO_FILE"], !path.isEmpty,
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)), data.count <= 4_194_304,
              let info = try? JSONDecoder().decode(MinerInfo.self, from: data) else { return nil }
        return info
    }

    private func verify(pool: ConfiguredMiningPool, index: Int) async throws {
        // SoloFury documents a recommended maximum of one request per second per IP.
        if index > 0 { try await Task.sleep(for: .seconds(1)) }
        try Task.checkCancellation()
        guard let provider = pool.provider, let coin = pool.coin, let address = pool.address else {
            Issue.record("Recognized configured account has no valid chain-compatible address.")
            return
        }
        let outcome: String
        switch provider {
        case .ckpool:
            outcome = await verifyCKPool(address: address)
        case .soloFury:
            outcome = await verifySoloFury(pool: pool)
        case .soloPool:
            outcome = await verifySoloPool(pool: pool)
        }
        guard !outcome.isEmpty else { return }
        print("provider=\(provider.rawValue) coin=\(coin.rawValue) outcome=\(outcome)")
    }

    private func verifyCKPool(address: String) async -> String {
        switch await MiningInsightsClient().ckPoolUser(address: address) {
        case .found(let result):
            guard result.value != nil, result.error == nil else {
                Issue.record("CKPool account response was not a valid found result.")
                return ""
            }
            return "found"
        case .notFound: return "not-found"
        case .failed:
            Issue.record("CKPool configured-account request failed. Private details omitted.")
            return ""
        }
    }

    private func verifySoloFury(pool: ConfiguredMiningPool) async -> String {
        let result = await SoloFuryClient().account(pool: pool)
        if result.error == .http(statusCode: 404) {
            return "not-found"
        } else if result.error == nil, result.value != nil {
            return "found"
        }
        Issue.record("SoloFury configured-account request failed. Private details omitted.")
        return ""
    }

    private func verifySoloPool(pool: ConfiguredMiningPool) async -> String {
        let result = await SoloPoolClient().account(pool: pool)
        if result.error == .http(statusCode: 404) {
            return "not-found"
        } else if result.error == nil, result.value != nil {
            return "found"
        }
        Issue.record("SoloPool configured-account request failed. Private details omitted.")
        return ""
    }
}
