import Foundation
import Testing
@testable import HashFleetWatchCore

@Suite struct WatchFleetSetupTransferTests {
    private func miner(_ n: Int, id: UUID = UUID()) throws -> WatchMiner {
        try WatchMiner(id: id, name: "M\(n)", address: "192.168.1.\(n)")
    }

    @Test func roundTrip() throws {
        let transfer = try WatchFleetSetupTransfer(miners: [miner(1), miner(2)])
        #expect(transfer.version == 1)
        let decoded = try JSONDecoder().decode(WatchFleetSetupTransfer.self, from: JSONEncoder().encode(transfer))
        #expect(decoded == transfer)
        #expect(decoded.id == transfer.id)
    }

    @Test func rejectsEmptyTooManyAndDuplicates() throws {
        #expect(throws: WatchFleetSetupTransferError.noMiners) { try WatchFleetSetupTransfer(miners: []) }
        let many = try (1...17).map { try miner($0) }
        #expect(throws: WatchFleetSetupTransferError.tooManyMiners) { try WatchFleetSetupTransfer(miners: many) }
        let shared = UUID()
        #expect(throws: WatchFleetSetupTransferError.duplicateIdentifier) {
            try WatchFleetSetupTransfer(miners: [try miner(1, id: shared), try miner(2, id: shared)])
        }
        #expect(throws: WatchFleetSetupTransferError.duplicateEndpoint) {
            try WatchFleetSetupTransfer(miners: [try miner(1), try miner(1)])
        }
        // Equivalent spellings of one endpoint are duplicates too.
        #expect(throws: WatchFleetSetupTransferError.duplicateEndpoint) {
            try WatchFleetSetupTransfer(miners: [
                try WatchMiner(name: "a", address: "192.168.1.9"),
                try WatchMiner(name: "b", address: "http://192.168.1.9:80/")
            ])
        }
    }

    @Test func acceptsExactlySixteen() throws {
        let sixteen = try (1...16).map { try miner($0) }
        #expect(try WatchFleetSetupTransfer(miners: sixteen).miners.count == 16)
    }

    @Test func decodingRejectsUnsupportedVersion() throws {
        let transfer = try WatchFleetSetupTransfer(miners: [miner(1)])
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(transfer)) as? [String: Any])
        object["version"] = 2
        let data = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: WatchFleetSetupTransferError.unsupportedVersion) {
            try JSONDecoder().decode(WatchFleetSetupTransfer.self, from: data)
        }
        object.removeValue(forKey: "version")
        let missing = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(WatchFleetSetupTransfer.self, from: missing) }
    }

    @Test func decodingRejectsUnsafeAddressAndShape() throws {
        let id = UUID().uuidString, mid = UUID().uuidString
        let publicAddr = #"{"id":"\#(id)","version":1,"miners":[{"id":"\#(mid)","name":"x","address":"http://8.8.8.8"}]}"#
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(WatchFleetSetupTransfer.self, from: Data(publicAddr.utf8)) }
        let empty = #"{"id":"\#(id)","version":1,"miners":[]}"#
        #expect(throws: WatchFleetSetupTransferError.noMiners) {
            try JSONDecoder().decode(WatchFleetSetupTransfer.self, from: Data(empty.utf8))
        }
        let dup = #"{"id":"\#(id)","version":1,"miners":[{"id":"\#(mid)","name":"a","address":"192.168.1.1"},{"id":"\#(mid)","name":"b","address":"192.168.1.2"}]}"#
        #expect(throws: WatchFleetSetupTransferError.duplicateIdentifier) {
            try JSONDecoder().decode(WatchFleetSetupTransfer.self, from: Data(dup.utf8))
        }
    }

    @Test func payloadCarriesOnlyConfiguration() throws {
        let transfer = try WatchFleetSetupTransfer(miners: [miner(1)])
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(transfer)) as? [String: Any])
        #expect(Set(object.keys) == ["id", "version", "miners"])
        let first = try #require((object["miners"] as? [[String: Any]])?.first)
        #expect(Set(first.keys) == ["id", "name", "address"])
    }
}
