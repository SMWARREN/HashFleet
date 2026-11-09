import Foundation
import Testing
import HashFleetCore

struct AddressTests {
    struct ValidAddress: Sendable {
        let input: String
        let scheme: String
        let host: String
        let port: Int?
    }

    @Test(arguments: [
        ValidAddress(input: "192.168.1.42", scheme: "http", host: "192.168.1.42", port: nil),
        ValidAddress(input: "bitaxe.local", scheme: "http", host: "bitaxe.local", port: nil),
        ValidAddress(input: "miner-01", scheme: "http", host: "miner-01", port: nil),
        ValidAddress(input: "bitaxe.local:8080", scheme: "http", host: "bitaxe.local", port: 8080),
        ValidAddress(input: "http://192.168.1.42:80", scheme: "http", host: "192.168.1.42", port: nil),
        ValidAddress(input: "https://miner.example:443", scheme: "https", host: "miner.example", port: nil),
        ValidAddress(input: "[2001:db8::42]", scheme: "http", host: "[2001:db8::42]", port: nil),
        ValidAddress(input: "http://[::1]:8080", scheme: "http", host: "[::1]", port: 8080),
        ValidAddress(input: "https://[2001:db8::1]:65535", scheme: "https", host: "[2001:db8::1]", port: 65535),
        ValidAddress(input: "miner.local:1", scheme: "http", host: "miner.local", port: 1),
        ValidAddress(input: "  http://miner.local/ \n", scheme: "http", host: "miner.local", port: nil),
        ValidAddress(input: "miner.local.", scheme: "http", host: "miner.local.", port: nil),
        ValidAddress(input: "[::ffff:192.168.1.42]", scheme: "http", host: "[::ffff:192.168.1.42]", port: nil),
        ValidAddress(input: "[2001:db8:1:2:3:4:5:6]", scheme: "http", host: "[2001:db8:1:2:3:4:5:6]", port: nil)
    ])
    func acceptsHostAndPortOnly(example: ValidAddress) throws {
        let url = try MinerDevice(name: "Desk", address: example.input).validatedURL()
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.scheme == example.scheme)
        #expect(components.host == example.host)
        #expect(components.port == example.port)
        #expect(components.user == nil)
        #expect(components.password == nil)
        #expect(components.query == nil)
        #expect(components.fragment == nil)
    }

    @Test(arguments: [
        "", "   ", "http://", "https://", "ftp://miner.local", "file:///etc/passwd",
        "ws://miner.local", "http://user@miner.local", "http://user:secret@miner.local",
        "user:secret@miner.local", "http://@miner.local", "http://miner.local/api/system/info",
        "miner.local/settings", "http://miner.local?x=1", "miner.local?", "miner.local#fragment",
        "http://miner.local#", "miner.local:0", "miner.local:65536", "miner.local:-1",
        "miner.local:notaport", "http://bad host.local", "http://miner.local\n.evil",
        "http://miner.local\\evil", "http://[not-ipv6]", "http://[2001:db8::zz]",
        "999.168.1.1", "192.168.1.999", "-miner.local", "miner-.local", "miner..local",
        "miner.local:", "http://miner.local:/", "192.168.1", "192.168.001.1", "127.1",
        "http://miner.local//", "http://miner.local/%2f", "http://miner%2elocal",
        "http://miner.local\u{0000}", "http://[1:2:3:4:5:6:7]", "http://[1:2:3:4:5:6:7:8:9]",
        "http://[1::2::3]", "http://[:::1]", "http://[192.168.1.1::]", "2001:db8::1",
        "http://[fe80::1%25en0]", String(repeating: "a", count: 64) + ".local"
    ])
    func rejectsUnsafeOrMalformedAddresses(address: String) {
        #expect(throws: MinerAPIError.self) {
            try MinerDevice(name: "Invalid", address: address).validatedURL()
        }
    }

    @Test func deviceIdentitySurvivesCodableRoundTrip() throws {
        let device = MinerDevice(name: "Workshop", address: "bitaxe.local:8080", kind: .espMiner)
        let decoded = try JSONDecoder().decode(MinerDevice.self, from: JSONEncoder().encode(device))
        #expect(decoded == device)
        #expect(decoded.id == device.id)
    }

    @Test func deviceLegacyDecodingDefaultsToESPMiner() throws {
        let legacyJSON = Data("""
        {
            "id": "123E4567-E89B-12D3-A456-426614174000",
            "name": "Legacy",
            "address": "192.168.1.100"
        }
        """.utf8)
        let decoded = try JSONDecoder().decode(MinerDevice.self, from: legacyJSON)
        #expect(decoded.name == "Legacy")
        #expect(decoded.address == "192.168.1.100")
        #expect(decoded.kind == .espMiner)
        #expect(decoded.keychainCredentialReference == nil)
    }

    @Test(arguments: [
        ["miner.local", "http://MINER.local:80", " HTTP://miner.LOCAL/ "],
        ["https://miner.local", "HTTPS://MINER.LOCAL:443", "https://miner.local/"],
        ["[2001:db8::ab]", "http://[2001:DB8::AB]:80", "http://[2001:db8::ab]/"]
    ])
    func equivalentHostSpellingsHaveOneCanonicalURL(addresses: [String]) throws {
        let urls = try addresses.map { try MinerDevice(name: "Duplicate", address: $0).validatedURL() }
        #expect(Set(urls).count == 1)
    }

    @Test func nonDefaultPortsAndTLSRemainDistinct() throws {
        let urls = try ["miner.local", "miner.local:8080", "https://miner.local", "https://miner.local:80"]
            .map { try MinerDevice(name: "Separate", address: $0).validatedURL() }
        #expect(Set(urls).count == 4)
    }
}

