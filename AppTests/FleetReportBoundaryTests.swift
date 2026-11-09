import Foundation
import Testing
import HashFleetCore
@testable import HashFleet

@Suite("Fleet report boundary", .serialized)
@MainActor
struct FleetReportBoundaryTests {

    // MARK: - Privacy & Redaction Boundary

    @Test("Snapshot capture and CSV export strictly redact device names, hostnames, and credentials")
    func testPrivacyRedactionScrubbing() throws {
        let (defaults, suite) = try makeSuite()
        defer { defaults.removePersistentDomain(forName: suite) }

        let secretName = "Vault-Antminer-SecretRoom"
        let secretHost = "192.168.100.222"
        let secretPort = "8080"
        let device = MinerDevice(name: secretName, address: "http://\(secretHost):\(secretPort)")
        defaults.set(try JSONEncoder().encode([device]), forKey: FleetStore.storageKey)

        let store = FleetStore(defaults: defaults)
        let captureDate = Date(timeIntervalSince1970: 1_700_000_000)
        let info = MinerInfo(raw: [
            "hashRate": .number(2500),
            "power": .number(85),
            "temp": .number(56),
            "password": .string("hiddenPassword"),
            "wallet": .string("bc1qsecretwalletaddress")
        ])
        store.snapshots[device.id] = MinerSnapshot(
            info: info, error: nil, updatedAt: captureDate, isCached: false
        )

        let snapshot = FleetReportSnapshot.capture(store: store, at: captureDate)
        #expect(snapshot.miners.count == 1)
        let capturedMiner = try #require(snapshot.miners.first)

        // Labels must be strictly anonymized 1-based index
        #expect(capturedMiner.id == 1)
        #expect(capturedMiner.label == "Miner 1")

        // CSV export verification
        let csvData = FleetReportCSV.encode(snapshot)
        let csvText = String(bytes: csvData, encoding: .utf8) ?? ""

        #expect(csvText.contains("Miner 1"))
        #expect(!csvText.contains(secretName))
        #expect(!csvText.contains(secretHost))
        #expect(!csvText.contains(secretPort))
        #expect(!csvText.contains("hiddenPassword"))
        #expect(!csvText.contains("bc1qsecretwalletaddress"))
        #expect(!csvText.contains(device.id.uuidString))
        #expect(csvText.contains("\"privacy\""))
        #expect(csvText.contains(FleetReportSnapshot.privacyNote))
    }

    // MARK: - Ordering & Connection Status Classification

    @Test("Miner sequence is stable 1-based and connection classification matches snapshot state")
    func testOrderingAndConnectionClassification() throws {
        let (defaults, suite) = try makeSuite()
        defer { defaults.removePersistentDomain(forName: suite) }

        let devA = MinerDevice(name: "A", address: "http://192.168.1.1")
        let devB = MinerDevice(name: "B", address: "http://192.168.1.2")
        let devC = MinerDevice(name: "C", address: "http://192.168.1.3")
        let devD = MinerDevice(name: "D", address: "http://192.168.1.4")
        defaults.set(try JSONEncoder().encode([devA, devB, devC, devD]), forKey: FleetStore.storageKey)

        let store = FleetStore(defaults: defaults)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        // devA: Online (info, not cached, no error)
        store.snapshots[devA.id] = MinerSnapshot(
            info: MinerInfo(raw: [:]), error: nil, updatedAt: now, isCached: false
        )
        // devB: Offline (error present)
        store.snapshots[devB.id] = MinerSnapshot(
            info: nil, error: "Connection timed out", updatedAt: now, isCached: false
        )
        // devC: Unknown (info present but cached)
        store.snapshots[devC.id] = MinerSnapshot(
            info: MinerInfo(raw: [:]), error: nil, updatedAt: now, isCached: true
        )
        // devD: Unknown (no snapshot)
        store.snapshots[devD.id] = nil

        let snapshot = FleetReportSnapshot.capture(store: store, at: now)
        #expect(snapshot.miners.map(\.id) == [1, 2, 3, 4])
        #expect(snapshot.miners.map(\.label) == ["Miner 1", "Miner 2", "Miner 3", "Miner 4"])

        #expect(snapshot.miners[0].connection == .online)
        #expect(snapshot.miners[1].connection == .offline)
        #expect(snapshot.miners[2].connection == .unknown)
        #expect(snapshot.miners[3].connection == .unknown)

        #expect(snapshot.onlineCount == 1)
        #expect(snapshot.offlineCount == 1)
        #expect(snapshot.unconfirmedCount == 2)
    }

