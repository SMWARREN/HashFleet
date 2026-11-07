import SwiftUI

struct WatchHelpView: View {
    var body: some View {
        List {
            Section("Phone off? Still works.") {
                Text("This Watch saves its own miner list and reads miners directly. Your iPhone is not needed after setup.")
                Text("Connect the Watch to the miners’ Wi-Fi network. Cellular alone cannot reach private home-network addresses.")
            }
            Section("Updates and saved readings") {
                Text("Readings refresh on open, about every 10 seconds after each finished pass while this app is active, or when you tap Refresh. Updates stop when you leave the app.")
                Text("After one minute, saved readings are marked stale. If a read fails, its original observation time is kept. Can't reach does not prove a miner is offline.")
            }
            Section("Setup and privacy") {
                Text("An empty Watch looks for compatible AxeOS miners on its Wi-Fi and saves those it finds. Scan for miners retries the search. Add miner is a manual fallback, or import a list from the iPhone app’s Apple Watch settings.")
                Text("Search checks one local IPv4 address block on standard HTTP port 80. Miners on other subnets, custom ports or protected endpoints may need manual setup. Search runs only while this app is active.")
                Text("This is a read-only monitor. It never changes miner settings. Removing an entry only changes this Watch’s saved list.")
            }
        }
        .font(.footnote)
        .navigationTitle("Connection & help")
        .accessibilityIdentifier("watch.help.page")
    }
}
