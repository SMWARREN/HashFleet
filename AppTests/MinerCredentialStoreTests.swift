import Foundation
import Testing
@testable import HashFleet

@Suite("XMRig credential keychain", .serialized)
struct MinerCredentialStoreTests {
    @Test func emptyAndMissingReferencesNeverTouchStoredTokens() throws {
        let reference = try MinerCredentialStore.save(token: "   \n")
        #expect(MinerCredentialStore.token(for: reference) == nil)
        #expect(MinerCredentialStore.token(for: nil) == nil)
        #expect(MinerCredentialStore.token(for: "") == nil)
        #expect(MinerCredentialStore.token(for: "missing-\(UUID().uuidString)") == nil)
        MinerCredentialStore.remove(reference: nil)
        MinerCredentialStore.remove(reference: "")
        #expect(MinerCredentialError.keychain(-1).errorDescription?.isEmpty == false)
    }

    @Test func saveReadsBackAndReplaceRemovesOnlyThatReference() throws {
        let reference = "coverage-\(UUID().uuidString)"
        defer { MinerCredentialStore.remove(reference: reference) }

        let saved = try MinerCredentialStore.save(token: " first-token ", reference: reference)
        #expect(saved == reference)
        #expect(MinerCredentialStore.token(for: reference) == "first-token")

        _ = try MinerCredentialStore.save(token: "replaced-token", reference: reference)
        #expect(MinerCredentialStore.token(for: reference) == "replaced-token")

        MinerCredentialStore.remove(reference: reference)
        #expect(MinerCredentialStore.token(for: reference) == nil)
    }
}