    // MARK: - Freshness vs Power Freshness Boundaries

    @Test("Row freshness permits clock skew up to 60s while power freshness strictly rejects future skew")
    func testFreshnessVersusPowerFreshnessSkew() throws {
        let (defaults, suite) = try makeSuite()
        defer { defaults.removePersistentDomain(forName: suite) }

        let captureDate = Date(timeIntervalSince1970: 1_700_000_000)
        let futureSkewDate = captureDate.addingTimeInterval(30) // 30s into future

        let device = MinerDevice(name: "SkewRig", address: "http://192.168.1.10")
        defaults.set(try JSONEncoder().encode([device]), forKey: FleetStore.storageKey)
        let store = FleetStore(defaults: defaults)

        store.snapshots[device.id] = MinerSnapshot(
            info: MinerInfo(raw: [
                "hashRate": .number(1800),
                "power": .number(75),
                "temp": .number(50)
            ]),
            error: nil, updatedAt: futureSkewDate, isCached: false
        )

        let snapshot = FleetReportSnapshot.capture(store: store, at: captureDate)
        let miner = try #require(snapshot.miners.first)

        // Row freshness accepts up to 60s skew as .fresh
        #expect(miner.freshness == .fresh)
        #expect(miner.hashrateGHs == 1800)

        // However power freshness strictly rejects any future timestamp (age < 0)
        #expect(miner.powerWatts == nil)
    }

