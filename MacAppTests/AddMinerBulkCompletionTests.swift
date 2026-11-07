import Foundation
import Testing
import HashFleetCore
@testable import HashFleetMac

@Suite("Add all completion")
struct AddMinerBulkCompletionTests {
    private let a = MinerDiscoveryCandidate(address: "192.168.1.2", name: "A", model: nil)
    private let b = MinerDiscoveryCandidate(address: "192.168.1.10", name: "B", model: nil)

    @MainActor
    @Test func workspaceCompletionDoesNotAlsoDismissItsChild() {
        var owners: [String] = []
        AddMinerMultiSelection.completeInWorkspace(
            returnToFleet: { owners.append("workspace") },
            dismiss: { owners.append("child") }
        )
        #expect(owners == ["workspace"])
    }

    @MainActor
    @Test func standaloneCompletionDismissesExactlyOnce() {
        var dismissals = 0
        AddMinerMultiSelection.completeInWorkspace(
            returnToFleet: nil, dismiss: { dismissals += 1 }
        )
        #expect(dismissals == 1)
    }

    @Test func successAddsInNumericOrderAndUsesCustomNameOnce() {
        var calls: [(String, String)] = []
        let result = AddMinerMultiSelection.addAll(candidates: [b, a, a], alreadyAdded: [], customName: " Desk ") {
            calls.append(($0, $1))
        }
        #expect(calls.map(\.1) == [a.address, b.address])
        #expect(calls.map(\.0) == ["Desk", ""])
        #expect(result.addedAddresses == [a.address, b.address])
        #expect(result.failures.isEmpty)
    }

    @Test func existingEntriesAreCompleteWithoutDuplicateWrites() {
        var calls = 0
        let result = AddMinerMultiSelection.addAll(candidates: [a], alreadyAdded: [a.address], customName: "") { _, _ in calls += 1 }
        #expect(calls == 0)
        #expect(result.failures.isEmpty)
        #expect(result.addedAddresses == [a.address])
    }

    @Test func storeDuplicateCountsAsSuccess() {
        let result = AddMinerMultiSelection.addAll(candidates: [a], alreadyAdded: [], customName: "") { _, _ in throw FleetError.duplicate }
        #expect(result.failures.isEmpty)
        #expect(result.addedAddresses == [a.address])
    }

    @Test func partialFailureRetainsSuccessfulAddsAndRetryOnlyAddsMissing() {
        let result = AddMinerMultiSelection.addAll(candidates: [a, b], alreadyAdded: [], customName: "") { _, address in
            if address == a.address { throw FleetError.invalidName }
        }
        #expect(result.addedAddresses == [b.address])
        #expect(result.failures.count == 1)
        #expect(result.failures[0].contains("A"))
        var retried: [String] = []
        let retry = AddMinerMultiSelection.addAll(candidates: [a, b], alreadyAdded: result.addedAddresses, customName: "") { _, address in retried.append(address) }
        #expect(retried == [a.address])
        #expect(retry.failures.isEmpty)
        #expect(retry.addedAddresses == [a.address, b.address])
    }
}
