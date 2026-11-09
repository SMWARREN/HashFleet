import HashFleetCore
import Observation
import StoreKit
import SwiftUI

/// Uses the actual storefront, never device locale, for App Store checkout eligibility.
@MainActor
@Observable
final class DeveloperSupportAvailability {
    private(set) var storefrontCountryCode: String?
    private(set) var isResolved = false
    @ObservationIgnored private let currentCountryCode: @MainActor () async -> String?

    init(currentCountryCode: @escaping @MainActor () async -> String? = {
        await Storefront.current?.countryCode
    }) {
        self.currentCountryCode = currentCountryCode
    }

    var directDistribution: Bool {
        #if os(macOS) && HASHFLEET_DIRECT_DISTRIBUTION
        true
        #else
        false
        #endif
    }

    /// Whether this build uses native StoreKit 2 tipping.
    /// Direct-distribution Mac builds do not use native in-app purchases.
    var usesNativeTipJar: Bool {
        !directDistribution
    }

    var checkoutURL: URL? {
        // App Store variants show native StoreKit 2 IAP only (no external PayPal links)
        guard directDistribution else { return nil }
        return DeveloperSupport.current.checkoutURL(
            storefrontCountryCode: storefrontCountryCode,
            directDistribution: directDistribution
        )
    }

    var cryptoDestinations: [DeveloperSupportCrypto] {
        // App Store variants show native StoreKit 2 IAP only (no crypto address copying)
        guard directDistribution else { return [] }
        return DeveloperSupport.current.cryptoDestinations(
            storefrontCountryCode: storefrontCountryCode,
            directDistribution: directDistribution
        )
    }

    func observe(while phase: ScenePhase) async {
        storefrontCountryCode = nil
        isResolved = false
        guard phase == .active else { return }
        guard !directDistribution else {
            isResolved = true
            return
        }
        let countryCode = await currentCountryCode()
        guard !Task.isCancelled else { return }
        storefrontCountryCode = countryCode
        isResolved = true
        for await storefront in Storefront.updates {
            guard !Task.isCancelled else { return }
            storefrontCountryCode = storefront.countryCode
        }
    }

    /// Recheck at activation so an old US storefront cannot authorize a new checkout.
    func revalidatedURL() async -> URL? {
        await refreshStorefront()
        return Task.isCancelled ? nil : checkoutURL
    }

    /// Copying is an explicit action, with the same fresh storefront check as checkout.
    func revalidatedCryptoDestination(_ destination: DeveloperSupportCrypto) async -> DeveloperSupportCrypto? {
        await refreshStorefront()
        guard !Task.isCancelled else { return nil }
        return cryptoDestinations.first { $0 == destination }
    }

    private func refreshStorefront() async {
        if !directDistribution {
            let countryCode = await currentCountryCode()
            guard !Task.isCancelled else { return }
            storefrontCountryCode = countryCode
        }
    }
}
