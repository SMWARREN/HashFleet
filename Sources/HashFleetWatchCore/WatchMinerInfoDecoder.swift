import Foundation

/// Decodes AxeOS-style `/api/system/info`, ThorOS `/v2/miner/status`, and cgminer summary JSON into a reading.
/// Only the fields below are read, so pool, Wi-Fi and other private fields never enter the model.
enum WatchMinerInfoDecoder {
    private struct Payload: Decodable {
        let hashRate: Double?
        let power: Double?
        let temp: Double?
        let temp2: Double?
        let vrTemp: Double?
        let uptimeSeconds: Double?
        let sharesAccepted: Int?
        let sharesRejected: Int?
        let miningPaused: Bool?

        enum CodingKeys: String, CodingKey {
            case hashRate, hashrate
            case hashrateGhs = "hashrate_ghs"
            case power
            case devicePowerW = "device_power_w"
            case asicRailPowerW = "asic_rail_power_w"
            case temp, temp2, chiptemp1, chiptemp2
            case asicTempC = "asic_temp_c"
            case vrTemp
            case vrTempC = "vr_temp_c"
            case uptimeSeconds
            case uptimeSecondsSnake = "uptime_seconds"
            case sharesAccepted
            case sharesAcceptedSnake = "shares_accepted"
            case sAccepted
            case sharesRejected
            case sharesRejectedSnake = "shares_rejected"
            case sRejected
            case miningPaused
            case asicPaused = "asic_paused"
            case paused, shutdown
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            // A field with the wrong type (string, boolean, ...) is "not reported", not zero.
            func number(_ key: CodingKeys) -> Double? { (try? c.decodeIfPresent(Double.self, forKey: key)) ?? nil }
            func integer(_ key: CodingKeys) -> Int? { (try? c.decodeIfPresent(Int.self, forKey: key)) ?? nil }
            hashRate = number(.hashRate) ?? number(.hashrate) ?? number(.hashrateGhs)
            power = number(.power) ?? number(.devicePowerW) ?? number(.asicRailPowerW)
            temp = number(.temp) ?? number(.chiptemp1) ?? number(.asicTempC)
            temp2 = number(.temp2) ?? number(.chiptemp2)
            vrTemp = number(.vrTemp) ?? number(.vrTempC)
            uptimeSeconds = number(.uptimeSeconds) ?? number(.uptimeSecondsSnake)
            sharesAccepted = integer(.sharesAccepted) ?? integer(.sharesAcceptedSnake) ?? integer(.sAccepted)
            sharesRejected = integer(.sharesRejected) ?? integer(.sharesRejectedSnake) ?? integer(.sRejected)
            if let flag = (try? c.decodeIfPresent(Bool.self, forKey: .miningPaused))
                ?? (try? c.decodeIfPresent(Bool.self, forKey: .asicPaused))
                ?? (try? c.decodeIfPresent(Bool.self, forKey: .paused))
                ?? (try? c.decodeIfPresent(Bool.self, forKey: .shutdown)) {
                miningPaused = flag
            } else if let value = integer(.miningPaused) ?? integer(.asicPaused) ?? integer(.paused) ?? integer(.shutdown),
                      value == 0 || value == 1 {
                miningPaused = value == 1
            } else {
                miningPaused = nil
            }
        }
    }

    /// Hammer ThorOS `/v2/miner/status`: hashrate in H/s, optionally wrapped as `{"ok":..,"data":{..}}`.
    private struct ThorOSPayload: Decodable {
        let currentHashrate: Double
        let power: Double?
        let temp: Double?
        let temp2: Double?
        let vrTemp: Double?
        let accepted: Int?
        let rejected: Int?

        enum CodingKeys: String, CodingKey {
            case data
            case currentHashrate = "current_hashrate"
            case power = "power_consumption"
            case temp = "temp_board"
            case temp2 = "temp_board_1"
            case vrTemp = "temp_vcore"
            case accepted = "shares_accepted"
            case rejected = "shares_rejected"
        }

