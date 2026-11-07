import Foundation
import HashFleetCore

enum MinerCustomJSONError: LocalizedError, Equatable {
    case emptyInput
    case oversized(Int)
    case malformedJSON(String)
    case notAnObject
    case emptyObject
    case nonFiniteNumber
    case securityScopedAccessDenied
    case invalidFileType
    case unreadableFile

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "Enter a JSON object. Only the fields you include will be sent."
        case .oversized(let byteCount):
            let maxKiB = MinerCustomJSONDraft.maximumPayloadBytes / 1_024
            return "Payload (\(byteCount) bytes) exceeds the \(maxKiB) KiB limit."
        case .malformedJSON(let details):
            return "Invalid JSON syntax: \(details)"
        case .notAnObject:
            return "Root payload must be a JSON object {...}, not an array, primitive value, or null."
        case .emptyObject:
            return "JSON object must not be empty. Include at least one field to stage."
        case .nonFiniteNumber:
            return "JSON numbers must be finite. NaN, Infinity, and overflowing numbers are not permitted."
        case .securityScopedAccessDenied:
            return "Unable to access the chosen file. Security-scoped resource access was denied."
        case .invalidFileType:
            return "Imported file must be a .json file."
        case .unreadableFile:
            return "Unable to open or read the selected file."
        }
    }
}

/// In-memory model representing a custom-firmware JSON draft.
/// Endpoint is fixed to `.settings` (PATCH /api/system) to prevent arbitrary endpoint payload hazards.
/// Never writes to disk, Keychain, or user defaults without consent, keeping secrets strictly in memory.
/// Preserves arbitrary unknown keys, nested objects, and 64-bit integer precision.
struct MinerCustomJSONDraft: Equatable, Sendable {
    static let maximumPayloadBytes: Int = 256 * 1_024  // 256 KiB bound matching MinerRequestSafety

    var rawText: String
    let endpoint: MinerEndpoint = .settings

    init(rawText: String = "{\n  \n}") {
        self.rawText = rawText
    }

    /// Validates the current rawText and returns the normalized UTF-8 Data and parsed JSONValue.
    /// Does not merge any stock defaults, strip custom fields, or convert integers to floating point.
    func validate() throws -> (data: Data, json: JSONValue) {
        // Bound raw UTF-8 size BEFORE trimming so oversized whitespace cannot bypass memory limits
        let rawUtf8Data = Data(rawText.utf8)
        guard rawUtf8Data.count <= Self.maximumPayloadBytes else {
            throw MinerCustomJSONError.oversized(rawUtf8Data.count)
        }

        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw MinerCustomJSONError.emptyInput
        }

        let utf8Data = Data(trimmed.utf8)

        // Decode once into JSONValue to preserve Int64/UInt64 precision without a second parse.
        let parsedValue: JSONValue
        do {
            parsedValue = try JSONDecoder().decode(JSONValue.self, from: utf8Data)
        } catch {
            throw MinerCustomJSONError.malformedJSON(error.localizedDescription)
        }

        guard case .object(let parsedDict) = parsedValue else { throw MinerCustomJSONError.notAnObject }
        guard !parsedDict.isEmpty else { throw MinerCustomJSONError.emptyObject }
        guard Self.allNumbersAreFinite(parsedValue) else { throw MinerCustomJSONError.nonFiniteNumber }

        // Re-serialize with sortedKeys to produce deterministic wire data while strictly preserving custom keys.
        // Fails closed if encoding fails.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let wireData: Data
        do {
            wireData = try encoder.encode(parsedValue)
        } catch {
            throw MinerCustomJSONError.malformedJSON("Encoding failed: \(error.localizedDescription)")
        }

        return (wireData, parsedValue)
    }

    /// Formats the rawText with pretty-printed indentation and sorted keys, preserving all fields.
    mutating func format() throws {
        let (_, parsedValue) = try validate()
        rawText = try parsedValue.prettyPrinted()
    }

    /// Generates a redacted preview representation of the payload for safe UI review.
    /// Replaces sensitive keys such as passwords or wifi credentials with redacted tokens.
    func redactedPreview() throws -> String {
        let (data, _) = try validate()
        return JSONRedactor.prettyString(from: data)
    }

    /// Accepts imported JSON string (e.g. from clipboard or file), validates non-empty object shape,
    /// and replaces current text.
    mutating func importJSON(_ text: String) throws {
        let rawBytes = Data(text.utf8)
        guard rawBytes.count <= Self.maximumPayloadBytes else {
            throw MinerCustomJSONError.oversized(rawBytes.count)
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MinerCustomJSONError.emptyInput }
        let tempDraft = MinerCustomJSONDraft(rawText: trimmed)
        let (_, parsedValue) = try tempDraft.validate()
        rawText = try parsedValue.prettyPrinted()
    }

    /// Reads data from a security-scoped URL using bounded chunk reading to prevent TOCTOU/unbounded memory,
    /// validates size and format, and replaces draft text.
    mutating func importFromFile(url: URL) throws {
        guard url.pathExtension.lowercased() == "json" else {
            throw MinerCustomJSONError.invalidFileType
        }

        let isAccessGranted = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessGranted {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        if let isRegular = values?.isRegularFile, !isRegular {
            throw MinerCustomJSONError.invalidFileType
        }
        if let size = values?.fileSize, size > Self.maximumPayloadBytes {
            throw MinerCustomJSONError.oversized(size)
        }

        guard let handle = try? FileHandle(forReadingFrom: url) else {
            throw MinerCustomJSONError.unreadableFile
        }
        defer { try? handle.close() }

        let maxRead = Self.maximumPayloadBytes + 1
        guard let readData = try? handle.read(upToCount: maxRead), !readData.isEmpty else {
            throw MinerCustomJSONError.emptyInput
        }

        if readData.count > Self.maximumPayloadBytes {
            throw MinerCustomJSONError.oversized(readData.count)
        }

        guard let stringContent = String(bytes: readData, encoding: .utf8) else {
            throw MinerCustomJSONError.malformedJSON("File content is not valid UTF-8 text.")
        }

        try importJSON(stringContent)
    }

    // MARK: - Private Helpers

    private static func allNumbersAreFinite(_ value: JSONValue) -> Bool {
        switch value {
        case .object(let object): object.values.allSatisfy(allNumbersAreFinite)
        case .array(let array): array.allSatisfy(allNumbersAreFinite)
        case .number(let number): number.isFinite
        case .string, .integer, .unsignedInteger, .bool, .null: true
        }
    }
}
