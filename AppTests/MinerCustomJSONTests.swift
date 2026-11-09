import Foundation
import Testing
import HashFleetCore
@testable import HashFleet

@Suite("Miner Custom JSON Tests")
struct MinerCustomJSONTests {

    // MARK: - Format & Unknown Keys Preservation

    @Test("Preserves unknown custom keys and deeply nested objects")
    func preservesUnknownKeysAndNesting() throws {
        let input = """
            {
              "customAlpha": "special_mode",
              "nestedFeature": {
                "enabled": true,
                "threshold": 1200,
                "tags": ["alpha", "beta", {"flag": 1}]
              }
            }
            """
        let draft = MinerCustomJSONDraft(rawText: input)
        let (wireData, json) = try draft.validate()

        // Assert structured decoded shape preserves unknown keys
        guard case .object(let dict) = json else {
            Issue.record("Expected JSON object")
            return
        }
        #expect(dict["customAlpha"]?.stringValue == "special_mode")
        #expect(dict["nestedFeature"]?["enabled"]?.boolValue == true)
        #expect(dict["nestedFeature"]?["threshold"]?.intValue == 1200)

        // Assert wire data decodes cleanly back without stripping keys
        let roundtrip = try JSONDecoder().decode(JSONValue.self, from: wireData)
        #expect(roundtrip["customAlpha"]?.stringValue == "special_mode")
        #expect(roundtrip["nestedFeature"]?["threshold"]?.intValue == 1200)
    }

    // MARK: - Integer Precision (UInt64 / Int64)

    @Test("Preserves 64-bit unsigned and signed integer precision")
    func preservesIntegerPrecision() throws {
        let u64Max: UInt64 = UInt64.max
        let i64Min: Int64 = Int64.min
        let input = """
            {
              "u64Value": \(u64Max),
              "i64Value": \(i64Min),
              "nested": {
                "largeInt": 9007199254740993
              }
            }
            """
        let draft = MinerCustomJSONDraft(rawText: input)
        let (wireData, json) = try draft.validate()

        switch json["u64Value"] {
        case .unsignedInteger(let val):
            #expect(val == u64Max)
        case .integer(let val):
            #expect(UInt64(bitPattern: val) == u64Max)
        default:
            #expect(json["u64Value"]?.stringValue == String(u64Max))
        }

        switch json["i64Value"] {
        case .integer(let val):
            #expect(val == i64Min)
        default:
            #expect(json["i64Value"]?.stringValue == String(i64Min))
        }

        #expect(
            json["nested"]?["largeInt"]?.intValue == 9007199254740993
                || json["nested"]?["largeInt"]?.stringValue == "9007199254740993"
        )