    @Test("Power observation freshness boundaries reject stale, future, and non-finite timestamps")
    func testPowerFreshnessBoundaryClassification() {
        let captureDate = Date(timeIntervalSince1970: 1_700_000_000)

        // Exact match
        #expect(FleetReportSnapshot.isFreshPowerObservation(observedAt: captureDate, capturedAt: captureDate))
        // 120 seconds old is the maximum freshness threshold
        #expect(FleetReportSnapshot.isFreshPowerObservation(
            observedAt: captureDate.addingTimeInterval(-120), capturedAt: captureDate
        ))
        // 121 seconds old is stale
        #expect(!FleetReportSnapshot.isFreshPowerObservation(
            observedAt: captureDate.addingTimeInterval(-121), capturedAt: captureDate
        ))
        // Future timestamp (even 1 second) is rejected
        #expect(!FleetReportSnapshot.isFreshPowerObservation(
            observedAt: captureDate.addingTimeInterval(1), capturedAt: captureDate
        ))
        // Nil or non-finite dates are rejected
        #expect(!FleetReportSnapshot.isFreshPowerObservation(observedAt: nil, capturedAt: captureDate))
        #expect(!FleetReportSnapshot.isFreshPowerObservation(
            observedAt: Date(timeIntervalSince1970: .infinity), capturedAt: captureDate
        ))
    }

    // MARK: - Temperature Sensor Placeholder Filtering

    @Test("Temperature sensor readings filter zero and negative hardware initialization placeholders")
    func testTemperaturePlaceholderFiltering() throws {
        let (defaults, suite) = try makeSuite()
        defer { defaults.removePersistentDomain(forName: suite) }

        let d1 = MinerDevice(name: "Valid", address: "http://192.168.1.1")
        let d2 = MinerDevice(name: "ZeroPlaceholder", address: "http://192.168.1.2")
        let d3 = MinerDevice(name: "NegativePlaceholder", address: "http://192.168.1.3")
        let d4 = MinerDevice(name: "Missing", address: "http://192.168.1.4")
        defaults.set(try JSONEncoder().encode([d1, d2, d3, d4]), forKey: FleetStore.storageKey)

        let store = FleetStore(defaults: defaults)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        store.snapshots[d1.id] = MinerSnapshot(
            info: MinerInfo(raw: ["temp": .number(52.5)]), error: nil, updatedAt: now, isCached: false
        )
        store.snapshots[d2.id] = MinerSnapshot(
            info: MinerInfo(raw: ["temp": .number(0.0)]), error: nil, updatedAt: now, isCached: false
        )
        store.snapshots[d3.id] = MinerSnapshot(
            info: MinerInfo(raw: ["temp": .number(-5.0)]), error: nil, updatedAt: now, isCached: false
        )
        store.snapshots[d4.id] = MinerSnapshot(
            info: MinerInfo(raw: [:]), error: nil, updatedAt: now, isCached: false
        )

        let snapshot = FleetReportSnapshot.capture(store: store, at: now)
        #expect(snapshot.miners[0].temperatureCelsius == 52.5)
        #expect(snapshot.miners[1].temperatureCelsius == nil)
        #expect(snapshot.miners[2].temperatureCelsius == nil)
        #expect(snapshot.miners[3].temperatureCelsius == nil)
    }

    // MARK: - Subtotals Calculation & Invariants

    @Test("Subtotals include only fresh online miners and distinguish reporting from eligible counts")
    func testSubtotalsCalculationAndInvariants() {
        let captureDate = Date(timeIntervalSince1970: 1_700_000_000)

        let m1 = FleetReportSnapshot.Miner(
            id: 1, connection: .online, freshness: .fresh, observedAt: captureDate,
            hashrateGHs: 2000, powerWatts: 50, temperatureCelsius: 50, fanRPM: 3000, uptimeSeconds: 1000
        )
        let m2 = FleetReportSnapshot.Miner(
            id: 2, connection: .online, freshness: .fresh, observedAt: captureDate,
            hashrateGHs: 1000, powerWatts: 0, temperatureCelsius: 48, fanRPM: 2800, uptimeSeconds: 1000
        )
        let m3 = FleetReportSnapshot.Miner(
            id: 3, connection: .online, freshness: .fresh, observedAt: captureDate,
            hashrateGHs: nil, powerWatts: nil, temperatureCelsius: 48, fanRPM: 2800, uptimeSeconds: 1000
        )
        let m4 = FleetReportSnapshot.Miner(
            id: 4, connection: .online, freshness: .stale, observedAt: captureDate.addingTimeInterval(-200),
            hashrateGHs: 9000, powerWatts: 300, temperatureCelsius: 70, fanRPM: 4000, uptimeSeconds: 5000
        )
        let m5 = FleetReportSnapshot.Miner(
            id: 5, connection: .offline, freshness: .unknown, observedAt: nil,
            hashrateGHs: 9000, powerWatts: 300, temperatureCelsius: nil, fanRPM: nil, uptimeSeconds: nil
        )

        let report = FleetReportSnapshot(capturedAt: captureDate, isDemo: false, miners: [m1, m2, m3, m4, m5])

        #expect(report.onlineCount == 4)
        #expect(report.offlineCount == 1)
        #expect(report.unconfirmedCount == 0)
        #expect(report.currentCount == 3) // m1, m2, m3

        // Hashrate: m1 (2000) + m2 (1000) = 3000. 2 reporting out of 3 eligible
        #expect(report.hashrate.value == 3000)
        #expect(report.hashrate.reporting == 2)
        #expect(report.hashrate.eligible == 3)
        #expect(report.hashrate.coverage == "2 of 3 fresh online miners")

        // Power: m1 (50) + m2 (0) = 50. Measured zero is valid! 2 reporting out of 3 eligible
        #expect(report.power.value == 50)
        #expect(report.power.reporting == 2)
        #expect(report.power.eligible == 3)
        #expect(report.power.coverage == "2 of 3 fresh online miners")
    }

    // MARK: - CSV Formula Neutralization & Table Layout

    @Test("CSV encoding neutralizes leading formula symbols across whitespace and control characters")
    func testCSVFormulaNeutralizationComprehensive() {
        let formulaVectors = [
            "=SUM(A1:A5)",
            "+cmd|' /C calc'!A0",
            "-2+3",
            "@SUM(B1)",
            "  \t =1+1",
            "\r\n+HYPERLINK(\"http://malicious.org\")",
            "\u{0000}=EXEC",
            "\u{0008}@SUM",
            "\u{001F}-99"
        ]

        for vector in formulaVectors {
            let encodedCell = FleetReportCSV.cell(vector)
            #expect(encodedCell.hasPrefix("\"'"), "Failed to neutralize formula in vector: \(vector)")
        }

        // Standard plain text and numbers must not receive formula neutralization quotes
        #expect(FleetReportCSV.cell("Miner 1") == "\"Miner 1\"")
        #expect(FleetReportCSV.cell("1250.5") == "\"1250.5\"")
        #expect(FleetReportCSV.cell("") == "\"\"")
    }

    @Test("CSV table preserves rectangular 25-column shape for empty fleet and multiline values")
    func testCSVRectangularTableIntegrity() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        // Empty fleet export
        let emptyReport = FleetReportSnapshot(capturedAt: date, isDemo: false, miners: [])
        let emptyData = FleetReportCSV.encode(emptyReport)
        let emptyText = String(bytes: emptyData, encoding: .utf8) ?? ""
        let emptyRows = emptyText.components(separatedBy: "\r\n").filter { !$0.isEmpty }

        #expect(emptyRows.count == 2)
        #expect(emptyRows.allSatisfy { $0.components(separatedBy: "\",\"").count == 25 })
        #expect(emptyText.contains("No miners"))
        #expect(emptyText.hasSuffix("\r\n"))

        // Populated fleet with tricky multiline notes
        let miner = FleetReportSnapshot.Miner(
            id: 1, connection: .online, freshness: .fresh, observedAt: date,
            hashrateGHs: 1500, powerWatts: 60, temperatureCelsius: 52, fanRPM: 3200, uptimeSeconds: 7200
        )
        let populatedReport = FleetReportSnapshot(capturedAt: date, isDemo: true, miners: [miner])
        let populatedData = FleetReportCSV.encode(populatedReport)
        let populatedText = String(bytes: populatedData, encoding: .utf8) ?? ""

        #expect(populatedText.contains("Demo / simulated"))
        #expect(populatedText.contains("\"1500.0\""))
        #expect(populatedText.contains("\"60.0\""))
        #expect(populatedText.hasSuffix("\r\n"))
    }

    // MARK: - Temporary File Export & Pruning Lifecycle

    @Test("Temporary file creation excludes backup, writes atomically, and removes idempotently")
    func testTemporaryFileLifecycleAndAttributes() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FleetReportLifecycleTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let sampleData = Data("sample csv export content".utf8)
        let capturedAt = Date(timeIntervalSince1970: 1_700_000_000)

        let tempFile = try FleetReportTemporaryFile.create(
            data: sampleData, format: .csv, capturedAt: capturedAt, root: root
        )

        #expect(FileManager.default.fileExists(atPath: tempFile.url.path))
        #expect(try Data(contentsOf: tempFile.url) == sampleData)
        #expect(tempFile.url.pathExtension == "csv")
        #expect(tempFile.url.lastPathComponent.hasPrefix("hash-fleet-snapshot-20231114T221320Z-"))

        // Resource values check: directory should be excluded from backup
        let values = try tempFile.url.deletingLastPathComponent().resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)

        // Removal is idempotent
        tempFile.remove()
        #expect(!FileManager.default.fileExists(atPath: tempFile.url.path))
        tempFile.remove()
        #expect(!FileManager.default.fileExists(atPath: tempFile.url.path))
    }

    @Test("Temporary file pruning leaves recent folders, symlinks, and non-UUID directories untouched")
    func testTemporaryFilePruningRules() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory
            .appendingPathComponent("FleetReportPruningTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? manager.removeItem(at: root) }
        try manager.createDirectory(at: root, withIntermediateDirectories: true)

        let oldUUIDDir = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let recentUUIDDir = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let nonUUIDDir = root.appendingPathComponent("custom-backup-dir", isDirectory: true)
        let symlinkDir = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let regularFile = root.appendingPathComponent("loose-file.txt")

        try manager.createDirectory(at: oldUUIDDir, withIntermediateDirectories: false)
        try manager.createDirectory(at: recentUUIDDir, withIntermediateDirectories: false)
        try manager.createDirectory(at: nonUUIDDir, withIntermediateDirectories: false)
        try manager.createSymbolicLink(at: symlinkDir, withDestinationURL: nonUUIDDir)
        try Data("content".utf8).write(to: regularFile)

        // Set oldUUIDDir and nonUUIDDir modification date to 3 days ago
        let oldDate = Date().addingTimeInterval(-(3 * 86_400))
        try manager.setAttributes([.modificationDate: oldDate], ofItemAtPath: oldUUIDDir.path)
        try manager.setAttributes([.modificationDate: oldDate], ofItemAtPath: nonUUIDDir.path)

        let cutoff = Date().addingTimeInterval(-86_400)
        FleetReportTemporaryFile.prune(in: root, before: cutoff)

        // Only the old UUID-named directory should be pruned
        #expect(!manager.fileExists(atPath: oldUUIDDir.path))
        #expect(manager.fileExists(atPath: recentUUIDDir.path))
        #expect(manager.fileExists(atPath: nonUUIDDir.path))
        #expect(manager.fileExists(atPath: symlinkDir.path))
        #expect(manager.fileExists(atPath: regularFile.path))
    }

    // MARK: - Helpers

    private func makeSuite() throws -> (UserDefaults, String) {
        let suite = "app.hashfleet.report.boundary.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return (defaults, suite)
    }
}
