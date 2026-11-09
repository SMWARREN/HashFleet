import Foundation
import HashFleetCore

/// Pure decision logic for adding several discovered miners in one sheet session.
///
/// Discovery can surface multiple miners at once. Adding one must not dismiss the sheet,
/// so the view tracks which addresses it has already added. This type holds the rules that
/// are easy to get wrong (name assignment and duplicate handling) outside SwiftUI state.
enum AddMinerMultiSelection {
    struct BulkResult {
        var addedAddresses: Set<String>
        var failures: [String]
    }

    /// Retain successes on a partial failure and treat existing fleet entries as complete.
    static func addAll(
        candidates: [MinerDiscoveryCandidate], alreadyAdded: Set<String>, customName: String,
        add: (String, String) throws -> Void
    ) -> BulkResult {
        var result = BulkResult(addedAddresses: alreadyAdded, failures: [])
        for candidate in MinerDiscoveryService.sorted(candidates) {
            guard !result.addedAddresses.contains(candidate.address) else { continue }
            do {
                try add(name(forCustomName: customName, alreadyAdded: result.addedAddresses), candidate.address)
                result.addedAddresses.insert(candidate.address)
            } catch FleetError.duplicate {
                result.addedAddresses.insert(candidate.address)
            } catch {
                result.failures.append("\(candidate.name): \(error.localizedDescription)")
            }
        }
        return result
    }

    /// A native in-app page must finish through one owner. A system open request would
    /// reset the same stack and reopen its window while its dismiss is still being reconciled.
    /// Keep the fallback for standalone previews, which have no workspace callback.
    @MainActor
    static func completeInWorkspace(returnToFleet: (() -> Void)?, dismiss: () -> Void) {
        if let returnToFleet {
            returnToFleet()
        } else {
            dismiss()
        }
    }

    /// A custom name describes one specific miner, so it only applies to the first add.
    /// Later miners resolve their own model-derived name after the first live response.
    static func name(forCustomName custom: String, alreadyAdded: Set<String>) -> String {
        alreadyAdded.isEmpty ? custom.trimmingCharacters(in: .whitespacesAndNewlines) : ""
    }

    /// Addresses among `candidates` that are already in `devices`, compared with the same
    /// URL normalisation the store uses for duplicate detection.
    static func alreadyPresent(
        candidates: [MinerDiscoveryCandidate],
        devices: [MinerDevice]
    ) -> Set<String> {
        let existing = Set(devices.compactMap { try? $0.validatedURL() })
        return Set(
            candidates.filter { candidate in
                let probe = MinerDevice(name: "", address: candidate.address)
                guard let url = try? probe.validatedURL() else { return false }
                return existing.contains(url)
            }
            .map(\.address)
        )
    }
}
