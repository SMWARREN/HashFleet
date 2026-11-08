import Foundation
import Testing
import HashFleetCore
@testable import HashFleet

/// Unit and integration tests for `FleetNotificationInboxEncoder`.
///
/// Verifies:
/// 1. Real `JSONEncoder` / `JSONDecoder` serialization and round-trip decoding across all 6 event types:
///    - `.bestShare` (with Unicode names, special characters, and sub-second ISO8601/Date representation)
///    - `.blockFound`
///    - `.temperature`
///    - `.power`
///    - `.stateChange` (including `.offline` and `.backOnline`)
///    - `.metricAlert`
/// 2. Canonical JSON equivalence:
///    - Asserts differential semantic equivalence against `JSONSerialization` sorted-key representation.
/// 3. Cache hit & granular invalidation:
///    - Encoding an identical array of entries performs 0 entry re-encodes.
///    - Mutating exactly one flag (`systemDelivered`, `inAppDelivered`, or `inAppAcceptancePending`) re-encodes exactly 1 entry.
/// 4. Order retention, sliding rolls, and duplicate IDs:
///    - Reordering entries changes the assembled output order while reusing cached chunk data.
///    - More than 100 entries gracefully bound cache capacity without dropping or altering output.
///    - Removal/roll cache eviction cleans up unreferenced entries, asserting exact cached count (e.g. exactly 80 on an 80-entry subset).
///    - Duplicate UUIDs with different payloads or flags are preserved and not deduped or dropped.
/// 5. Real JSONEncoder non-finite failure handling:
///    - Real non-finite floating point numbers (`Double.nan`, `Double.infinity`) cause standard `JSONEncoder` to throw.
///    - Verifies that default JSONEncoder throwing on real non-finite event values is retried twice with counter, and existing prior cache is preserved.
/// 6. Exact 512 KiB inclusive boundary and +1 overflow:
///    - Dynamically measures baseline JSON overhead and constructs exact 524,288 byte whole-array JSON (inclusive boundary).
///    - Adding exactly 1 byte (524,289 bytes) asserts throwing without corrupting encoder.
///    - Evaluates 2-entry comma-delimited boundary.
///    - Passing an empty array clears the cache.
/// 7. Multi-Store persistence, setter counts, and last-writer-wins fidelity:
///    - Uses an isolated `UserDefaults` write-count tracking subclass.
///    - Tests repeated `storeA.persistNotificationInbox()` calls to verify setter counts.
///    - Verifies `storeB` updates a flag, `storeA` writes its cached full journal, and verifies existing last-writer-wins behavior.
@Suite("FleetNotificationInboxEncoder Tests", .serialized)
@MainActor
struct FleetNotificationInboxEncodingTests {

    // MARK: - Write Counting UserDefaults Subclass

    /// UserDefaults is thread-safe. The only added mutable state is protected by this lock;
    /// no actor-isolated state or unprotected references escape through the test double.
    private final class TrackingUserDefaults: UserDefaults {
        private let counterLock = NSLock()
        private var counts: [String: Int] = [:]
        var setCallsByKey: [String: Int] {
            counterLock.lock()
            defer { counterLock.unlock() }
            return counts
        }

        override func set(_ value: Any?, forKey defaultName: String) {
            counterLock.lock()
            counts[defaultName, default: 0] += 1
            counterLock.unlock()
            super.set(value, forKey: defaultName)
        }
    }

    // MARK: - Test Helpers & Event Constructors

    private static func makeDeviceID() -> UUID { UUID() }

