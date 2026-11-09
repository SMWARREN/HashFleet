import AppKit
import Testing
@testable import HashFleetMac

@Suite("Native macOS asset catalog loading")
struct FleetNativeAssetTests {
    @Test(arguments: [
        "MinerCoolingArt",
        "FleetClusterArt",
        "BitsyCelebrate",
        "BitsyThinking",
        "BitsyIdle",
        "BitsyWave",
        "BitsyWorried",
        "BitsyParty",
        "BitsySleepy"
    ])
    func loadsPreviouslyThreeXOnlyArtwork(name: String) {
        let image = NSImage(named: NSImage.Name(name))
        #expect(image != nil, "Expected the native app asset catalog to load \(name)")
        #expect((image?.size.width ?? 0) > 0)
        #expect((image?.size.height ?? 0) > 0)
    }
}
