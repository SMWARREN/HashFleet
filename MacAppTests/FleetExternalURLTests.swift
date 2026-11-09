import Dispatch
import Foundation
import SwiftUI
import Testing
@testable import HashFleetMac

@Suite("External URL completion isolation")
@MainActor
struct FleetExternalURLTests {
    @Test(arguments: [true, false])
    func backgroundCompletionReturnsToMainActor(accepted: Bool) async {
        let result = await FleetExternalURL.result { completion in
            DispatchQueue.global(qos: .userInitiated).async {
                dispatchPrecondition(condition: .notOnQueue(.main))
                completion(accepted)
            }
        }
        MainActor.assertIsolated()
        #expect(result == accepted)
    }

    @Test(arguments: [true, false])
    func synchronousCompletionIsNotLost(accepted: Bool) async {
        let result = await FleetExternalURL.result { completion in
            completion(accepted)
        }
        MainActor.assertIsolated()
        #expect(result == accepted)
    }

    @Test(arguments: [true, false])
    func openURLActionPreservesAcceptanceWithoutOpeningABrowser(accepted: Bool) async throws {
        let url = try #require(URL(string: "https://example.com/support-test"))
        var requestedURL: URL?
        let action = OpenURLAction { requested in
            requestedURL = requested
            return accepted ? .handled : .discarded
        }
        let result = await FleetExternalURL.open(url, using: action)
        MainActor.assertIsolated()
        #expect(requestedURL == url)
        #expect(result == accepted)
    }
}