struct MinerInfoTests {
    @Test func decodesMixedFirmwareTypesAndPreservesUnknownFields() throws {
        let json = #"{"hashRate":"1200.25","power":18.5,"temp":null,"vrTemp":"54.2","fanspeed":"65","# +
                   #""fanrpm":4500,"voltage":"5000","frequency":600,"coreVoltage":"1200","wifiRSSI":"-62","# +
                   #""sharesAccepted":"123","sharesRejected":4,"uptimeSeconds":"3600","hostname":"workshop","# +
                   #""version":"v2.13.1","ASICModel":"BM1370","bestDiff":123456,"stratumURL":"pool.example","# +
                   #""future":{"enabled":true,"items":[1,null,"x"]}}"#
        let data = Data(json.utf8)
        let info = try JSONDecoder().decode(MinerInfo.self, from: data)
        #expect(info.hashRate == 1200.25)
        #expect(info.power == 18.5)
        #expect(info.temp == 0)
        #expect(info.vrTemp == 54.2)
        #expect(info.fanSpeed == 65)
        #expect(info.fanRpm == 4500)
        #expect(info.voltage == 5000)
        #expect(info.frequency == 600)
        #expect(info.coreVoltage == 1200)
        #expect(info.wifiRSSI == -62)
        #expect(info.sharesAccepted == 123)
        #expect(info.sharesRejected == 4)
        #expect(info.uptimeSeconds == 3600)
        #expect(info.hostname == "workshop")
        #expect(info.version == "v2.13.1")
        #expect(info.asicModel == "BM1370")
        #expect(Double(info.bestDiff) == 123456)
        #expect(info.poolURL == "pool.example")
        #expect(info.value(for: "temp") == .null)
        #expect(info.value(for: "missing") == nil)
        let roundTrip = try JSONDecoder().decode(MinerInfo.self, from: JSONEncoder().encode(info))
        #expect(roundTrip == info)
        #expect(roundTrip.raw["future"]?.objectValue?["enabled"]?.boolValue == true)
        let encoded = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(info))
        #expect(encoded.objectValue?["raw"] == nil, "Firmware objects must not acquire a raw wrapper")
    }

    @Test func missingFieldsHaveDisplayDefaultsWithoutFabricatingRawValues() throws {
        let info = try JSONDecoder().decode(MinerInfo.self, from: Data("{}".utf8))
        #expect([info.hashRate, info.power, info.temp, info.vrTemp, info.fanSpeed, info.fanRpm,
                 info.voltage, info.frequency, info.coreVoltage, info.wifiRSSI].allSatisfy { $0 == 0 })
        #expect([info.sharesAccepted, info.sharesRejected, info.uptimeSeconds].allSatisfy { $0 == 0 })
        #expect([info.hostname, info.version, info.asicModel, info.bestDiff, info.poolURL].allSatisfy { $0.isEmpty })
        #expect(info.raw.isEmpty)
        #expect(info.value(for: "hashRate") == nil)
        #expect(MinerInfo(raw: ["hashRate": .number(0)]).value(for: "hashRate") == .number(0))
    }

    @Test(arguments: [JSONValue.null, .string("unavailable"), .object([:]), .array([])])
    func malformedNumericFieldsDoNotBreakTheWholeSnapshot(value: JSONValue) {
        let info = MinerInfo(raw: ["hashRate": value, "sharesAccepted": value])
        #expect(info.hashRate == 0)
        #expect(info.sharesAccepted == 0)
        #expect(info.value(for: "hashRate") == value)
    }

    @Test func stringDifficultyRemainsHumanReadable() {
        let info = MinerInfo(raw: ["bestDiff": .string("1.25G"), "hostname": .null, "version": .number(213)])
        #expect(info.bestDiff == "1.25G")
        #expect(info.hostname == "")
        #expect(Double(info.version) == 213)
    }

    @Test(arguments: ["[]", "null", "42", "\"not an object\""])
    func nonObjectInfoIsRejected(json: String) {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(MinerInfo.self, from: Data(json.utf8))
        }
    }
}

