import Foundation
import Network
import Testing
@testable import HashFleetMac

@Suite("Local network approval")
@MainActor
struct LocalNetworkAuthorizationTests {
    @Test func savedApprovalDoesNotAuthorizeANewSession() {
        let suite = "LocalNetworkAuthorizationTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: LocalNetworkAuthorization.grantedKey)
        let authorization = LocalNetworkAuthorization(defaults: defaults)
        #expect(authorization.status == .notRequested)
        #expect(!authorization.isGranted)
        #expect(defaults.object(forKey: LocalNetworkAuthorization.grantedKey) == nil)
    }

    @Test func repeatedConstructionOnlyRemovesAnExistingLegacyFlagOnce() {
        let suite = "LocalNetworkAuthorizationTests-" + UUID().uuidString
        let defaults = AuthorizationDefaultsSpy(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        for _ in 0..<50 {
            #expect(!LocalNetworkAuthorization(defaults: defaults).isGranted)
        }
        #expect(defaults.removalCount == 0)

        defaults.set(true, forKey: LocalNetworkAuthorization.grantedKey)
        for _ in 0..<50 {
            #expect(!LocalNetworkAuthorization(defaults: defaults).isGranted)
        }
        #expect(defaults.removalCount == 1)
        #expect(defaults.object(forKey: LocalNetworkAuthorization.grantedKey) == nil)
    }

    @Test func denialAndCancelNeverGrantAccess() {
        let suite = "LocalNetworkAuthorizationTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let authorization = LocalNetworkAuthorization(defaults: defaults)
        authorization.markDenied()
        #expect(authorization.status == .denied)
        #expect(!authorization.isGranted)
        authorization.cancel()
        #expect(authorization.status == .notRequested)
        #expect(!authorization.isGranted)
    }

    @Test func onlyPolicyDeniedIsClassifiedAsPrivacyDenial() {
        #expect(LocalNetworkAuthorization.isPolicyDenied(.dns(-65570)))
        #expect(!LocalNetworkAuthorization.isPolicyDenied(.dns(-65537)))
        #expect(!LocalNetworkAuthorization.isPolicyDenied(.posix(.ENETDOWN)))
    }
}

private final class AuthorizationDefaultsSpy: UserDefaults, @unchecked Sendable {
    private let removalLock = NSLock()
    private var removals = 0

    var removalCount: Int {
        removalLock.lock()
        defer { removalLock.unlock() }
        return removals
    }

    override func removeObject(forKey defaultName: String) {
        removalLock.lock()
        removals += 1
        removalLock.unlock()
        super.removeObject(forKey: defaultName)
    }
}
