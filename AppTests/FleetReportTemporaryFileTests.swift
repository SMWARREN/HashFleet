import Foundation
import Testing
@testable import HashFleet

struct FleetReportTemporaryFileTests {
    @Test func filenamesAreBoundedUniqueAndCleanupIsScopedAndIdempotent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FleetReportTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try FleetReportTemporaryFile.create(data: Data("one".utf8), format: .csv, capturedAt: FleetReportFixtures.date, root: root)
        let second = try FleetReportTemporaryFile.create(data: Data("two".utf8), format: .pdf, capturedAt: FleetReportFixtures.date, root: root)
        #expect(first.url != second.url)
        #expect(first.url.lastPathComponent.utf8.count < 80)
        #expect(first.url.lastPathComponent.hasPrefix("hash-fleet-snapshot-20231114T221320Z-"))
        #expect(first.url.pathExtension == "csv")
        #expect(second.url.pathExtension == "pdf")
        #expect(try Data(contentsOf: first.url) == Data("one".utf8))
        first.remove()
        first.remove()
        #expect(!FileManager.default.fileExists(atPath: first.url.path))
        #expect(FileManager.default.fileExists(atPath: second.url.path))
        second.remove()
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    @Test func pruningOnlyRemovesOldOwnedUUIDDirectories() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("FleetReportTests-\(UUID())")
        defer { try? manager.removeItem(at: root) }
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        let old = root.appendingPathComponent(UUID().uuidString)
        let recent = root.appendingPathComponent(UUID().uuidString)
        let unrelated = root.appendingPathComponent("keep-me")
        let symlink = root.appendingPathComponent(UUID().uuidString)
        for directory in [old, recent, unrelated] {
            try manager.createDirectory(at: directory, withIntermediateDirectories: false)
        }
        try manager.createSymbolicLink(at: symlink, withDestinationURL: unrelated)
        let oldDate = Date().addingTimeInterval(-172_800)
        for directory in [old, unrelated] {
            try manager.setAttributes([.modificationDate: oldDate], ofItemAtPath: directory.path)
        }
        FleetReportTemporaryFile.prune(in: root, before: Date().addingTimeInterval(-86_400))
        #expect(!manager.fileExists(atPath: old.path))
        #expect(manager.fileExists(atPath: recent.path))
        #expect(manager.fileExists(atPath: unrelated.path))
        #expect(manager.fileExists(atPath: symlink.path))
    }

    @Test func invalidRootFailsWithoutReplacingExistingFile() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("FleetReportTests-\(UUID())")
        defer { try? manager.removeItem(at: root) }
        try Data("keep".utf8).write(to: root)
        #expect(throws: (any Error).self) {
            try FleetReportTemporaryFile.create(data: Data(), format: .csv, capturedAt: FleetReportFixtures.date, root: root)
        }
        #expect(try Data(contentsOf: root) == Data("keep".utf8))
    }

    @Test func fleetReportDocumentWrapsDataAndTypes() {
        let pdfData = Data("%PDF-1.4 test data".utf8)
        let pdfDoc = FleetReportDocument(data: pdfData, contentType: .pdf)
        #expect(pdfDoc.contentType == .pdf)
        #expect(pdfDoc.data == pdfData)
        #expect(FleetReportDocument.readableContentTypes.contains(.pdf))
        #expect(FleetReportDocument.readableContentTypes.contains(.commaSeparatedText))

        let csvData = Data("miner,hashrate\ntest,100".utf8)
        let csvDoc = FleetReportDocument(data: csvData, contentType: .commaSeparatedText)
        #expect(csvDoc.contentType == .commaSeparatedText)
        #expect(csvDoc.data == csvData)
    }
}
