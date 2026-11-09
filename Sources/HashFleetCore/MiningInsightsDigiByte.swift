import Foundation

/// Parser for the public DigiByte SHA-256d SoloPool network endpoint.
///
/// `https://dgb-sha.solopool.org/api/stats` is the API used by the live dashboard whose
/// configuration sets `algoSha256` to true. Its nested `node.difficulty` is the network
/// difficulty used by that SHA-256d pool, not the top-level pool share difficulty.
enum MiningInsightsDigiByteParser {
    private struct Response: Decodable {
        let node: Node

        struct Node: Decodable {
            let height: Int
            let hashrate: Double
            let difficulty: Double
            let lastUpdate: TimeInterval
        }
    }

    static func statistics(_ data: Data) throws -> (BitcoinCashStatistics, Date?) {
        let response: Response
        do {
            response = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw MiningInsightsError.invalidData
        }

        let node = response.node
        guard node.height >= 0,
            node.hashrate.isFinite, node.hashrate > 0,
            node.difficulty.isFinite, node.difficulty > 0,
            node.lastUpdate.isFinite, node.lastUpdate > 0,
            node.lastUpdate <= Date.distantFuture.timeIntervalSince1970
        else {
            throw MiningInsightsError.invalidData
        }

        let sourceTimestamp = Date(timeIntervalSince1970: node.lastUpdate)
        return (
            BitcoinCashStatistics(
                difficulty: node.difficulty,
                tipHeight: node.height,
                // The response's top-level hashrate is pool hashrate, while node.hashrate
                // is a current node estimate. Neither is a 24-hour network average.
                hashrate24HoursHPS: nil,
                sourceTimestamp: sourceTimestamp
            ),
            sourceTimestamp
        )
    }
}
