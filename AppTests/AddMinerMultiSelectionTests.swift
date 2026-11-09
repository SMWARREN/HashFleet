import Foundation
import Testing
import HashFleetCore
@testable import HashFleet

/// Discovery can surface several miners at once. Adding one must not dismiss the sheet,
/// and must not misattribute the user's custom name to every miner found.
@Suite("Add miner multi-selection")
struct AddMinerMultiSelectionTests {
    private func candidate(_ address: String) -> MinerDiscoveryCandidate {
        MinerDiscoveryCandidate(address: address, name: "Bitaxe", model: "BM1370")
    }

    /// An isolated defaults suite per test, so a shared on-disk fleet cannot leak between tests.
    @MainActor
    private func isolatedStore() -> (store: FleetStore, defaults: UserDefaults, suite: String) {
        let suite = "app.hashfleet.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (FleetStore(defaults: defaults), defaults, suite)
    }

    @Test func customNameAppliesOnlyToTheFirstMinerAdded() {
        var added: Set<String> = []
        #expect(AddMinerMultiSelection.name(forCustomName: "  Desk miner  ", alreadyAdded: added) == "Desk miner")
        added.insert("192.168.1.10")
        // The second and third miners must fall back to automatic naming, not reuse "Desk miner".
        #expect(AddMinerMultiSelection.name(forCustomName: "Desk miner", alreadyAdded: added).isEmpty)
        added.insert("192.168.1.11")
        #expect(AddMinerMultiSelection.name(forCustomName: "Desk miner", alreadyAdded: added).isEmpty)
    }

    @Test func blankCustomNameStaysBlankForTheFirstMiner() {
        #expect(AddMinerMultiSelection.name(forCustomName: "   ", alreadyAdded: []).isEmpty)
    }

    @Test func candidatesAlreadyInTheFleetAreDetectedAcrossAddressSpellings() throws {
        let devices = [
            MinerDevice(name: "One", address: "192.168.1.10"),
            MinerDevice(name: "Two", address: "http://192.168.1.11")
        ]
        let present = AddMinerMultiSelection.alreadyPresent(
            candidates: [candidate("192.168.1.10"), candidate("192.168.1.11"), candidate("192.168.1.12")],
            devices: devices
        )
        #expect(present == ["192.168.1.10", "192.168.1.11"])
        // A genuinely new miner must remain addable.
        #expect(!present.contains("192.168.1.12"))
    }

    @Test func emptyFleetMarksNothingAsPresent() {
        #expect(
            AddMinerMultiSelection.alreadyPresent(
                candidates: [candidate("192.168.1.10")], devices: []
            ).isEmpty
        )
    }

    /// The end-to-end rule this feature exists for: several discovered miners land in the
    /// fleet from one sheet session, each with its own distinct address.
    @Test @MainActor func addingSeveralDiscoveredMinersKeepsThemAll() throws {
        let (store, defaults, suite) = isolatedStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        var added: Set<String> = []
        for address in ["192.168.1.10", "192.168.1.11", "192.168.1.12"] {
            let name = AddMinerMultiSelection.name(forCustomName: "Desk miner", alreadyAdded: added)
            try store.add(name: name, address: address)
            added.insert(address)
        }
        #expect(store.devices.count == 3)
        #expect(added.count == 3)
        #expect(Set(store.devices.map(\.address)).count == 3)
        // Only the first miner keeps the typed name; the rest are automatic.
        #expect(store.devices.filter { $0.usesAutomaticName == false }.count == 1)
        #expect(store.devices.first(where: { $0.usesAutomaticName == false })?.name == "Desk miner")
    }

    @Test @MainActor func reAddingTheSameDiscoveredMinerIsRejectedAsDuplicate() throws {
        let (store, defaults, suite) = isolatedStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        try store.add(name: "", address: "192.168.1.10")
        var threwDuplicate = false
        do {
            try store.add(name: "", address: "192.168.1.10")
        } catch FleetError.duplicate {
            threwDuplicate = true
        }
        #expect(threwDuplicate)
        #expect(store.devices.count == 1)
        // And the sheet would show that row as already added rather than offering it again.
        #expect(
            AddMinerMultiSelection.alreadyPresent(
                candidates: [candidate("192.168.1.10")], devices: store.devices
            ) == ["192.168.1.10"]
        )
    }
}
