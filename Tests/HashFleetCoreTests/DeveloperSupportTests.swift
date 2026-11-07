import Foundation
import Testing
@testable import HashFleetCore

struct DeveloperSupportTests {
    private let fixture = "https://www.paypal.com/ncp/payment/TESTONLY123"

    @Test func cryptoDestinationsMatchOwnerApprovedWebsiteConfiguration() {
        #expect(DeveloperSupportCrypto.allCases.map(\.rawValue) == ["BTC", "ETH", "SOL"])
        #expect(DeveloperSupportCrypto.allCases.map(\.network) == ["Bitcoin mainnet", "Ethereum mainnet", "Solana mainnet"])
        #expect(DeveloperSupportCrypto.bitcoin.address == "1AZLMVdq1Dpc8FqibVUoMqJkh5wMQpd1wg")
        #expect(DeveloperSupportCrypto.ethereum.address == "0xe0297d17680a3fa52975cf1cfc27bd2c1e73010c")
        #expect(DeveloperSupportCrypto.solana.address == "2Ny4ZFGWtdVix4ZhGWCq3VCKLBRMC75aduCrYJUavA27")
        #expect(Set(DeveloperSupportCrypto.allCases.map(\.id)).count == 3)
        #expect(DeveloperSupportCrypto(rawValue: "bitcoin:untrusted") == nil)
        #expect(DeveloperSupportCrypto(rawValue: "DOGE") == nil)
    }

    @Test(arguments: [nil, "", "US", "usa", "CAN", "GBR", "DEU"] as [String?])
    func cryptoSupportRetainsFailClosedStorefrontGate(_ code: String?) {
        let support = DeveloperSupport.current
        #expect(support.cryptoDestinations(storefrontCountryCode: code, directDistribution: false).isEmpty)
        #expect(support.cryptoDestinations(storefrontCountryCode: code, directDistribution: true) == DeveloperSupportCrypto.allCases)
    }

    @Test func cryptoSupportIsAvailableForUSAWithoutRequiringPayPal() {
        let support = DeveloperSupport(paypalPaymentLink: "")
        #expect(support.checkoutURL(storefrontCountryCode: "USA", directDistribution: false) == nil)
        #expect(support.cryptoDestinations(storefrontCountryCode: "USA", directDistribution: false) == DeveloperSupportCrypto.allCases)
    }

    @Test func canonicalHostedLinkIsPreserved() {
        #expect(DeveloperSupport.validatedPayPalURL(fixture)?.absoluteString == fixture)
    }

    @Test func productionCheckoutUsesReviewedDestinationAndRetainsStorefrontGate() {
        let reviewed = "https://www.paypal.com/ncp/payment/6NAMWWPAKSFV2"
        let support = DeveloperSupport.current
        #expect(support.paypalURL?.absoluteString == reviewed)
        #expect(support.checkoutURL(storefrontCountryCode: "USA", directDistribution: false)?.absoluteString == reviewed)
        #expect(support.checkoutURL(storefrontCountryCode: nil, directDistribution: true)?.absoluteString == reviewed)
        let unsupported: [String?] = [nil, "", "CAN", "GBR"]
        for code in unsupported {
            #expect(support.checkoutURL(storefrontCountryCode: code, directDistribution: false) == nil)
        }
    }

    @Test(arguments: [
        "", " ", "https://www.paypal.com/ncp/payment/",
        "http://www.paypal.com/ncp/payment/ABC",
        "https://www.paypal.com.evil.invalid/ncp/payment/ABC",
        "https://www.paypal.com@evil.invalid/ncp/payment/ABC",
        "https://evil.invalid@www.paypal.com/ncp/payment/ABC",
        "https://www.paypal.com:443/ncp/payment/ABC",
        "https://www.sandbox.paypal.com/ncp/payment/ABC",
        "https://paypal.me/someone", "javascript:alert(1)",
        "https://www.paypal.com/ncp/payment/ABC?redirect=evil",
        "https://www.paypal.com/ncp/payment/ABC#fragment",
        "https://www.paypal.com/ncp/payment/ABC/extra",
        "https://www.paypal.com/ncp/payment/%41BC",
        "https://www.paypal.com/ncp/payment/../ABC",
        "https://www.paypal.com/ncp/payment/ABC\n",
        "https://www.paypal.com/ncp/payment/ＡBC",
        "https://www.paypal.com/ncp/payment/" + String(repeating: "A", count: 129)
    ])
    func unsafeOrUnconfiguredDestinationsAreRejected(_ candidate: String) {
        #expect(DeveloperSupport.validatedPayPalURL(candidate) == nil)
    }

    @Test func storeDistributionUsesActualUSAStorefrontOnly() {
        let support = DeveloperSupport(paypalPaymentLink: fixture)
        #expect(support.checkoutURL(storefrontCountryCode: "USA", directDistribution: false) != nil)
        let unsupported: [String?] = [nil, "", "US", "usa", "CAN", "GBR", "DEU"]
        for code in unsupported {
            #expect(support.checkoutURL(storefrontCountryCode: code, directDistribution: false) == nil)
        }
    }

    @Test func directDistributionDoesNotRequireAStorefront() {
        let support = DeveloperSupport(paypalPaymentLink: fixture)
        #expect(support.checkoutURL(storefrontCountryCode: nil, directDistribution: true) != nil)
        #expect(support.checkoutURL(storefrontCountryCode: "CAN", directDistribution: true) != nil)
    }

    @Test func missingCheckoutFailsClosedOnEveryDistribution() {
        let support = DeveloperSupport(paypalPaymentLink: "")
        #expect(support.checkoutURL(storefrontCountryCode: "USA", directDistribution: false) == nil)
        #expect(support.checkoutURL(storefrontCountryCode: nil, directDistribution: true) == nil)
    }
}