        init(from decoder: any Decoder) throws {
            let outer = try decoder.container(keyedBy: CodingKeys.self)
            let c = (try? outer.nestedContainer(keyedBy: CodingKeys.self, forKey: .data)) ?? outer
            func number(_ key: CodingKeys) -> Double? { (try? c.decodeIfPresent(Double.self, forKey: key)) ?? nil }
            func integer(_ key: CodingKeys) -> Int? { (try? c.decodeIfPresent(Int.self, forKey: key)) ?? nil }
            currentHashrate = try c.decode(Double.self, forKey: .currentHashrate)
            guard c.contains(.power) else {
                throw DecodingError.keyNotFound(CodingKeys.power, .init(codingPath: [], debugDescription: "not ThorOS"))
            }
            power = number(.power)
            temp = number(.temp)
            temp2 = number(.temp2)
            vrTemp = number(.vrTemp)
            accepted = integer(.accepted)
            rejected = integer(.rejected)
        }
    }

    static func reading(from data: Data, minerID: UUID, observedAt: Date) throws -> WatchMinerReading {
        if let thor = try? JSONDecoder().decode(ThorOSPayload.self, from: data) {
            return WatchMinerReading(
                minerID: minerID,
                observedAt: observedAt,
                hashrateGHs: thor.currentHashrate / 1e9,
                powerWatts: thor.power,
                chipTemperatureC: [thor.temp, thor.temp2].compactMap(validTemperature).max(),
                vrTemperatureC: validTemperature(thor.vrTemp),
                uptimeSeconds: nil,
                acceptedShares: thor.accepted,
                rejectedShares: thor.rejected,
                isMiningPaused: nil
            )
        }
        if let payload = try? JSONDecoder().decode(Payload.self, from: data) {
            let temperatures = [payload.temp, payload.temp2].compactMap(validTemperature)
            let reading = WatchMinerReading(
                minerID: minerID,
                observedAt: observedAt,
                hashrateGHs: payload.hashRate,
                powerWatts: payload.power,
                chipTemperatureC: temperatures.max(),
                vrTemperatureC: validTemperature(payload.vrTemp),
                uptimeSeconds: payload.uptimeSeconds,
                acceptedShares: payload.sharesAccepted,
                rejectedShares: payload.sharesRejected,
                isMiningPaused: payload.miningPaused
            )
            // A page that parses as JSON but has none of the expected metrics is not a miner reading.
            let hasMetric = reading.hashrateGHs != nil || reading.powerWatts != nil
                || reading.chipTemperatureC != nil || reading.vrTemperatureC != nil
                || reading.uptimeSeconds != nil || reading.acceptedShares != nil
                || reading.rejectedShares != nil || reading.isMiningPaused != nil
            if hasMetric { return reading }
        }

        if let cgminer = try? JSONDecoder().decode(WatchCgminerSummaryPayload.self, from: data),
           let item = cgminer.summary?.first {
            let mhs = item.mhs5m ?? item.mhs1m ?? item.mhsAv ?? item.mhs5s
            let ghs = mhs.map { $0 / 1000.0 }
            let reading = WatchMinerReading(
                minerID: minerID,
                observedAt: observedAt,
                hashrateGHs: ghs,
                powerWatts: nil,
                chipTemperatureC: nil,
                vrTemperatureC: nil,
                uptimeSeconds: item.elapsed,
                acceptedShares: item.accepted,
                rejectedShares: item.rejected,
                isMiningPaused: nil
            )
            return reading
        }

        throw WatchMinerFetchError.invalidResponse
    }

    /// Negative values and zero are sentinels for "no sensor", and absurdly large values are bad data.
    private static func validTemperature(_ value: Double?) -> Double? {
        WatchMinerReading.temperature(value)
    }
}
