import Foundation
import Testing
import HashFleetCore
@testable import HashFleet

extension MinerTuningTests {
    @Test func displayPayloadsChangeOnlyOneSelectedField() throws {
        #expect(try MinerTuningDraft.rotationPayload(90) == .object(["rotation": .integer(90)]))
        #expect(MinerTuningDraft.inversionPayload(true) == .object(["invertscreen": .integer(1)]))
        #expect(MinerTuningDraft.inversionPayload(false) == .object(["invertscreen": .integer(0)]))
        #expect(try MinerTuningDraft.displayTimeoutPayload("-1") == .object(["displayTimeout": .integer(-1)]))
        #expect(try MinerTuningDraft.displayTimeoutPayload("0") == .object(["displayTimeout": .integer(0)]))
        #expect(try MinerTuningDraft.displayTimeoutPayload("10") == .object(["displayTimeout": .integer(10)]))
    }

    @Test func displayValidationFollowsActualHandlerInsteadOfSchemaTypos() {
        #expect(throws: (any Error).self) { try MinerTuningDraft.rotationPayload(nil) }
        #expect(throws: (any Error).self) { try MinerTuningDraft.rotationPayload(1) }
        #expect(throws: (any Error).self) { try MinerTuningDraft.rotationPayload(360) }
        #expect(throws: (any Error).self) { try MinerTuningDraft.displayTimeoutPayload("-2") }
        #expect(throws: (any Error).self) { try MinerTuningDraft.displayTimeoutPayload("65536") }
        #expect(throws: (any Error).self) { try MinerTuningDraft.displayTimeoutPayload("NaN") }
    }

    @Test func capabilityReferencesUseOnlyGenuinelyReportedFields() throws {
        let reference = try MinerTuningReference(
            json: .object([
                "ASICModel": .string("BM1370"), "defaultFrequency": .number(525),
                "defaultVoltage": .integer(1200), "frequencyOptions": .array([.integer(500), .number(525.5)]),
                "voltageOptions": .array([.integer(1150), .integer(1200)]),
                "safeMaximumVoltage": .integer(9999), "safeMinimumFrequency": .integer(1)
            ])
        )
        #expect(reference.model == "BM1370")
        #expect(reference.defaultFrequency == 525)
        #expect(reference.defaultVoltage == 1200)
        #expect(reference.frequencyOptions == [500, 525.5])
        #expect(reference.voltageOptions == [1150, 1200])
    }

    @Test func absentOrMalformedReferencesAreNotFilledWithInventedOptions() throws {
        let empty = try MinerTuningReference(json: .object([:]))
        #expect(empty.defaultFrequency == nil)
        #expect(empty.defaultVoltage == nil)
        #expect(empty.frequencyOptions.isEmpty)
        #expect(empty.voltageOptions.isEmpty)
        let malformed = try MinerTuningReference(
            json: .object([
                "defaultFrequency": .string("500"), "defaultVoltage": .number(.infinity),
                "frequencyOptions": .array([.bool(true), .string("500"), .number(.nan), .number(-1), .null]),
                "voltageOptions": .object(["min": .integer(1100), "max": .integer(1300)])
            ])
        )
        #expect(malformed.defaultFrequency == nil)
        #expect(malformed.defaultVoltage == nil)
        #expect(malformed.frequencyOptions.isEmpty)
        #expect(malformed.voltageOptions.isEmpty)
        #expect(throws: (any Error).self) { try MinerTuningReference(json: .array([])) }
    }

    private func poolDraft() -> MinerTuningPoolDraft {
        MinerTuningPoolDraft(
            slot: 2,
            server: "pool.example",
            port: "3333",
            user: "worker",
            stratumProtocol: "SV1",
            replacePassword: false,
            password: ""
        )
    }

    @Test func poolSlotReplacementRequiresSeparateAcknowledgement() {
        let pool = poolDraft()
        #expect(throws: (any Error).self) { try pool.payload(replacementAcknowledged: false) }
        #expect(MinerTuningPoolDraft.replacementNotice.contains("FULL SLOT REPLACEMENT"))
        #expect(MinerTuningPoolDraft.replacementNotice.contains("TLS/certificate"))
        #expect(MinerTuningPoolDraft.replacementNotice.contains("firmware defaults"))
    }

    @Test func unchangedPoolPasswordUsesSentinelNeverOmissionOrRealPassword() throws {
        var pool = poolDraft()
        pool.password = "unused-sensitive-draft"
        let payload = try pool.payload(replacementAcknowledged: true)
        #expect(payload["stratumPassword"] == .string("*****"))
        #expect(!(try payload.prettyPrinted()).contains("unused-sensitive-draft"))
    }

    @Test func explicitlyReplacingOrClearingPoolPasswordIsIntentional() throws {
        var pool = poolDraft()
        pool.replacePassword = true
        pool.password = "new-fixture-password"
        #expect(try pool.payload(replacementAcknowledged: true)["stratumPassword"] == .string("new-fixture-password"))
        pool.password = ""
        #expect(try pool.payload(replacementAcknowledged: true)["stratumPassword"] == .string(""))
        pool.password = "*****"
        #expect(throws: (any Error).self) { try pool.payload(replacementAcknowledged: true) }
        pool.password = String(repeating: "a", count: 256)
        #expect(throws: (any Error).self) { try pool.payload(replacementAcknowledged: true) }
    }

    @Test func SV2PoolPayloadKeepsProtocolAndReplacementPasswordExplicit() throws {
        var pool = poolDraft()
        pool.stratumProtocol = "SV2"
        pool.replacePassword = true
        pool.password = "sv2-fixture-password"
        let payload = try pool.payload(replacementAcknowledged: true)
        #expect(payload["stratumProtocol"] == .string("SV2"))
        #expect(payload["stratumPassword"] == .string("sv2-fixture-password"))
    }

    @Test func acknowledgedPoolReplacementContainsOnlyExplicitBasicFieldsAndSentinel() throws {
        let payload = try poolDraft().payload(replacementAcknowledged: true)
        let fields = try #require(payload.objectValue)
        #expect(
            Set(fields.keys)
                == Set(["stratumURL", "stratumPort", "stratumUser", "stratumProtocol", "stratumPassword"])
        )
        #expect(payload["stratumTLS"] == nil)
        #expect(payload["stratumV2AuthorityPubkey"] == nil)
        #expect(payload["overheat_mode"] == nil)
        // Missing advanced values are intentionally not represented as preserved settings.
        #expect(MinerTuningPoolDraft.replacementNotice.contains("revert to firmware defaults"))
    }

    @Test(arguments: ["0", "65536", "3333.0", "NaN", "1e3", "-1", ""])
    func poolPortParsingIsStrict(_ input: String) {
        var pool = poolDraft()
        pool.port = input
        #expect(throws: (any Error).self) { try pool.payload(replacementAcknowledged: true) }
    }

    @Test func poolSlotAndRequiredFieldsAreValidated() {
        var pool = poolDraft()
        pool.slot = 8
        #expect(throws: (any Error).self) { try pool.payload(replacementAcknowledged: true) }
        pool.slot = -1
        #expect(throws: (any Error).self) { try pool.payload(replacementAcknowledged: true) }
        pool.slot = 0
        pool.server = " "
        #expect(throws: (any Error).self) { try pool.payload(replacementAcknowledged: true) }
        pool.server = "pool.example"
        pool.user = ""
        #expect(throws: (any Error).self) { try pool.payload(replacementAcknowledged: true) }
        pool.user = "worker"
        pool.stratumProtocol = "SV3"
        #expect(throws: (any Error).self) { try pool.payload(replacementAcknowledged: true) }
    }
}