    private static func makeAllSixEvents(baseDate: Date = Date(timeIntervalSince1970: 1700000000.125)) -> [FleetNotificationEvent] {
        let devID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let unicodeName = "Miner ⛏️ \u{1F525} \\\"Workshop\\\" \n\t «Beta»"

        let bestShare = FleetNotificationEvent.bestShare(MinerBestShareEvent(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            deviceID: devID,
            minerName: unicodeName,
            kind: .allTime,
            displayValue: "4.50 GH/s",
            rawValue: "4500000000",
            occurredAt: baseDate
        ))

        let blockFound = FleetNotificationEvent.blockFound(MinerBlockFoundEvent(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            deviceID: devID,
            minerName: unicodeName,
            coinLabel: "BTC",
            height: 900_123,
            count: 1,
            occurredAt: baseDate.addingTimeInterval(10.375)
        ))

        let temperature = FleetNotificationEvent.temperature(MinerTemperatureAlertEvent(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            deviceID: devID,
            minerName: unicodeName,
            temperatureCelsius: 78.5,
            thresholdCelsius: 75.0,
            occurredAt: baseDate.addingTimeInterval(20.5)
        ))

        let power = FleetNotificationEvent.power(MinerPowerAlertEvent(
            id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            deviceID: devID,
            minerName: unicodeName,
            kind: .exceeded,
            watts: 18.2,
            thresholdWatts: 15.0,
            occurredAt: baseDate.addingTimeInterval(30.625)
        ))

        let stateChange = FleetNotificationEvent.stateChange(MinerStateChangeEvent(
            id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
            deviceID: devID,
            minerName: unicodeName,
            kind: .backOnline,
            detail: "Socket connection resumed",
            occurredAt: baseDate.addingTimeInterval(40.875)
        ))

        let metricAlert = FleetNotificationEvent.metricAlert(MinerMetricAlertEvent(
            id: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
            deviceID: devID,
            minerName: unicodeName,
            kind: .hashrateDrop,
            title: "Hashrate dropped",
            detail: "Rate fell 30% below 5-minute rolling average",
            occurredAt: baseDate.addingTimeInterval(50.25)
        ))

        return [bestShare, blockFound, temperature, power, stateChange, metricAlert]
    }

    private static func makeEntries(events: [FleetNotificationEvent]) -> [FleetNotificationInboxEntry] {
        events.enumerated().map { index, event in
            FleetNotificationInboxEntry(
                event: event,
                systemDelivered: index.isMultiple(of: 2),
                inAppDelivered: index.isMultiple(of: 3),
                inAppAcceptancePending: index == 1 ? true : nil
            )
        }
    }

    // MARK: - Test 1: Full Round-Trip Decoding & Canonical JSON Equivalence

    @Test
    func allSixEventTypesSerializeAndRoundTripDecodeAccuratelyWithFractionalDates() throws {
        var encoder = FleetNotificationInboxEncoder()
        let events = Self.makeAllSixEvents()
        let entries = Self.makeEntries(events: events)

        let encodedData = try encoder.encode(entries)
        #expect(encodedData.count > 0)
        #expect(encodedData.count <= 512 * 1024)

        // Decode using standard JSONDecoder to verify exact schema compatibility
        let decoded = try JSONDecoder().decode([FleetNotificationInboxEntry].self, from: encodedData)
        #expect(decoded.count == 6)
        #expect(decoded == entries)

        // Differential canonical equivalence against whole-array JSONEncoder
        let directData = try JSONEncoder().encode(entries)
        let canonicalFromEncoder = try JSONSerialization.jsonObject(with: encodedData)
        let canonicalFromDirect = try JSONSerialization.jsonObject(with: directData)
        #expect((canonicalFromEncoder as? NSArray) == (canonicalFromDirect as? NSArray))

        // Verify read-only metrics
        #expect(encoder.cachedEntryCount == 6)
        #expect(encoder.cachedByteCount > 0)
        #expect(encoder.cachedByteCount <= 512 * 1024)
    }

    // MARK: - Test 2: Repeated Array Encodes 0 Entries (Full Cache Hit)

