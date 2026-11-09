import Foundation
import Testing
@testable import HashFleet

/// The journal writes to the real `UserDefaults.standard`, so every test uses random device UUIDs
/// and removes exactly the keys derived from them, never the app's persistent domain.
@MainActor
@Suite("Miner tuning journal store")
struct MinerTuningJournalTests {
    /// Hands out unique device IDs and removes only their journal keys when cleaned up.
    private final class Scope {
        private var ids: [UUID] = []

        func newDevice() -> UUID {
            let id = UUID()
            ids.append(id)
            return id
        }

        func cleanup() {
            for id in ids { UserDefaults.standard.removeObject(forKey: Self.key(id)) }
            ids.removeAll()
        }

        /// The persisted key is private to the store. It is part of the on-disk contract, so the
        /// tests pin it: renaming it would orphan every owner's existing journal.
        static func key(_ id: UUID) -> String { "app.hashfleet.tuningJournal.\(id.uuidString)" }
    }

    private func stored(_ id: UUID) -> Data? {
        UserDefaults.standard.data(forKey: Scope.key(id))
    }

    private func entry(
        _ title: String,
        detail: String = "detail",
        date: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> MinerTuningJournalEntry {
        MinerTuningJournalEntry(id: UUID(), date: date, title: title, detail: detail)
    }

    @Test("The journal is capped at twelve entries")
    func limitIsTwelve() {
        #expect(MinerTuningJournalCard.limit == 12)
    }

    @Test("Absent data loads as empty and loading never writes")
    func absentLoadsEmpty() {
        let scope = Scope()
        defer { scope.cleanup() }
        let device = scope.newDevice()

        #expect(MinerTuningJournalStore.load(deviceID: device).isEmpty)
        #expect(stored(device) == nil)
    }

    struct BadPayload: Sendable, CustomTestStringConvertible {
        let name: String
        let data: Data
        var testDescription: String { name }
    }

    @Test("Corrupt or wrong-shape data loads as empty and is replaced by the next record", arguments: [
        BadPayload(name: "empty data", data: Data()),
        BadPayload(name: "not JSON", data: Data("not json".utf8)),
        BadPayload(name: "truncated JSON", data: Data("[{\"id\":\"".utf8)),
        BadPayload(name: "object instead of array", data: Data("{\"title\":\"x\"}".utf8)),
        BadPayload(name: "array of strings", data: Data("[\"a\",\"b\"]".utf8)),
        BadPayload(name: "array of nulls", data: Data("[null]".utf8)),
        BadPayload(name: "entry missing detail", data: Data(
            "[{\"id\":\"\(UUID().uuidString)\",\"date\":0,\"title\":\"t\"}]".utf8)),
        BadPayload(name: "entry with non-UUID id", data: Data(
            "[{\"id\":\"nope\",\"date\":0,\"title\":\"t\",\"detail\":\"d\"}]".utf8)),
        BadPayload(name: "entry with non-numeric date", data: Data(
            "[{\"id\":\"\(UUID().uuidString)\",\"date\":\"yesterday\",\"title\":\"t\",\"detail\":\"d\"}]".utf8)),
        BadPayload(name: "one good entry among a bad one", data: Data(
            "[{\"id\":\"\(UUID().uuidString)\",\"date\":0,\"title\":\"t\",\"detail\":\"d\"},{\"id\":1}]".utf8))
    ])
    func corruptDataIsSafelyEmpty(payload: BadPayload) throws {
        let scope = Scope()
        defer { scope.cleanup() }
        let device = scope.newDevice()
        UserDefaults.standard.set(payload.data, forKey: Scope.key(device))

        // A bad blob is dropped as a whole rather than partially trusted.
        #expect(MinerTuningJournalStore.load(deviceID: device).isEmpty)

        let updated = MinerTuningJournalStore.record(
            title: "Recovered", detail: "after corruption", to: [], deviceID: device)
        #expect(updated.map(\.title) == ["Recovered"])
        #expect(MinerTuningJournalStore.load(deviceID: device) == updated)
    }

    @Test("Non-data values under the key load as empty")
    func nonDataValueLoadsEmpty() {
        let scope = Scope()
        defer { scope.cleanup() }
        let device = scope.newDevice()
        UserDefaults.standard.set(42, forKey: Scope.key(device))
        #expect(MinerTuningJournalStore.load(deviceID: device).isEmpty)
        UserDefaults.standard.set(["a", "b"], forKey: Scope.key(device))
        #expect(MinerTuningJournalStore.load(deviceID: device).isEmpty)
    }

    @Test("Record returns the new entry first and persists exactly what it returns")
    func recordReturnsAndPersistsExactly() throws {
        let scope = Scope()
        defer { scope.cleanup() }
        let device = scope.newDevice()
        let before = Date()

        let first = MinerTuningJournalStore.record(title: "Frequency", detail: "550 MHz", to: [], deviceID: device)
        let after = Date()

        let created = try #require(first.first)
        #expect(first.count == 1)
        #expect(created.title == "Frequency")
        #expect(created.detail == "550 MHz")
        #expect(created.date >= before && created.date <= after)
        #expect(MinerTuningJournalStore.load(deviceID: device) == first)

        let second = MinerTuningJournalStore.record(title: "Voltage", detail: "1100 mV", to: first, deviceID: device)
        #expect(second.map(\.title) == ["Voltage", "Frequency"])
        #expect(second[1] == created)
        #expect(second[0].id != created.id)
        #expect(second[0].date >= created.date)
        #expect(MinerTuningJournalStore.load(deviceID: device) == second)
    }

    @Test("Only the newest twelve entries are kept, newest first, with older ones untouched")
    func newestFirstTwelveCap() {
        let scope = Scope()
        defer { scope.cleanup() }
        let device = scope.newDevice()

        var journal: [MinerTuningJournalEntry] = []
        var history: [[MinerTuningJournalEntry]] = []
        for index in 1...15 {
            journal = MinerTuningJournalStore.record(
                title: "Change \(index)", detail: "step \(index)", to: journal, deviceID: device)
            history.append(journal)
            #expect(journal.count == min(index, 12))
            #expect(journal.first?.title == "Change \(index)")
        }

        let loaded = MinerTuningJournalStore.load(deviceID: device)
        #expect(loaded == journal)
        #expect(loaded.map(\.title) == (4...15).reversed().map { "Change \($0)" })
        // The survivors are the original entries, not rewritten copies: ids and dates match
        // what each earlier call returned.
        let previous = history[13]
        #expect(Array(loaded.dropFirst()) == Array(previous.prefix(11)))
        #expect(Set(loaded.map(\.id)).count == 12)
        #expect(!loaded.contains { ["Change 1", "Change 2", "Change 3"].contains($0.title) })
    }

    @Test("An oversized supplied list is trimmed to the limit and the head is preserved")
    func oversizedInputIsTrimmed() {
        let scope = Scope()
        defer { scope.cleanup() }
        let device = scope.newDevice()
        let existing = (0..<20).map { entry("Old \($0)") }

        let updated = MinerTuningJournalStore.record(title: "New", detail: "d", to: existing, deviceID: device)

        #expect(updated.count == 12)
        #expect(updated.first?.title == "New")
        #expect(Array(updated.dropFirst()) == Array(existing.prefix(11)))
        #expect(MinerTuningJournalStore.load(deviceID: device) == updated)
    }

    @Test("Record builds on the list it is given, replacing what was stored")
    func recordUsesSuppliedListNotStoredOne() {
        let scope = Scope()
        defer { scope.cleanup() }
        let device = scope.newDevice()
        let stale = MinerTuningJournalStore.record(title: "Stored", detail: "d", to: [], deviceID: device)
        #expect(stale.count == 1)

        let replaced = MinerTuningJournalStore.record(title: "Fresh", detail: "d", to: [], deviceID: device)

        #expect(replaced.map(\.title) == ["Fresh"])
        #expect(MinerTuningJournalStore.load(deviceID: device).map(\.title) == ["Fresh"])
    }

    @Test("Each miner has its own journal")
    func perMinerIsolation() {
        let scope = Scope()
        defer { scope.cleanup() }
        let first = scope.newDevice()
        let second = scope.newDevice()

        let firstJournal = MinerTuningJournalStore.record(title: "A1", detail: "a", to: [], deviceID: first)
        #expect(MinerTuningJournalStore.load(deviceID: second).isEmpty)
        #expect(stored(second) == nil)

        let secondJournal = MinerTuningJournalStore.record(title: "B1", detail: "b", to: [], deviceID: second)
        _ = MinerTuningJournalStore.record(title: "A2", detail: "a", to: firstJournal, deviceID: first)

        #expect(MinerTuningJournalStore.load(deviceID: first).map(\.title) == ["A2", "A1"])
        #expect(MinerTuningJournalStore.load(deviceID: second) == secondJournal)
        #expect(MinerTuningJournalStore.load(deviceID: second).map(\.title) == ["B1"])
        // Both miners are stored under their own keys.
        let keys = UserDefaults.standard.dictionaryRepresentation().keys
        #expect(keys.contains(Scope.key(first)))
        #expect(keys.contains(Scope.key(second)))
    }

    struct TextCase: Sendable, CustomTestStringConvertible {
        let name: String
        let title: String
        let detail: String
        var testDescription: String { name }
    }

    @Test("Unicode, newlines, quotes and empty text round-trip byte for byte", arguments: [
        TextCase(name: "empty", title: "", detail: ""),
        TextCase(name: "newlines", title: "Line1\nLine2\r\nLine3", detail: "\n\n  leading and trailing  \n"),
        TextCase(name: "emoji and ZWJ", title: "⚡️ Tuned 👩‍💻", detail: "🇺🇸 🏳️‍🌈 hash ⛏️"),
        TextCase(name: "CJK and RTL", title: "频率 530 MHz", detail: "مرحبا بالعالم עברית"),
        TextCase(name: "combining marks", title: "e\u{301} vs \u{e9}", detail: "A\u{30a} vs \u{c5}"),
        TextCase(name: "quotes and backslashes", title: "He said \"go\" \\ done", detail: "{\"json\":[1,2]}"),
        TextCase(name: "control characters", title: "tab\there\u{0}nul", detail: "bell\u{7} esc\u{1b}"),
        TextCase(name: "line separators", title: "a\u{2028}b\u{2029}c", detail: "\u{feff}bom"),
        TextCase(name: "very long", title: String(repeating: "x", count: 50_000), detail: String(repeating: "é\n", count: 20_000))
    ])
    func textRoundTrips(testCase: TextCase) throws {
        let scope = Scope()
        defer { scope.cleanup() }
        let device = scope.newDevice()

        let recorded = MinerTuningJournalStore.record(
            title: testCase.title, detail: testCase.detail, to: [], deviceID: device)
        let loaded = try #require(MinerTuningJournalStore.load(deviceID: device).first)

        // Compare unicode scalars so canonical-equivalent strings cannot hide a normalisation change.
        #expect(Array(loaded.title.unicodeScalars) == Array(testCase.title.unicodeScalars))
        #expect(Array(loaded.detail.unicodeScalars) == Array(testCase.detail.unicodeScalars))
        #expect(loaded == recorded.first)
    }

    @Test("Identifiers and dates survive persistence exactly")
    func identityAndDatesRoundTrip() throws {
        let scope = Scope()
        defer { scope.cleanup() }
        let device = scope.newDevice()
        let dates: [Date] = [
            Date(timeIntervalSinceReferenceDate: 0),
            Date(timeIntervalSince1970: 0),
            Date(timeIntervalSince1970: 1_700_000_000.123_456),
            Date(timeIntervalSinceReferenceDate: 1.0 / 3.0),
            .distantPast,
            .distantFuture
        ]
        let seeded = dates.enumerated().map { entry("Seed \($0.offset)", date: $0.element) }
        UserDefaults.standard.set(try JSONEncoder().encode(seeded), forKey: Scope.key(device))

        let loaded = MinerTuningJournalStore.load(deviceID: device)

        #expect(loaded == seeded)
        #expect(loaded.map(\.id) == seeded.map(\.id))
        #expect(loaded.map(\.date.timeIntervalSinceReferenceDate) == seeded.map(\.date.timeIntervalSinceReferenceDate))

        // Recording on top keeps every previously seeded entry intact, up to the cap.
        let updated = MinerTuningJournalStore.record(title: "Next", detail: "d", to: loaded, deviceID: device)
        #expect(Array(updated.dropFirst()) == seeded)
        #expect(MinerTuningJournalStore.load(deviceID: device) == updated)
        let newest = try #require(updated.first)
        #expect(!seeded.map(\.id).contains(newest.id))
        #expect(Set(updated.map(\.id)).count == updated.count)
    }
}
