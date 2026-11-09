import Foundation
import Testing
import HashFleetCore
@testable import HashFleet

@Suite("Native mining setup catalog & guided setup")
struct MiningSetupTests {
    @Test func SHA256dCoinsAreStrictlyLimitedAndNeverIncludeEthereumOrArbitraryTokens() {
        let expectedSymbols: Set<String> = ["BTC", "BCH", "BC2", "BCH2", "XEC", "DGB"]
        let allCoins = MiningCoin.allCases
        #expect(allCoins.count == 6)
        #expect(Set(allCoins.map(\.symbol)) == expectedSymbols)
        for coin in allCoins {
            #expect(coin.algorithm == .sha256d)
            #expect(coin.algorithm.title == "SHA-256d")
            #expect(!coin.plainEnglishDescription.isEmpty)
        }
    }

    @Test func hardwareCompatibilityStrictlyIdentifiesBM1370AndRelatedBitaxeASICs() {
        let compatibleASICs = ["BM1370", "bm1370", "BM1366", "BM1397", "BM1368", "BM1362", "BM1387"]
        for asic in compatibleASICs {
            let compat = MiningCoin.btc.checkCompatibility(reportedASIC: asic)
            #expect(compat.isCompatible)
            if case .verifiedCompatible(let model, let algo) = compat {
                #expect(model == asic)
                #expect(algo == .sha256d)
            } else {
                Issue.record("Expected verifiedCompatible for \(asic)")
            }
        }
    }

    @Test func unknownOrMissingASICModelsAndImpostorsRemainStrictlyUnverified() {
        let unverified: [String?] = [
            nil, "", "   ", "UNKNOWN", "ETH-CHIP", "S19-PRO-GENERIC",
            "NOTBM1370", "BM1370FAKE", "BM13700", "BM1366X", "FAKEBM1397"
        ]
        for asic in unverified {
            let compat = MiningCoin.btc.checkCompatibility(reportedASIC: asic)
            #expect(!compat.isCompatible)
            if case .unverified = compat {
                // expected
            } else {
                Issue.record("Expected unverified for \(String(describing: asic))")
            }
        }
    }

    @Test func coinOfficialNamingMatchesWithoutUnverifiedClaims() {
        #expect(MiningCoin.bc2.fullName == "Bitcoin II")
        #expect(!MiningCoin.btc.plainEnglishDescription.contains("highest network difficulty"))
        #expect(!MiningCoin.btc.plainEnglishDescription.contains("block value"))
        #expect(!MiningCoin.bch2.plainEnglishDescription.contains("low difficulty target suitable"))
    }

    @Test func credentialGuidancePromptsUseNonAddressPlaceholders() {
        for preset in MiningSetupCatalog.allPresets {
            let prompt = preset.credentialGuidance.prompt
            #expect(!prompt.contains("bc1q"))
            #expect(!prompt.contains("bitcoincash:"))
            #expect(!prompt.contains("ecash:"))
            #expect(prompt.contains("YOUR_") || prompt.contains("Format:"))
        }
    }