    @Test
    func repeatedArrayEncodingPerformsZeroEntryEncodes() throws {
        var encoder = FleetNotificationInboxEncoder()
        let entries = Self.makeEntries(events: Self.makeAllSixEvents())

        var encodeCallCount = 0
        let countingEncode: () -> Void = {
            encodeCallCount += 1
        }

        // First pass: cold cache, must encode all 6 entries
        let firstData = try encoder.encode(entries, willEncodeEntry: countingEncode)
        #expect(encodeCallCount == 6)
        #expect(encoder.cachedEntryCount == 6)

        // Second pass: identical array, must perform 0 entry re-encodes
        let secondData = try encoder.encode(entries, willEncodeEntry: countingEncode)
        #expect(encodeCallCount == 6, "Expected zero re-encodes on identical array")
        #expect(firstData == secondData)
        #expect(encoder.cachedEntryCount == 6)
    }

    // MARK: - Test 3: Mutating Exactly One Flag Re-Encodes Exactly One Entry

    @Test
    func mutatingOneFlagReencodesOnlyTheModifiedEntry() throws {
        var encoder = FleetNotificationInboxEncoder()
        var entries = Self.makeEntries(events: Self.makeAllSixEvents())

        var encodeCallCount = 0
        let countingEncode: () -> Void = {
            encodeCallCount += 1
        }

        _ = try encoder.encode(entries, willEncodeEntry: countingEncode)
        #expect(encodeCallCount == 6)

        // Mutate only entry[2].systemDelivered
        entries[2].systemDelivered.toggle()

        let modifiedData = try encoder.encode(entries, willEncodeEntry: countingEncode)
        #expect(encodeCallCount == 7, "Expected exactly 1 re-encode for single flag change")

        let decoded = try JSONDecoder().decode([FleetNotificationInboxEntry].self, from: modifiedData)
        #expect(decoded == entries)
        #expect(decoded[2].systemDelivered == entries[2].systemDelivered)

        // Mutate only entry[3].inAppDelivered
        entries[3].inAppDelivered.toggle()
        _ = try encoder.encode(entries, willEncodeEntry: countingEncode)
        #expect(encodeCallCount == 8, "Expected exactly 1 re-encode for inAppDelivered change")
    }

    // MARK: - Test 4: Mutating inAppAcceptancePending Flag Invalidation

    @Test
    func mutatingInAppAcceptancePendingReencodesOnlyThatEntry() throws {
        var encoder = FleetNotificationInboxEncoder()
        var entries = Self.makeEntries(events: Self.makeAllSixEvents())

        var encodeCallCount = 0
        let countingEncode: () -> Void = {
            encodeCallCount += 1
        }

        _ = try encoder.encode(entries, willEncodeEntry: countingEncode)
        #expect(encodeCallCount == 6)

        // Transition from nil -> true
        entries[0].inAppAcceptancePending = true
        _ = try encoder.encode(entries, willEncodeEntry: countingEncode)
        #expect(encodeCallCount == 7)

        // Transition from true -> nil
        entries[0].inAppAcceptancePending = nil
        _ = try encoder.encode(entries, willEncodeEntry: countingEncode)
        #expect(encodeCallCount == 8)
    }

    // MARK: - Test 5: Reordering and Sliding Retention Window

    @Test
    func reorderingPreservesOrderAndReusesCachedEntryPayloads() throws {
        var encoder = FleetNotificationInboxEncoder()
        let entries = Self.makeEntries(events: Self.makeAllSixEvents())

        var encodeCallCount = 0
        let countingEncode: () -> Void = {
            encodeCallCount += 1
        }

        _ = try encoder.encode(entries, willEncodeEntry: countingEncode)
        #expect(encodeCallCount == 6)

        // Reverse the array order: all entries exist in cache, so 0 entry re-encodes occur
        let reversedEntries = Array(entries.reversed())
        let reversedData = try encoder.encode(reversedEntries, willEncodeEntry: countingEncode)
        #expect(encodeCallCount == 6, "Reordering cached entries must not trigger re-encoding")

        let decoded = try JSONDecoder().decode([FleetNotificationInboxEntry].self, from: reversedData)
        #expect(decoded == reversedEntries)
        #expect(decoded.first?.id == entries.last?.id)
        #expect(decoded.last?.id == entries.first?.id)
    }

    // MARK: - Test 6: Duplicate UUIDs with Different Payloads or Flags Preserved

