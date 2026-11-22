import HashFleetCore
import Testing
@testable import HashFleet

struct MinerEssentialsPoolTests {
    @Test func editsOnlyTheAssignedRecordAndPreservesAllAdvancedFields() throws {
        let raw = modernInfo()
        let baseline = try #require(MinerEssentialsPoolBaseline(role: .primary, raw: raw))
        #expect(baseline.connection.address == "primary.example.invalid:3333")
        var draft = baseline.connection
        draft.port = "4444"
        let change = try #require(try baseline.plan(for: draft, password: ""))
        let records = try #require(change.payload["pools"]?.arrayValue)
        #expect(change.payload.objectValue?.keys.sorted() == ["pools"])
        #expect(records.count == 1)
        var expected = primaryRecord
        expected["stratumPort"] = .integer(4444)
        expected["stratumPassword"] = .string("*****")
        #expect(records.first?.objectValue == expected)
        #expect(change.address == "primary.example.invalid:4444")
        #expect(!baseline.matches(change, raw: raw))
        var readback = raw
        readback["pools"] = .array([.object(fallbackRecord), .object(expected)])
        #expect(baseline.matches(change, raw: readback))
        // An accepted request that resets an advanced option is not a verified save.
        expected["stratumShareWarning"] = .bool(true)
        readback["pools"] = .array([.object(fallbackRecord), .object(expected)])
        #expect(!baseline.matches(change, raw: readback))
    }

    @Test func legacyFallbackNeverUsesPrimaryKeysOrOverwritesUneditedFields() throws {
        let raw: [String: JSONValue] = [
            "stratumURL": .string("primary.example.invalid"), "stratumPort": .integer(3333),
            "stratumUser": .string("sample.primary"), "fallbackStratumURL": .string(""),
            "fallbackStratumPort": .integer(3333), "fallbackStratumUser": .string(""),
            "fallbackStratumTLS": .integer(1), "fallbackStratumPassword": .string("private-old-fixture")
        ]
        let baseline = try #require(MinerEssentialsPoolBaseline(role: .fallback, raw: raw))
        var draft = baseline.connection
        #expect(draft.address == "Not configured")
        draft.server = "backup.example.invalid"
        draft.worker = "test-worker"
        #expect(throws: MinerEssentialsPoolBaseline.FormError.newPassword) { try baseline.plan(for: draft, password: "") }
        let change = try #require(try baseline.plan(for: draft, password: "new-fixture"))
        #expect(change.payload == .object([
            "fallbackStratumURL": .string("backup.example.invalid"), "fallbackStratumUser": .string("test-worker"),
            "fallbackStratumPassword": .string("new-fixture")
        ]))
        var readback = raw
        readback["fallbackStratumURL"] = .string(draft.server)
        readback["fallbackStratumUser"] = .string(draft.worker)
        readback["fallbackStratumPassword"] = .string("*****")
        #expect(baseline.matches(change, raw: readback))
    }

    @Test func refusingUnknownModernShapesNeverFallsBackToLegacyAliases() throws {
        var raw = modernInfo()
        raw["stratumURL"] = .string("alias.example.invalid")
        raw["stratumPort"] = .integer(3333)
        raw["stratumUser"] = .string("worker")
        raw["pools"] = .null
        #expect(MinerEssentialsPoolBaseline(role: .primary, raw: raw) == nil)
        #expect(MinerEssentialsPoolBaseline.reportedConnection(.primary, raw: raw)?.server == "alias.example.invalid")
        raw = modernInfo()
        raw["secondaryPoolIndex"] = raw["primaryPoolIndex"]
        #expect(MinerEssentialsPoolBaseline(role: .primary, raw: raw) == nil)
        #expect(MinerEssentialsPoolBaseline(role: .fallback, raw: raw) == nil)
        raw = modernInfo()
        raw["pools"] = .array([.object(primaryRecord), .object(primaryRecord), .object(fallbackRecord)])
        #expect(MinerEssentialsPoolBaseline(role: .primary, raw: raw) == nil)
        var extra = primaryRecord
        extra["new-advanced-setting"] = .integer(7)
        raw["pools"] = .array([.object(extra), .object(fallbackRecord)])
        #expect(MinerEssentialsPoolBaseline(role: .primary, raw: raw) == nil)
        extra = primaryRecord
        extra.removeValue(forKey: "rotationWeight")
        raw["pools"] = .array([.object(extra), .object(fallbackRecord)])
        #expect(MinerEssentialsPoolBaseline(role: .primary, raw: raw) == nil)
    }

    @Test func draftRequiresSafeExplicitValuesAndDoesNotWriteAnUnchangedConnection() throws {
        let baseline = try #require(MinerEssentialsPoolBaseline(role: .primary, raw: modernInfo()))
        #expect(try baseline.plan(for: baseline.connection, password: "") == nil)
        var draft = baseline.connection
        draft.port = "65536"
        #expect(throws: MinerEssentialsPoolBaseline.FormError.port) { try baseline.plan(for: draft, password: "") }
        draft = baseline.connection
        draft.server = "https://primary.example.invalid:4444/path"
        #expect(throws: MinerEssentialsPoolBaseline.FormError.server) { try baseline.plan(for: draft, password: "") }
        draft.server = "new.example.invalid"
        #expect(throws: MinerEssentialsPoolBaseline.FormError.newPassword) { try baseline.plan(for: draft, password: "") }
        #expect(throws: MinerEssentialsPoolBaseline.FormError.password) { try baseline.plan(for: draft, password: "*****") }
        let change = try #require(try baseline.plan(for: draft, password: "sample-password"))
        #expect(change.payload["pools"]?.arrayValue?.first?["stratumPassword"] == .string("sample-password"))
    }

    private var primaryRecord: [String: JSONValue] {
        ["id": .integer(5), "stratumURL": .string("primary.example.invalid"), "stratumPort": .integer(3333),
         "stratumUser": .string("demo.worker"), "stratumPassword": .string("unmasked-synthetic-fixture"),
         "stratumProtocol": .string("SV2"), "stratumSuggestedDifficulty": .integer(32),
         "stratumExtranonceSubscribe": .bool(true), "stratumTLS": .integer(2), "stratumCert": .string("test-cert"),
         "stratumDecodeCoinbase": .bool(false), "stratumShareWarning": .bool(false),
         "stratumV2ChannelType": .string("extended"), "stratumV2AuthorityPubkey": .string("test-key"),
         "stratumV2RequireAuth": .bool(true), "rotationEnabled": .bool(false), "rotationWeight": .integer(13)]
    }

    private var fallbackRecord: [String: JSONValue] {
        var result = primaryRecord
        result["id"] = .integer(2)
        result["stratumURL"] = .string("backup.example.invalid")
        return result
    }

    private func modernInfo() -> [String: JSONValue] {
        ["primaryPoolIndex": .integer(5), "secondaryPoolIndex": .integer(2),
         "pools": .array([.object(fallbackRecord), .object(primaryRecord)])]
    }
}