struct JSONValueTests {
    @Test(arguments: [JSONValue.number(.infinity), .number(-.infinity), .number(.nan),
                       .string("NaN"), .string("Infinity"), .string("1e999"),
                       .unsignedInteger(UInt64.max)])
    func numericFacadeNeverTrapsOnNonfiniteOrOverflowingIntegers(value: JSONValue) {
        #expect(value.intValue == nil)
        #expect(MinerInfo(raw: ["sharesAccepted": value]).sharesAccepted == 0)
        if case .unsignedInteger = value {
            #expect(value.doubleValue?.isFinite == true)
        } else {
            #expect(value.doubleValue == nil)
            #expect(MinerInfo(raw: ["power": value]).power == 0)
        }
    }

    @Test func arbitraryJSONRoundTrips() throws {
        let jsonStr = #"{"nested":[null,true,false,1,2.5,"hello"],"empty":{},"large":9007199254740993,"# +
                      #""unsigned":18446744073709551615}"#
        let json = Data(jsonStr.utf8)
        let value = try JSONDecoder().decode(JSONValue.self, from: json)
        let encoded = try JSONEncoder().encode(value)
        #expect(try JSONDecoder().decode(JSONValue.self, from: encoded) == value)
        let text = try #require(String(bytes: encoded, encoding: .utf8))
        #expect(text.contains("9007199254740993"),
                "Integer precision must survive beyond Double's exact range")
        #expect(text.contains("18446744073709551615"))
        #expect(try JSONDecoder().decode(JSONValue.self, from: Data(value.prettyPrinted().utf8)) == value)
        #expect(value.objectValue?["nested"]?.arrayValue?.count == 6)
        #expect(JSONValue.string("42.5").doubleValue == 42.5)
        #expect(JSONValue.string("42").intValue == 42)
        #expect(JSONValue.null.doubleValue == nil)
        #expect(JSONValue.object([:]).stringValue == nil)
    }

    @Test func liveDiffMergesObjectsWithoutErasingSiblings() {
        let complete = JSONValue.object([
            "hashRate": .number(1_200),
            "power": .number(19),
            "pools": .object([
                "primary": .string("pool.example"),
                "worker": .string("rig-1")
            ])
        ])
        let diff = JSONValue.object([
            "hashRate": .number(1_250),
            "pools": .object(["worker": .string("rig-2")])
        ])

        let merged = complete.merging(diff)
        #expect(merged["hashRate"]?.doubleValue == 1_250)
        #expect(merged["power"]?.doubleValue == 19)
        #expect(merged["pools"]?["primary"]?.stringValue == "pool.example")
        #expect(merged["pools"]?["worker"]?.stringValue == "rig-2")
    }
}
