import Foundation
import Testing
@testable import HashFleet

/// The component branches on this exact policy before inserting raw Text or Copy into its tree.
/// Actual SwiftUI accessibility-tree and lifecycle interaction checks remain UI-test acceptance.
struct FleetSensitiveValueTests {
    private let secret = "192.168.50.123"

    @Test func startsMaskedAndCannotCopyWithoutReveal() {
        let disclosure = FleetSensitiveValueDisclosure()
        var copied: [String] = []
        #expect(disclosure.visibleValue(for: secret, isActive: true) == nil)
        #expect(!disclosure.copy(secret, isActive: true) { copied.append($0) })
        #expect(copied.isEmpty)
    }

    @Test func revealingDoesNotCopyAndExplicitCopyWritesExactlyTheRevealedValue() {
        var disclosure = FleetSensitiveValueDisclosure()
        var copied: [String] = []
        disclosure.reveal(secret, isActive: true)
        #expect(copied.isEmpty)
        #expect(disclosure.visibleValue(for: secret, isActive: true) == secret)
        #expect(disclosure.copy(secret, isActive: true) { copied.append($0) })
        #expect(copied == [secret])
    }

    @Test func hiddenValueIsRemovedAndCopyAuthorizationIsRevoked() {
        var disclosure = FleetSensitiveValueDisclosure()
        disclosure.reveal(secret, isActive: true)
        disclosure.hide()
        disclosure.hide()
        #expect(disclosure == FleetSensitiveValueDisclosure())
        #expect(disclosure.visibleValue(for: secret, isActive: true) == nil)
        var writes = 0
        #expect(!disclosure.copy(secret, isActive: true) { _ in writes += 1 })
        #expect(writes == 0)
    }

    @Test func inactiveSceneCannotRevealDisplayOrCopyEvenBeforeLifecycleCallback() {
        var disclosure = FleetSensitiveValueDisclosure()
        disclosure.reveal(secret, isActive: false)
        #expect(disclosure.visibleValue(for: secret, isActive: true) == nil)
        disclosure.reveal(secret, isActive: true)
        #expect(disclosure.visibleValue(for: secret, isActive: false) == nil)
        var writes = 0
        #expect(!disclosure.copy(secret, isActive: false) { _ in writes += 1 })
        #expect(writes == 0)
        // The same hide invoked by inactive/disappear callbacks prevents reappearance on return.
        disclosure.hide()
        #expect(disclosure.visibleValue(for: secret, isActive: true) == nil)
    }

    @Test func reusingRowForAnotherValueCannotExposeOrCopyItBeforeOnChangeRuns() {
        var disclosure = FleetSensitiveValueDisclosure()
        disclosure.reveal(secret, isActive: true)
        let replacement = "10.42.0.99"
        #expect(disclosure.visibleValue(for: replacement, isActive: true) == nil)
        var copied: [String] = []
        #expect(!disclosure.copy(replacement, isActive: true) { copied.append($0) })
        #expect(copied.isEmpty)
        disclosure.hide()
        #expect(disclosure.visibleValue(for: secret, isActive: true) == nil)
    }

    @Test func emptyValuesNeverReplaceTheClipboard() {
        var disclosure = FleetSensitiveValueDisclosure()
        disclosure.reveal("", isActive: true)
        var writes = 0
        #expect(!disclosure.copy("", isActive: true) { _ in writes += 1 })
        #expect(writes == 0)
    }

    @Test func independentRowsDoNotShareRevealState() {
        var first = FleetSensitiveValueDisclosure()
        let second = FleetSensitiveValueDisclosure()
        first.reveal(secret, isActive: true)
        #expect(first.visibleValue(for: secret, isActive: true) == secret)
        #expect(second.visibleValue(for: secret, isActive: true) == nil)
    }
}
