import XCTest
import HashFleetCore
import HashFleetWatchCore
@testable import HashFleet

final class FleetWatchSetupSelectionTests: XCTestCase {
    func testOnlyCredentialFreeLocalASICsAreSelected() {
        let local = MinerDevice(name: "Local ASIC", address: "192.168.1.40")
        let protected = MinerDevice(name: "Protected", address: "192.168.1.41", keychainCredentialReference: "private-token-reference")
        let cpu = MinerDevice(name: "CPU miner", address: "192.168.1.42", kind: .xmrig)
        let publicHost = MinerDevice(name: "Public host", address: "https://example.com")
        let embeddedPassword = MinerDevice(name: "Credentials", address: "http://user:secret@192.168.1.43")
        let selection = FleetWatchSetupSelection(
            devices: [local, protected, cpu, publicHost, embeddedPassword], isDemo: false)
        XCTAssertEqual(selection.miners.map(\.id), [local.id])
        XCTAssertEqual(selection.skippedCount, 4)
    }

    func testDemoNeverExportsSavedRealFleet() {
        let selection = FleetWatchSetupSelection(
            devices: [MinerDevice(name: "Real", address: "192.168.1.40")], isDemo: true)
        XCTAssertTrue(selection.miners.isEmpty)
        XCTAssertEqual(selection.skippedCount, 1)
    }

    func testNormalizedDuplicateAddressesAreNotSentTwice() {
        let first = MinerDevice(name: "First", address: "192.168.1.40")
        let selection = FleetWatchSetupSelection(devices: [
            first, MinerDevice(name: "Duplicate", address: "http://192.168.1.40:80/")
        ], isDemo: false)
        XCTAssertEqual(selection.miners.map(\.id), [first.id])
        XCTAssertEqual(selection.skippedCount, 1)
    }

    func testTransferContainsOnlyBoundedConfigurationFields() throws {
        let selection = FleetWatchSetupSelection(
            devices: [MinerDevice(name: "Local", address: "192.168.1.40")], isDemo: false)
        let data = try JSONEncoder().encode(WatchFleetSetupTransfer(miners: selection.miners))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(root.keys), ["id", "version", "miners"])
        let miners = try XCTUnwrap(root["miners"] as? [[String: Any]])
        XCTAssertEqual(miners.count, 1)
        XCTAssertEqual(Set(miners[0].keys), ["id", "name", "address"])
    }
}