    @Test
    func duplicateUUIDsWithDifferentPayloadsAreBothPreservedAndNotDeduped() throws {
        var encoder = FleetNotificationInboxEncoder()
        let sharedID = UUID()
        let devID = UUID()
        let t0 = Date(timeIntervalSince1970: 1700000000)

        // Two distinct events intentionally constructed with the same UUID (e.g. diagnostic collision)
        let eventA = FleetNotificationEvent.stateChange(MinerStateChangeEvent(
            id: sharedID, deviceID: devID, minerName: "Miner", kind: .offline, detail: "Detail A", occurredAt: t0
        ))
        let eventB = FleetNotificationEvent.stateChange(MinerStateChangeEvent(
            id: sharedID, deviceID: devID, minerName: "Miner", kind: .backOnline, detail: "Detail B", occurredAt: t0.addingTimeInterval(5)
        ))

        let entryA = FleetNotificationInboxEntry(event: eventA, systemDelivered: false, inAppDelivered: false)
        let entryB = FleetNotificationInboxEntry(event: eventB, systemDelivered: true, inAppDelivered: false)

        let entries = [entryA, entryB]
        let data = try encoder.encode(entries)

        let decoded = try JSONDecoder().decode([FleetNotificationInboxEntry].self, from: data)
        #expect(decoded == entries)
        #expect(decoded.count == 2)
        #expect(decoded[0].event.id == sharedID)
        #expect(decoded[1].event.id == sharedID)
        #expect(decoded[0].systemDelivered == false)
        #expect(decoded[1].systemDelivered == true)
    }

    // MARK: - Test 7: Real JSONEncoder Non-Finite Failure Retried Twice and Prior Cache Preserved

