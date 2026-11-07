import Foundation
import HashFleetCore

/// Compiles with production MinerDiscovery.swift and AddMinerMultiSelection.swift.
/// No NSApplication, NSWindow, saved fleet, network scan, or hardware request is created.
/// This verifies completion ownership and add semantics, not native-window hang acceptance.
@main
@MainActor
struct NativeMacAddMinerCompletionProbe {
    struct Failure: Error { let message: String }

    static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw Failure(message: message) }
    }

    static func main() throws {
        let a = MinerDiscoveryCandidate(address: "192.0.2.2", name: "A", model: nil)
        let b = MinerDiscoveryCandidate(address: "192.0.2.10", name: "B", model: nil)
        var owners: [String] = []
        AddMinerMultiSelection.completeInWorkspace(
            returnToFleet: { owners.append("workspace") },
            dismiss: { owners.append("child") }
        )
        try require(owners == ["workspace"], "Workspace completion must not also dismiss its child")

        owners = []
        AddMinerMultiSelection.completeInWorkspace(
            returnToFleet: nil, dismiss: { owners.append("child") }
        )
        try require(owners == ["child"], "Standalone completion must dismiss exactly once")

        var calls: [(String, String)] = []
        let complete = AddMinerMultiSelection.addAll(
            candidates: [b, a, a], alreadyAdded: [], customName: " Desk "
        ) { calls.append(($0, $1)) }
        try require(calls.map(\.1) == [a.address, b.address], "Numeric ordering and no duplicate writes")
        try require(calls.map(\.0) == ["Desk", ""], "Apply a custom name to the first miner only")
        try require(complete.addedAddresses == [a.address, b.address] && complete.failures.isEmpty, "Keep both successful addresses")

        calls = []
        let noOp = AddMinerMultiSelection.addAll(
            candidates: [b, a], alreadyAdded: complete.addedAddresses, customName: "Ignored"
        ) { calls.append(($0, $1)) }
        try require(calls.isEmpty && noOp.failures.isEmpty, "Existing entries must not be written again")

        let duplicate = AddMinerMultiSelection.addAll(
            candidates: [a], alreadyAdded: [], customName: ""
        ) { _, _ in throw FleetError.duplicate }
        try require(duplicate.failures.isEmpty && duplicate.addedAddresses == [a.address], "Store duplicate is an existing success")

        let partial = AddMinerMultiSelection.addAll(
            candidates: [a, b], alreadyAdded: [], customName: ""
        ) { _, address in
            if address == a.address { throw FleetError.invalidName }
        }
        try require(partial.addedAddresses == [b.address] && partial.failures.count == 1, "Partial failure retains successes")
        calls = []
        let retry = AddMinerMultiSelection.addAll(
            candidates: [a, b], alreadyAdded: partial.addedAddresses, customName: ""
        ) { calls.append(($0, $1)) }
        try require(calls.map(\.1) == [a.address] && retry.failures.isEmpty, "Retry writes only the failed miner")

        calls = []
        let empty = AddMinerMultiSelection.addAll(
            candidates: [], alreadyAdded: [], customName: ""
        ) { calls.append(($0, $1)) }
        try require(calls.isEmpty && empty.addedAddresses.isEmpty && empty.failures.isEmpty, "Empty candidate set has no add side effects")
        print("PASS actual production source: mutually exclusive completion owners; bulk ordering, names, duplicates, no-op, partial failure, retry and empty input. No app/window/network created.")
    }
}
