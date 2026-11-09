import Foundation
import HashFleetCore

/// PUT /api/system/pools/{slot} is a full replacement in audited master, not a partial update.
/// Omitted advanced fields receive firmware defaults. Never infer preservation from stale telemetry.
struct MinerTuningPoolDraft: Equatable, Sendable {
    var slot: Int
    var server: String
    var port: String
    var user: String
    var stratumProtocol: String
    var replacePassword: Bool
    var password: String

    static let replacementNotice =
        "FULL SLOT REPLACEMENT: this PUT replaces the"
        + " entire pool slot. Advanced fields omitted from"
        + " this JSON, including TLS/certificate, difficulty,"
        + " extranonce, coinbase and SV2 authority/channel"
        + " settings, revert to firmware defaults. Review"
        + " and add every required field before APPLY."
        + " The password value ***** asks current firmware"
        + " to preserve an existing slot password; for an"
        + " empty slot firmware uses its default x."

    func payload(replacementAcknowledged: Bool) throws -> JSONValue {
        guard replacementAcknowledged else {
            throw MinerTuningError.invalidInput(
                "Acknowledge full-slot replacement and omitted-field"
                    + " resets before reviewing a pool slot write."
            )
        }
        guard (0...7).contains(slot) else {
            throw MinerTuningError.invalidInput("Choose a pool slot from 0 through 7.")
        }
        let normalizedServer = server.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedServer.isEmpty,
            normalizedServer.utf8.count <= 255,
            !user.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            user.utf8.count <= 255,
            ["SV1", "SV2"].contains(stratumProtocol)
        else {
            throw MinerTuningError.invalidInput(
                "Enter a server and worker of at most"
                    + " 255 UTF-8 bytes and choose SV1 or SV2."
            )
        }
        let portNumber = try MinerTuningDraft.integer(port, name: "Pool port", bounds: 1...65_535)
        if replacePassword {
            guard password != "*****", password.utf8.count <= 255 else {
                throw MinerTuningError.invalidInput(
                    "A replacement password must be at most"
                        + " 255 UTF-8 bytes. ***** is reserved by"
                        + " firmware for retaining the current"
                        + " password, not a new password."
                )
            }
        }
        return .object([
            "stratumURL": .string(normalizedServer),
            "stratumPort": .integer(Int64(portNumber)),
            "stratumUser": .string(user),
            "stratumProtocol": .string(stratumProtocol),
            // Never copy a real password from a telemetry snapshot or omit it silently.
            "stratumPassword": .string(replacePassword ? password : "*****")
        ])
    }
}
