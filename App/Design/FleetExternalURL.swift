import SwiftUI

/// LaunchServices may deliver its completion on a background queue. The completion
/// must be Sendable and touch only the continuation, never SwiftUI state. Awaiting
/// callers resume on their actor before handling success or presenting an error.
@MainActor
enum FleetExternalURL {
    static func open(_ url: URL, using action: OpenURLAction) async -> Bool {
        await result { completion in
            action(url, completion: completion)
        }
    }

    static func result(
        from launch: (@escaping @Sendable (Bool) -> Void) -> Void
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            launch { @Sendable accepted in
                continuation.resume(returning: accepted)
            }
        }
    }
}
