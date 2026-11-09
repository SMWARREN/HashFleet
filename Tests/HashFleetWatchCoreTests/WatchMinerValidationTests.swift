import Foundation
import Testing
@testable import HashFleetWatchCore

@Suite struct WatchMinerValidationTests {
    @Test(arguments: [
        ("192.168.1.50", "http://192.168.1.50"),
        ("192.168.1.50/", "http://192.168.1.50"),
        ("http://192.168.1.50:80/", "http://192.168.1.50"),
        ("https://192.168.1.50:443", "https://192.168.1.50"),
        ("http://10.0.0.7:8080", "http://10.0.0.7:8080"),
        ("172.16.0.1", "http://172.16.0.1"),
        ("172.31.255.254", "http://172.31.255.254"),
        ("  HTTP://Miner.LOCAL  ", "http://miner.local"),
        ("bitaxe", "http://bitaxe"),
        ("bitaxe-1:81", "http://bitaxe-1:81")
    ])
    func acceptsAndNormalizesLocalEndpoints(input: String, expected: String) throws {
        let miner = try WatchMiner(name: "Test", address: input)
        #expect(miner.address == expected)
    }

    @Test(arguments: [
        ("", WatchMinerValidationError.emptyAddress),
        ("   ", .emptyAddress),
        ("ftp://192.168.1.5", .unsupportedScheme),
        ("ws://192.168.1.5", .unsupportedScheme),
        ("http://user:pw@192.168.1.5", .credentialsNotAllowed),
        ("user@192.168.1.5", .credentialsNotAllowed),
        ("http://192.168.1.5/api", .pathNotAllowed),
        ("http://192.168.1.5/?a=1", .pathNotAllowed),
        ("http://192.168.1.5#frag", .pathNotAllowed),
        ("http://192.168.1.5:0", .invalidPort),
        ("http://192.168.1.5:65536", .invalidPort),
        ("http://192.168.1.5:abc", .invalidPort),
        ("http://192.168.1.5:", .invalidPort),
        ("http://192.168.1.5:1:2", .malformedAddress),
        ("8.8.8.8", .notLocalAddress),
        ("1.1.1.1", .notLocalAddress),
        ("172.15.0.1", .notLocalAddress),
        ("172.32.0.1", .notLocalAddress),
        ("192.169.1.1", .notLocalAddress),
        ("127.0.0.1", .notLocalAddress),
        ("localhost", .notLocalAddress),
        ("169.254.1.1", .notLocalAddress),
        ("example.com", .notLocalAddress),
        ("miner.example.com", .notLocalAddress),
        ("192.168.1", .notLocalAddress),
        ("192.168.1.1.1", .notLocalAddress),
        ("192.168.001.5", .notLocalAddress),
        ("192.168.1.256", .notLocalAddress),
        ("0x7f.0.0.1", .notLocalAddress),
        ("0x7f000001", .notLocalAddress),
        ("2130706433", .notLocalAddress),
        ("017700000001", .notLocalAddress),
        ("[::1]", .malformedAddress),
        ("::1", .malformedAddress),
        ("192.168.1.5%25en0", .malformedAddress),
        ("mine r.local", .malformedAddress),
        ("-bad.local", .malformedAddress),
        ("miner..local", .malformedAddress),
        (".local", .malformedAddress),
        ("mîner.local", .malformedAddress),
        ("localhost.local", .notLocalAddress)
    ])
    func rejectsUnsafeEndpoints(input: String, expected: WatchMinerValidationError) {
        #expect(throws: expected) { try WatchMiner(name: "Test", address: input) }
    }

    @Test func rejectsBadNames() {
        #expect(throws: WatchMinerValidationError.emptyName) { try WatchMiner(name: "  ", address: "192.168.1.5") }
        #expect(throws: WatchMinerValidationError.nameTooLong) {
            try WatchMiner(name: String(repeating: "a", count: 49), address: "192.168.1.5")
        }
        #expect(throws: WatchMinerValidationError.invalidName) { try WatchMiner(name: "a\u{0007}b", address: "192.168.1.5") }
        #expect(throws: WatchMinerValidationError.invalidName) { try WatchMiner(name: "a\nb", address: "192.168.1.5") }
    }

    @Test func trimsName() throws {
        #expect(try WatchMiner(name: "  Gamma  ", address: "192.168.1.5").name == "Gamma")
    }

    @Test func decodingRevalidatesAddress() throws {
        let id = UUID()
        let bad = #"{"id":"\#(id.uuidString)","name":"x","address":"http://8.8.8.8"}"#
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(WatchMiner.self, from: Data(bad.utf8)) }
        let good = #"{"id":"\#(id.uuidString)","name":"x","address":"192.168.1.5/"}"#
        let miner = try JSONDecoder().decode(WatchMiner.self, from: Data(good.utf8))
        #expect(miner.address == "http://192.168.1.5")
        #expect(miner.id == id)
    }

    @Test func codableRoundTrip() throws {
        let miner = try WatchMiner(name: "Duo", address: "https://miner.local:8443")
        let decoded = try JSONDecoder().decode(WatchMiner.self, from: JSONEncoder().encode(miner))
        #expect(decoded == miner)
    }

    @Test func validationMessagesAreReadable() {
        #expect(WatchMinerValidationError.notLocalAddress.errorDescription?.isEmpty == false)
        #expect(WatchMinerValidationError.emptyName.localizedDescription.contains("name"))
    }
}
