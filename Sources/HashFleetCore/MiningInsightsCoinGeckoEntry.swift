import Foundation

/// One CoinGecko market entry in the read-only market list response.
struct CoinGeckoResponse: Decodable {
    let id: String
    let symbol: String
    let name: String
    let image: String?
    let currentPrice: Double?
    let marketCapRank: Int?

    enum CodingKeys: String, CodingKey {
        case id, symbol, name, image
        case currentPrice = "current_price"
        case marketCapRank = "market_cap_rank"
    }
}