    @Test
    func realNonfiniteJSONEncoderFailureThrowsIsRetriedTwiceAndPreservesPriorCache() throws {
        var encoder = FleetNotificationInboxEncoder()
        let entries = Self.makeEntries(events: Self.makeAllSixEvents())
        let initialData = try encoder.encode(entries)
        let initialCachedBytes = encoder.cachedByteCount
        var attempts = 0
        let countingEncode: () -> Void = {
            attempts += 1
        }

        // The invalid values belong to actual production event types. Reuse the valid
        // event's UUID, but change its full payload so this cannot be a cache hit.
        for value in [Double.nan, Double.infinity, -Double.infinity] {
            let invalidEvents: [FleetNotificationEvent] = [
                .temperature(MinerTemperatureAlertEvent(
                    id: entries[2].id, deviceID: entries[2].event.deviceID,
                    minerName: "Invalid temperature", temperatureCelsius: value,
                    thresholdCelsius: 75, occurredAt: entries[2].event.occurredAt
                )),
                .power(MinerPowerAlertEvent(
                    id: entries[3].id, deviceID: entries[3].event.deviceID,
                    minerName: "Invalid power", kind: .exceeded, watts: value,
                    thresholdWatts: 15, occurredAt: entries[3].event.occurredAt
                ))
            ]
            for event in invalidEvents {
                let invalid = FleetNotificationInboxEntry(event: event, systemDelivered: false, inAppDelivered: false)
                for _ in 0..<2 {
                    let before = attempts
                    #expect(throws: EncodingError.self) {
                        try encoder.encode([invalid], willEncodeEntry: countingEncode)
                    }
                    #expect(attempts == before + 1)
                    #expect(encoder.cachedEntryCount == 6)
                    #expect(encoder.cachedByteCount == initialCachedBytes)
                }
            }
        }
        let beforeRecovery = attempts
        #expect(try encoder.encode(entries, willEncodeEntry: countingEncode) == initialData)
        #expect(attempts == beforeRecovery)
    }

    // MARK: - Test 8: More Than 100 Entries Cache Bound & Exact Eviction Count

    @Test
    func moreThan100EntriesBoundsCacheAndExactSubsetEvictsUnusedEntries() throws {
        var encoder = FleetNotificationInboxEncoder()
        let devID = UUID()
        let baseDate = Date(timeIntervalSince1970: 1700000000)

        // Construct 120 unique entries
        let entries = (0..<120).map { i in
            FleetNotificationInboxEntry(
                event: .temperature(MinerTemperatureAlertEvent(
                    id: UUID(), deviceID: devID, minerName: "Rig",
                    temperatureCelsius: Double(60 + i), thresholdCelsius: 70,
                    occurredAt: baseDate.addingTimeInterval(Double(i))
                )),
                systemDelivered: false,
                inAppDelivered: false
            )
        }

        let encodedData = try encoder.encode(entries)
        let decoded = try JSONDecoder().decode([FleetNotificationInboxEntry].self, from: encodedData)
        #expect(decoded.count == 120)
        #expect(decoded == entries)

        // Cached entry count must be bounded at 100
        #expect(encoder.cachedEntryCount <= 100)

        // Re-encoding a subset of exactly 80 entries must evict unused entries and leave exactly 80 cached entries
        let subset = Array(entries.suffix(80))
        let subsetData = try encoder.encode(subset)
        let decodedSubset = try JSONDecoder().decode([FleetNotificationInboxEntry].self, from: subsetData)
        #expect(decodedSubset == subset)
        #expect(encoder.cachedEntryCount == 80, "Expected exact cached entry count of 80 after subset eviction")
    }

    // MARK: - Test 9: Exact 512 KiB (524,288 Bytes) Inclusive Boundary & +1 Overflow

    @Test
    func exact512KiBInclusiveBoundaryAndPlusOneOverflow() throws {
        var encoder = FleetNotificationInboxEncoder()
        let devID = UUID(uuidString: "99999999-9999-9999-9999-999999999999")!
        let t0 = Date(timeIntervalSince1970: 1700000000)

        // 1. Measure single-entry baseline overhead with empty detail
        let baseEvent = FleetNotificationEvent.stateChange(MinerStateChangeEvent(
            id: UUID(uuidString: "88888888-8888-8888-8888-888888888888")!,
            deviceID: devID, minerName: "Rig", kind: .offline, detail: "", occurredAt: t0
        ))
        let baseEntry = FleetNotificationInboxEntry(event: baseEvent, systemDelivered: false, inAppDelivered: false)
        let baseData = try JSONEncoder().encode([baseEntry])
        // Array brackets count is 2: "[" (1 byte) and "]" (1 byte)
        // With detail = "", the JSON contains "detail":"" (length 11).
        // Let's compute the exact padding required so whole array length == 524,288 bytes.
        let targetBoundary = 512 * 1024 // 524,288 bytes
        let baseLength = baseData.count
        let neededChars = targetBoundary - baseLength

        let exactPadding = String(repeating: "A", count: neededChars)
        let boundaryEvent = FleetNotificationEvent.stateChange(MinerStateChangeEvent(
            id: UUID(uuidString: "88888888-8888-8888-8888-888888888888")!,
            deviceID: devID, minerName: "Rig", kind: .offline, detail: exactPadding, occurredAt: t0
        ))
        let boundaryEntry = FleetNotificationInboxEntry(event: boundaryEvent, systemDelivered: false, inAppDelivered: false)

        // Verify JSONEncoder produces exactly 524,288 bytes
        let directBoundaryData = try JSONEncoder().encode([boundaryEntry])
        #expect(directBoundaryData.count == 524_288)

        // Encoder must accept exactly 524,288 bytes (inclusive boundary)
        let boundaryResult = try encoder.encode([boundaryEntry])
        #expect(boundaryResult.count == 524_288)

        // Now add exactly 1 byte to detail: 524,289 bytes -> must throw
        let overflowPadding = exactPadding + "B"
        let overflowEvent = FleetNotificationEvent.stateChange(MinerStateChangeEvent(
            id: UUID(uuidString: "88888888-8888-8888-8888-888888888888")!,
            deviceID: devID, minerName: "Rig", kind: .offline, detail: overflowPadding, occurredAt: t0
        ))
        let overflowEntry = FleetNotificationInboxEntry(event: overflowEvent, systemDelivered: false, inAppDelivered: false)

        let directOverflowData = try JSONEncoder().encode([overflowEntry])
        #expect(directOverflowData.count == 524_289)

        #expect(throws: (any Error).self) {
            try encoder.encode([overflowEntry])
        }

        // Exact two-entry boundary includes the inter-entry comma, not just brackets.
        let secondID = UUID()
        func secondEntry(padding: Int) -> FleetNotificationInboxEntry {
            FleetNotificationInboxEntry(
                event: .stateChange(MinerStateChangeEvent(
                    id: secondID, deviceID: devID, minerName: "B", kind: .backOnline,
                    detail: String(repeating: "D", count: padding), occurredAt: t0
                )), systemDelivered: false, inAppDelivered: false
            )
        }
        let twoEntryOverhead = try JSONEncoder().encode([baseEntry, secondEntry(padding: 0)]).count
        let secondPadding = targetBoundary - twoEntryOverhead
        let pair = [baseEntry, secondEntry(padding: secondPadding)]
        #expect(try JSONEncoder().encode(pair).count == 524_288)
        let twoEntryData = try encoder.encode(pair)
        #expect(twoEntryData.count == 524_288)
        #expect(try JSONDecoder().decode([FleetNotificationInboxEntry].self, from: twoEntryData) == pair)
        let overflowingPair = [baseEntry, secondEntry(padding: secondPadding + 1)]
        #expect(try JSONEncoder().encode(overflowingPair).count == 524_289)
        #expect(throws: (any Error).self) { try encoder.encode(overflowingPair) }
        #expect(encoder.cachedEntryCount == 2)
        #expect(encoder.cachedByteCount <= 524_288)
        #expect(try encoder.encode(pair) == twoEntryData)
    }

    // MARK: - Test 10: Empty Array Clears Cache

    @Test
    func storeEncodingFailureAndOversizeDoNotWriteAndValidRetryDoes() throws {
        let suite = "app.hashfleet.encoder-failure-tests.\(UUID().uuidString)"
        let defaults = TrackingUserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FleetStore(defaults: defaults)
        let key = FleetStore.notificationInboxStorageKey
        let valid = Self.makeEntries(events: Self.makeAllSixEvents())
        store.notificationInbox = valid
        store.persistNotificationInbox()
        let saved = try #require(defaults.data(forKey: key))
        let writes = defaults.setCallsByKey[key, default: 0]

        let invalid = FleetNotificationInboxEntry(
            event: .temperature(MinerTemperatureAlertEvent(
                id: valid[2].id, deviceID: valid[2].event.deviceID,
                minerName: "Invalid", temperatureCelsius: .infinity,
                thresholdCelsius: 75, occurredAt: Date()
            )), systemDelivered: false, inAppDelivered: false
        )
        let oversize = FleetNotificationInboxEntry(
            event: .stateChange(MinerStateChangeEvent(
                id: valid[4].id, deviceID: valid[4].event.deviceID,
                minerName: "Oversize", kind: .offline,
                detail: String(repeating: "A", count: 512 * 1024), occurredAt: Date()
            )), systemDelivered: false, inAppDelivered: false
        )
        for rejected in [invalid, oversize] {
            store.notificationInbox = [rejected]
            store.persistNotificationInbox()
            store.persistNotificationInbox()
            #expect(defaults.setCallsByKey[key, default: 0] == writes)
            #expect(defaults.data(forKey: key) == saved)
            #expect(store.notificationInboxEncoder.cachedEntryCount == valid.count)
        }
        store.notificationInbox = valid
        store.persistNotificationInbox()
        #expect(defaults.setCallsByKey[key, default: 0] == writes + 1)
        #expect(try JSONDecoder().decode([FleetNotificationInboxEntry].self,
                                        from: #require(defaults.data(forKey: key))) == valid)
    }

    @Test
    func emptyArrayClearsCacheAndProducesValidEmptyJSONArray() throws {
        var encoder = FleetNotificationInboxEncoder()
        let entries = Self.makeEntries(events: Self.makeAllSixEvents())

        _ = try encoder.encode(entries)
        #expect(encoder.cachedEntryCount == 6)
        #expect(encoder.cachedByteCount > 0)

        let emptyData = try encoder.encode([])
        #expect(encoder.cachedEntryCount == 0)
        #expect(encoder.cachedByteCount == 0)

        let decoded = try JSONDecoder().decode([FleetNotificationInboxEntry].self, from: emptyData)
        #expect(decoded.isEmpty)
    }

    // MARK: - Test 11: Multi-Store Persistence, Setter Increments, and Last-Writer-Wins Restoration

    @Test
    func multiStorePersistenceSetterIncrementsAndLastWriterWinsFidelity() throws {
        let suite = "app.hashfleet.encoder-tracking-tests.\(UUID().uuidString)"
        let trackingDefaults = TrackingUserDefaults(suiteName: suite)!
        defer { trackingDefaults.removePersistentDomain(forName: suite) }

        let devID = UUID()
        let device = MinerDevice(id: devID, name: "Rig-1", address: "192.168.1.50")

        // Seed devices in defaults before creating store instances so restoreNotificationInbox retains entries
        let encodedDevices = try JSONEncoder().encode([device])
        trackingDefaults.set(encodedDevices, forKey: FleetStore.storageKey)

        let storeA = FleetStore(defaults: trackingDefaults)
        #expect(storeA.devices.count == 1)

        let t0 = Date()
        let event = FleetNotificationEvent.blockFound(MinerBlockFoundEvent(
            id: UUID(), deviceID: devID, minerName: "Rig-1", coinLabel: "BTC", height: 850_000, count: 1, occurredAt: t0
        ))

        // Initial enqueue writes to defaults
        storeA.enqueueNotification(event)
        let initialWrites = trackingDefaults.setCallsByKey[FleetStore.notificationInboxStorageKey, default: 0]
        #expect(initialWrites >= 1)

        // Calling storeA.persistNotificationInbox() twice increments the setter count on each call
        storeA.persistNotificationInbox()
        let writesAfterCall1 = trackingDefaults.setCallsByKey[FleetStore.notificationInboxStorageKey, default: 0]
        #expect(writesAfterCall1 == initialWrites + 1)

        storeA.persistNotificationInbox()
        let writesAfterCall2 = trackingDefaults.setCallsByKey[FleetStore.notificationInboxStorageKey, default: 0]
        #expect(writesAfterCall2 == writesAfterCall1 + 1)

        // Separate Store B mounts same UserDefaults suite and restores
        let storeB = FleetStore(defaults: trackingDefaults)
        #expect(storeB.devices.count == 1)
        #expect(storeB.notificationInbox.count == 1)
        #expect(storeB.notificationInbox.first?.event.id == event.id)
        #expect(storeB.notificationInbox.first?.systemDelivered == false)

        // Store B marks system delivered -> writes its update to shared defaults
        storeB.markSystemNotificationDelivered(for: event)
        let writesAfterB = trackingDefaults.setCallsByKey[FleetStore.notificationInboxStorageKey, default: 0]
        #expect(writesAfterB > writesAfterCall2)

        // Verify last-writer-wins fidelity:
        // storeA still holds its un-updated in-memory inbox where systemDelivered is false.
        // If storeA now executes persistNotificationInbox(), it overwrites the domain with its state.
        storeA.persistNotificationInbox()
        let writesAfterAOverwrite = trackingDefaults.setCallsByKey[FleetStore.notificationInboxStorageKey, default: 0]
        #expect(writesAfterAOverwrite > writesAfterB)

        // Fresh Store C inspects backing storage and decodes storeA's last-written state
        let storeC = FleetStore(defaults: trackingDefaults)
        #expect(storeC.notificationInbox.first?.systemDelivered == false, "Last-writer-wins semantics preserved across stores")
    }
}
