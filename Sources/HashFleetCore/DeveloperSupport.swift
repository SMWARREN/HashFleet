import Foundation

/// Public support configuration only. Never put payment credentials or wallet secrets here.
public struct DeveloperSupport: Sendable {
    // Created in the owner's Business account and inspected as a guest on 2026-11-01.
    // Public payment link only. Empty configurations still fail closed.
    public static let current = DeveloperSupport(
        paypalPaymentLink: "https://www.paypal.com/ncp/payment/6NAMWWPAKSFV2"
    )

    public static let title = "Support Hash Fleet"
    public static let explanation =
        "Optional developer tip. Hash Fleet stays free, with no features unlocked by payment."
    public static let checkoutNotice =
        "Opens PayPal in your browser. Available payment methods and any verification are handled by PayPal. " +
        "Hash Fleet does not receive your payment details or send miner information."
    public static let cryptoNotice =
        "Use only the named network. Check the full address in your wallet before sending. " +
        "Copying an address does not open a wallet or send a payment. Cryptocurrency transfers are generally irreversible."

    /// Approved StoreKit 2 consumable tip product identifiers for App Store builds.
    public static let appStoreTipProductIDs: Set<String> = [
        "app.hashfleet.tip.small",
        "app.hashfleet.tip.medium",
        "app.hashfleet.tip.large",
        "app.hashfleet.tip.supporter",
        "app.hashfleet.tip.champion",
        "app.hashfleet.tip.patron"
    ]

    public let paypalURL: URL?

    public init(paypalPaymentLink: String) {
        paypalURL = Self.validatedPayPalURL(paypalPaymentLink)
    }

    /// Store-distributed apps fail closed for unknown or unsupported storefronts.
    /// Direct distribution is an explicit build choice, never inferred from locale or IP.
    public func checkoutURL(storefrontCountryCode: String?, directDistribution: Bool) -> URL? {
        guard Self.isAvailable(storefrontCountryCode: storefrontCountryCode, directDistribution: directDistribution) else { return nil }
        return paypalURL
    }

    public func cryptoDestinations(storefrontCountryCode: String?, directDistribution: Bool) -> [DeveloperSupportCrypto] {
        guard Self.isAvailable(storefrontCountryCode: storefrontCountryCode, directDistribution: directDistribution) else { return [] }
        return DeveloperSupportCrypto.allCases
    }

    private static func isAvailable(storefrontCountryCode: String?, directDistribution: Bool) -> Bool {
        directDistribution || storefrontCountryCode == "USA"
    }

    /// Accept only canonical hosted Payment Links, not arbitrary redirects, PayPal.me,
    /// sandbox destinations, userinfo, query parameters, or payment URLs from miner data.
    public static func validatedPayPalURL(_ value: String) -> URL? {
        let prefix = "https://www.paypal.com/ncp/payment/"
        guard value.hasPrefix(prefix) else { return nil }
        let identifier = value.dropFirst(prefix.count)
        guard !identifier.isEmpty, identifier.count <= 128,
              identifier.utf8.allSatisfy({ byte in
                  (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte)
              }) else { return nil }
        return URL(string: value)
    }
}