    @Test func feeDescriptionsDirectToOfficialSitesRatherThanHardcoding() {
        for preset in MiningSetupCatalog.allPresets {
            #expect(
                preset.feeDescription.lowercased().contains("official")
                    || preset.feeDescription.lowercased().contains("terms")
                    || preset.feeDescription.lowercased().contains("rules")
            )
            #expect(!preset.feeDescription.contains("2% fee on block find only"))
            #expect(!preset.feeDescription.contains("1% fee on block find only"))
        }
    }

    @Test func poolModeDescriptionsClearlyStateSoloFindRulesAndSharedThresholds() {
        let soloDesc = PoolOperationMode.solo.description
        #expect(soloDesc.contains("If your miner finds an accepted valid block"))
        #expect(!soloDesc.contains("winner-take-all"))

        let sharedDesc = PoolOperationMode.shared.description
        #expect(sharedDesc.contains("Rewards follow each provider's payout scheme"))
        #expect(!sharedDesc.contains("Steady, lower-variance"))
    }

    @Test func allPresetsMatchVerifiedEndpointsAndSupportBothSoloAndShared() {
        let solo = MiningSetupCatalog.soloPresets
        let shared = MiningSetupCatalog.sharedPresets
        #expect(solo.count == 7)
        #expect(shared.count == 2)
        #expect(MiningSetupCatalog.allPresets.count == 9)

        // OCEAN BTC shared
        guard let ocean = shared.first(where: { $0.id == "shared.ocean.btc" }) else {
            Issue.record("Missing OCEAN preset"); return
        }
        #expect(ocean.server == "mine.ocean.xyz")
        #expect(ocean.port == 3334)
        #expect(ocean.stratumProtocol == "SV1")
        #expect(ocean.coin == .btc)
        #expect(ocean.mode == .shared)

        // Braiins BTC shared
        guard let braiins = shared.first(where: { $0.id == "shared.braiins.btc" }) else {
            Issue.record("Missing Braiins preset"); return
        }
        #expect(braiins.server == "stratum.braiins.com")
        #expect(braiins.port == 3333)
        #expect(braiins.stratumProtocol == "SV1")
        #expect(braiins.coin == .btc)
        #expect(braiins.mode == .shared)
    }

    @Test func switchingPresetsClearsPreviousWalletOrCredentials() {
        let ocean = MiningSetupCatalog.sharedPresets[0]
        let braiins = MiningSetupCatalog.sharedPresets[1]
        let oldUser = "bc1qoldaddress.worker"

        let draft = braiins.draft(previousPresetID: ocean.id, currentUser: oldUser)
        #expect(draft.user.isEmpty)
        #expect(draft.server == braiins.server)
        #expect(draft.port == String(braiins.port))

        // Same preset preserves user
        let sameDraft = braiins.draft(previousPresetID: braiins.id, currentUser: "userName.worker1")
        #expect(sameDraft.user == "userName.worker1")
    }

    @Test @MainActor func priceHonestyPresentsUnavailableForUnverifiedCoinsAndNeverInventsProfitability() async {
        let now = Date()
        let btcPriceNil = MiningCoin.btc.publicPriceUSD(from: nil, now: now)
        #expect(btcPriceNil == .unavailable(reason: "Live data has not loaded yet"))

        // BC2, BCH2, XEC are always price unavailable (not tracked), never invented
        let bc2PriceNil = MiningCoin.bc2.publicPriceUSD(from: nil, now: now)
        #expect(bc2PriceNil == .unavailable(reason: "Live data has not loaded yet"))

        #expect(CoinPriceQuote.profitabilityDisclaimer.contains("does not equal mining profitability"))

        // Test with loaded store using demo samples
        let store = MiningInsightsStore()
        store.setDemo(true)
        await store.refresh()

        expectFreshThenStaleBtcQuote(store: store)

        expectFreshThenStaleBchQuote(store: store)

        // Untracked coins (BC2, BCH2, XEC) MUST report unavailable even when store is loaded
        for coin in [MiningCoin.bc2, MiningCoin.bch2, MiningCoin.xec] {
            let quote = coin.publicPriceUSD(from: store, now: now)
            if case .unavailable(let reason) = quote {
                #expect(reason.contains("not tracked"))
                #expect(quote.displayText == "Price unavailable")
            } else {
                Issue.record("Expected unavailable quote for untracked coin \(coin.symbol) but got \(quote)")
            }
        }
    }

    /// BTC must surface a fresh mempool.space quote inside 300s and a clearly stale quote beyond it.
    @MainActor
    private func expectFreshThenStaleBtcQuote(store: MiningInsightsStore) {
        guard let fetchedAt = store.network?.price.fetchedAt else {
            Issue.record("Expected price.fetchedAt in demo network snapshot")
            return
        }
        let freshBtc = MiningCoin.btc.publicPriceUSD(from: store, now: fetchedAt.addingTimeInterval(30))
        if case .fresh(let usd, let source) = freshBtc {
            #expect(usd == 80000)
            #expect(source == "mempool.space")
            #expect(freshBtc.displayText.contains("80,000"))
        } else {
            Issue.record("Expected fresh BTC price quote but got \(freshBtc)")
        }
        let staleBtc = MiningCoin.btc.publicPriceUSD(from: store, now: fetchedAt.addingTimeInterval(301))
        if case .stale(let usd, let source) = staleBtc {
            #expect(usd == 80000)
            #expect(source == "mempool.space")
            #expect(staleBtc.displayText.contains("stale"))
        } else {
            Issue.record("Expected stale BTC price quote but got \(staleBtc)")
        }
    }

    /// BCH must surface fresh and stale blockchair quotes the same way.
    @MainActor
    private func expectFreshThenStaleBchQuote(store: MiningInsightsStore) {
        guard let cashFetched = store.cash?.fetchedAt else {
            Issue.record("Expected cash.fetchedAt in demo cash snapshot")
            return
        }
        let freshBch = MiningCoin.bch.publicPriceUSD(from: store, now: cashFetched.addingTimeInterval(10))
        if case .fresh(let usd, let source) = freshBch {
            #expect(usd == 260)
            #expect(source == "blockchair.com")
        } else {
            Issue.record("Expected fresh BCH price quote but got \(freshBch)")
        }
        let staleBch = MiningCoin.bch.publicPriceUSD(from: store, now: cashFetched.addingTimeInterval(350))
        if case .stale(let usd, let source) = staleBch {
            #expect(usd == 260)
            #expect(source == "blockchair.com")
        } else {
            Issue.record("Expected stale BCH price quote but got \(staleBch)")
        }
    }

    @Test func soloPoolPresetsInCatalogMatchSoloPoolPresetEnum() {
        let soloCatalog = MiningSetupCatalog.soloPresets
        #expect(soloCatalog.count == SoloPoolPreset.allCases.count)
        for solo in SoloPoolPreset.allCases {
            guard let matching = soloCatalog.first(where: { $0.server == solo.server && $0.port == solo.port }) else {
                Issue.record("Missing matching preset in catalog for \(solo.title)")
                continue
            }
            #expect(matching.coin.symbol == solo.coin)
            #expect(matching.stratumProtocol == solo.stratumProtocol)
            #expect(matching.mode == .solo)
        }
    }
}
