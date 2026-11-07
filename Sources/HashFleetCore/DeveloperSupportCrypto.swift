import Foundation

/// Owner-approved public receiving destinations. These are not wallet credentials or transaction requests.
public enum DeveloperSupportCrypto: String, CaseIterable, Identifiable, Sendable {
    case bitcoin = "BTC"
    case ethereum = "ETH"
    case solana = "SOL"

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .bitcoin: "Bitcoin"
        case .ethereum: "Ethereum"
        case .solana: "Solana"
        }
    }

    public var network: String { "\(name) mainnet" }

    public var address: String {
        switch self {
        case .bitcoin: "1AZLMVdq1Dpc8FqibVUoMqJkh5wMQpd1wg"
        case .ethereum: "0xe0297d17680a3fa52975cf1cfc27bd2c1e73010c"
        case .solana: "2Ny4ZFGWtdVix4ZhGWCq3VCKLBRMC75aduCrYJUavA27"
        }
    }
}