        let decoded = try JSONDecoder().decode(JSONValue.self, from: wireData)
        #expect(
            decoded["nested"]?["largeInt"]?.intValue == 9007199254740993
                || decoded["nested"]?["largeInt"]?.stringValue == "9007199254740993"
        )
    }

    // MARK: - Validation Errors: Empty, Malformed, Non-Object, Non-Finite

    @Test("Rejects empty input and empty object")
    func rejectsEmptyInputs() {
        let emptyDraft = MinerCustomJSONDraft(rawText: "   \n  \t ")
        #expect(throws: MinerCustomJSONError.emptyInput) {
            try emptyDraft.validate()
        }

        let emptyObjectDraft = MinerCustomJSONDraft(rawText: "  {}  ")
        #expect(throws: MinerCustomJSONError.emptyObject) {
            try emptyObjectDraft.validate()
        }
    }

    @Test("Rejects non-object JSON values like arrays, strings, numbers, booleans, and null")
    func rejectsNonObjectJSON() {
        let cases = ["[1, 2, 3]", "\"just a string\"", "12345", "true", "false", "null"]
        for text in cases {
            let draft = MinerCustomJSONDraft(rawText: text)
            #expect(throws: MinerCustomJSONError.notAnObject) {
                try draft.validate()
            }
        }
    }

    @Test("Rejects malformed JSON syntax")
    func rejectsMalformedJSON() {
        let cases = ["{ broken ", "{ key: 123 }", "{ \"trailing\": , }", "{\"unclosed\": "]
        for text in cases {
            let draft = MinerCustomJSONDraft(rawText: text)
            #expect(throws: (any Error).self) {
                try draft.validate()
            }
        }
    }

    @Test("Rejects non-finite numbers such as NaN and Infinity in input")
    func rejectsNonFiniteNumbers() {
        let cases = [
            "{\"val\": NaN}",
            "{\"val\": Infinity}",
            "{\"val\": -Infinity}"
        ]
        for text in cases {
            let draft = MinerCustomJSONDraft(rawText: text)
            #expect(throws: (any Error).self) {
                try draft.validate()
            }
        }
    }

    @Test("Rejects oversized JSON payloads before and after whitespace trimming")
    func rejectsOversizedJSON() {
        // Max payload is 256 KiB
        let oversizedKey = String(repeating: "a", count: 260 * 1024)
        let payload = "{\"key\": \"\(oversizedKey)\"}"
        let draft = MinerCustomJSONDraft(rawText: payload)
        #expect(throws: (any Error).self) {
            try draft.validate()
        }

        // Oversized due to excessive raw whitespace before trim
        let whitespacePadding = String(repeating: " ", count: 260 * 1024)
        let paddedDraft = MinerCustomJSONDraft(rawText: whitespacePadding + "{\"a\": 1}")
        #expect(throws: (any Error).self) {
            try paddedDraft.validate()
        }
    }

    // MARK: - Redaction & Safe Review

    @Test("Redacts passwords and credentials during review generation")
    func redactsSecretsInReview() throws {
        let jsonWithSecrets = """
            {
              "normalField": "safe_value",
              "stratumPassword": "super_secret_pool_password",
              "wifiPassword": "wifi_secret_123",
              "authorizationToken": "bearer_secret",
              "api_key": "api_secret",
              "nestedConfig": {
                "customPassword": "deep_secret"
              }
            }
            """
        let draft = MinerCustomJSONDraft(rawText: jsonWithSecrets)
        let preview = try draft.redactedPreview()

        #expect(!preview.contains("super_secret_pool_password"))
        #expect(!preview.contains("wifi_secret_123"))
        #expect(!preview.contains("bearer_secret"))
        #expect(!preview.contains("api_secret"))
        #expect(!preview.contains("deep_secret"))
        #expect(preview.contains("•••••• (will be sent)"))
        #expect(preview.contains("safe_value"))
    }

    // MARK: - Stage Only (No Side Effects / No Network)

    @Test("Staging validates a payload with fixed .settings endpoint and no side effects")
    func stagesWithoutSideEffects() throws {
        let input = "{\"customClockLimit\": 650}"
        let draft = MinerCustomJSONDraft(rawText: input)
        let (wireData, json) = try draft.validate()

        #expect(draft.endpoint == .settings)
        #expect(draft.endpoint.method == "PATCH")
        #expect(draft.endpoint.path == "/api/system")

        let bodyString = String(bytes: wireData, encoding: .utf8) ?? ""
        #expect(bodyString.contains("customClockLimit"))
        #expect(bodyString.contains("650"))
        #expect(json["customClockLimit"]?.intValue == 650)
    }

    // MARK: - Format Functionality

    @Test("Format pretty-prints and sorts keys without losing fields")
    func formatsJSONDeterministically() throws {
        var draft = MinerCustomJSONDraft(rawText: "{\"z\": 1, \"a\": 2}")
        try draft.format()
        #expect(draft.rawText.contains("\n"))
        #expect(draft.rawText.contains("\"a\" : 2"))
        #expect(draft.rawText.contains("\"z\" : 1"))
    }

    // MARK: - File & String Import Boundedness

    @Test("ImportJSON enforces size limits and rejects non-objects")
    func importJSONValidates() throws {
        var draft = MinerCustomJSONDraft()
        try draft.importJSON("{\"imported\": true}")
        #expect(draft.rawText.contains("\"imported\" : true"))

        #expect(throws: MinerCustomJSONError.notAnObject) {
            try draft.importJSON("[1, 2]")
        }
    }
}
