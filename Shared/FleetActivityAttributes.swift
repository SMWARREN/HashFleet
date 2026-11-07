import ActivityKit
import Foundation

struct FleetActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var glance: FleetGlance
    }
    var name: String
    // Optional for decoding activities created by earlier builds. No addresses or identity pins
    // belong in ActivityKit attributes. Legacy activities require an explicit restart to bind.
    var refreshGeneration: UUID?
}
