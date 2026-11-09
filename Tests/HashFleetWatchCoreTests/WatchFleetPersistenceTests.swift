import Foundation
import Testing
@testable import HashFleetWatchCore

@MainActor
@Suite struct WatchFleetPersistenceTests {
    private func backups(beside url: URL) -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: url.deletingLastPathComponent(), includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.lastPathComponent.contains(".corrupt-") }
    }

    private func writeCorrupt(_ content: String, at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(content.utf8).write(to: url)
    }

    @Test func corruptFileIsKeptAsUniqueBackupWithOriginalBytes() throws {
        let url = temporaryStorageURL(); defer { cleanUp(url) }
        try writeCorrupt("garbage-one", at: url)
        let store = WatchFleetStore(storageURL: url, client: ScriptedClient())
        #expect(store.storageError != nil)
        let first = backups(beside: url)
        #expect(first.count == 1)
        #expect(try String(contentsOf: first[0], encoding: .utf8) == "garbage-one")
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func earlierBackupsAreNeverDeletedOrOverwritten() throws {
        let url = temporaryStorageURL(); defer { cleanUp(url) }
        try writeCorrupt("first", at: url)
        _ = WatchFleetStore(storageURL: url, client: ScriptedClient())
        try writeCorrupt("second", at: url)
        _ = WatchFleetStore(storageURL: url, client: ScriptedClient())
        try writeCorrupt("third", at: url)
        _ = WatchFleetStore(storageURL: url, client: ScriptedClient())
        let contents = try backups(beside: url).map { try String(contentsOf: $0, encoding: .utf8) }
        #expect(Set(contents) == ["first", "second", "third"])
    }

    @Test func failedQuarantineBlocksWritesAndKeepsOriginalFile() async throws {
        let url = temporaryStorageURL()
        let directory = url.deletingLastPathComponent()
        try writeCorrupt("precious-unreadable", at: url)
        // A read-only directory prevents moving the file aside.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
            cleanUp(url)
        }
        guard !FileManager.default.isWritableFile(atPath: directory.path) else { return } // e.g. running as root

        let client = ScriptedClient()
        let store = WatchFleetStore(storageURL: url, client: client)
        #expect(store.storageError?.contains("paused") == true)
        #expect(throws: WatchFleetStoreError.persistenceFailed) { try store.addMiner(name: "a", address: "192.168.1.1") }
        #expect(throws: WatchFleetStoreError.persistenceFailed) {
            try store.importMiners([try WatchMiner(name: "a", address: "192.168.1.2")])
        }
        #expect(store.miners.isEmpty)
        await store.refresh()
        #expect(try String(contentsOf: url, encoding: .utf8) == "precious-unreadable")
    }

    @Test func oversizedFileIsNotTrusted() throws {
        let url = temporaryStorageURL(); defer { cleanUp(url) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let padding = String(repeating: " ", count: WatchFleetPersistence.maximumFileBytes + 1)
        try Data((#"{"version":1,"miners":[],"readings":[]}"# + padding).utf8).write(to: url)
        let store = WatchFleetStore(storageURL: url, client: ScriptedClient())
        #expect(store.storageError != nil)
        #expect(backups(beside: url).count == 1)
    }

    @Test func cachedTemperatureSentinelsAreSanitizedOnDecode() throws {
        let url = temporaryStorageURL(); defer { cleanUp(url) }
        let id = "00000000-0000-0000-0000-0000000000AA"
        let json = """
        {"version":1,
         "miners":[{"id":"\(id)","name":"x","address":"http://192.168.1.1"}],
         "readings":[{"minerID":"\(id)","observedAt":1000,"hashrateGHs":5,
                      "chipTemperatureC":-1,"vrTemperatureC":99999,"powerWatts":-3}]}
        """
        try writeCorrupt(json, at: url)
        let store = WatchFleetStore(storageURL: url, client: ScriptedClient())
        let reading = try #require(store.readings[UUID(uuidString: id)!])
        #expect(store.storageError == nil)
        #expect(reading.chipTemperatureC == nil)
        #expect(reading.vrTemperatureC == nil)
        #expect(reading.powerWatts == nil)
        #expect(reading.hashrateGHs == 5)
        #expect(reading.observedAt == Date(timeIntervalSinceReferenceDate: 1000))
    }

    @Test func readingForUnknownMinerMakesFileCorrupt() throws {
        let url = temporaryStorageURL(); defer { cleanUp(url) }
        let json = #"{"version":1,"miners":[],"readings":[{"minerID":"00000000-0000-0000-0000-0000000000BB","observedAt":1}]}"#
        try writeCorrupt(json, at: url)
        #expect(WatchFleetStore(storageURL: url, client: ScriptedClient()).storageError != nil)
    }
}
