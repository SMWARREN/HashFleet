import HashFleetCore
import Foundation

@main
struct HashFleetCLI {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard !arguments.contains("--help") && !arguments.contains("-h") else {
            printUsage()
            return
        }
        if arguments.first == "logo" {
            guard arguments.count == 1 else {
                fputs("hashfleet: logo takes no options or miner hosts.\n", stderr)
                exit(64)
            }
            DashboardBrand.printLogo()
            return
        }
        if arguments.first == "support" {
            printSupport(arguments)
            return
        }

        let options: CLIOptions
        do {
            options = try parse(arguments)
        } catch {
            fputs("hashfleet: \(error.localizedDescription)\n\n\(usageText)\n", stderr)
            exit(64)
        }

        if options.watch {
            guard TerminalSession.isInteractive else {
                fputs("hashfleet: the dashboard needs an interactive terminal. Use 'hashfleet status' or 'hashfleet status --json' for redirected output.\n", stderr)
                exit(64)
            }
            do {
                try await FleetDashboard(options: options).run()
            } catch {
                fputs("hashfleet: \(error.localizedDescription)\n", stderr)
                exit(EXIT_FAILURE)
            }
            return
        }

        let json = options.json
        let explicitAddresses = options.addresses
        let devices = explicitAddresses.map { MinerDevice(name: $0, address: $0) }
        let configuredState: FleetSharedStore.DevicesReadState = explicitAddresses.isEmpty
            ? FleetSharedStore.readDevicesState()
            : .unconfigured
        if case .unavailable = configuredState {
            fputs("hashfleet: the configured fleet store is unavailable or corrupt; refusing local discovery.\n", stderr)
            exit(EXIT_FAILURE)
        }
        let configuredDevices: [MinerDevice]
        if case .configured(let devices) = configuredState {
            configuredDevices = devices
        } else {
            configuredDevices = []
        }
        let fleet: FleetStatusSnapshot
        let usedDiscovery = devices.isEmpty && configuredState == .unconfigured
        if usedDiscovery {
            let candidates = await FleetNetworkDiscovery.scanCurrent()
            fleet = FleetStatusSnapshot(
                miners: candidates.map {
                    MinerStatusSnapshot(device: $0.device, info: $0.info)
                }
            )
        } else {
            let selectedDevices = devices.isEmpty ? configuredDevices : devices
            fleet = await FleetStatusService.read(
                devices: selectedDevices,
                xmrigBearerToken: ProcessInfo.processInfo.environment["XMRIG_TOKEN"]
            )
        }
        let outputFleet = sanitizedOutput(fleet)
        if json {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            do {
                guard let output = String(data: try encoder.encode(outputFleet), encoding: .utf8) else {
                    fputs("hashfleet: could not encode status as UTF-8.\n", stderr)
                    exit(EXIT_FAILURE)
                }
                print(output)
            } catch {
                fputs("hashfleet: could not encode status: \(error.localizedDescription)\n", stderr)
                exit(EXIT_FAILURE)
            }
        } else {
            printTable(outputFleet, searchedLocally: usedDiscovery, details: options.details)
        }

        if fleet.offlineCount > 0 { exit(EXIT_FAILURE) }
    }

    private static func printSupport(_ arguments: [String]) {
        guard arguments.count == 1 else {
            fputs("hashfleet: support takes no options or miner hosts.\n", stderr)
            exit(64)
        }
        guard DeveloperSupport.current.paypalURL != nil else {
            fputs("hashfleet: developer support checkout is not configured in this build.\n", stderr)
            exit(69)
        }
        print(DeveloperSupport.title)
        CLISupportContent.lines.forEach { print($0) }
        print("No browser was opened and no payment or miner request was sent.")
    }

    private static func printUsage() {
        print(usageText)
    }

    static var usageText: String {
        """
        HASH FLEET — your fleet, live in the terminal

        Usage: hashfleet [watch] [--interval <seconds>] [--details] [<miner-host> ...]
               hashfleet status [--json | --details] [<miner-host> ...]
               hashfleet settings [<miner-host>]
               hashfleet logo
               hashfleet support
               hashfleet watch --demo

        With no command, opens the live dashboard in an interactive terminal.
        Redirected output defaults to a single status snapshot.
        Status uses a logo and colors in terminals; NO_COLOR disables styling. Pipes and JSON stay plain.
        logo prints the Hash Fleet logo without contacting any miners.
        support prints PayPal and crypto support destinations without contacting miners or opening a browser.
        Dashboard: arrows/j/k select · d details · e settings · r refresh · space pause · s sort · l logo · q quit
        Shift+S opens Support Hash Fleet inside the dashboard, including PayPal and BTC/ETH/SOL mainnet addresses.
        Support: arrows/j/k scroll · g/G top/end · S/b/Esc return · q quit. No browser, wallet or payment is opened.
        Miner page: 1–4/Tab section · arrows/j/k scroll · left/right miner · d/Esc back
        --interval sets the wait between polls (5–3600 seconds; default 5).
        --demo previews the dashboard with labeled sample data and no network access.
        Settings: 1–5/Tab section · Enter edit · r review · type APPLY then Enter to save.
        Pools: [/] select configured slot · edit host, port, worker, password, protocol and pool roles.
        Settings changes target only the selected miner and are checked with fresh readback.

        Read-only status for explicit hosts, the fleet configured in Hash Fleet, or a bounded
        local-network discovery when no fleet is configured.
        Text includes all-time and session-best share difficulty, not solved-block claims.
        --details adds mining, cooling, hardware and pool information. Pool notices appear only when reported.
        --json keeps the existing complete raw status schema. Missing readings remain unavailable.
        Examples:
          hashfleet status 192.0.2.215
          hashfleet status --details gamma.local
          hashfleet status --json gamma.local 192.0.2.221
          hashfleet status
        """
    }

    struct CLIOptions {
        let json: Bool
        let details: Bool
        let addresses: [String]
        let watch: Bool
        let interval: TimeInterval
        let demo: Bool
        let settings: Bool
    }

    private enum CLIError: LocalizedError {
        case invalidUsage(String)

        var errorDescription: String? {
            switch self {
            case .invalidUsage(let message): return message
            }
        }
    }

    private static func parse(_ arguments: [String]) throws -> CLIOptions {
        var tokens = arguments
        let command = ["status", "watch", "settings"].contains(tokens.first ?? "") ? tokens.first : nil
        if command != nil {
            tokens.removeFirst()
        }

        var state = ParseState()
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            index += 1
            try consume(token, tokens: tokens, index: &index, state: &state)
        }
        return try makeOptions(command: command, state: state)
    }

    private struct ParseState {
        var json = false
        var details = false
        var demo = false
        var interval: TimeInterval?
        var addresses: [String] = []
    }

    private static func consume(_ token: String, tokens: [String], index: inout Int, state: inout ParseState) throws {
        switch token {
        case "--json":
            guard !state.json else { throw CLIError.invalidUsage("--json may be supplied only once.") }
            state.json = true
        case "--details":
            guard !state.details else { throw CLIError.invalidUsage("--details may be supplied only once.") }
            state.details = true
        case "--demo":
            guard !state.demo else { throw CLIError.invalidUsage("--demo may be supplied only once.") }
            state.demo = true
        case "--interval":
            guard state.interval == nil, index < tokens.count,
                let value = Double(tokens[index]), value.isFinite, (5...3600).contains(value)
            else { throw CLIError.invalidUsage("--interval requires a number from 5 to 3600 seconds, supplied once.") }
            state.interval = value
            index += 1
        case "status", "watch", "settings":
            throw CLIError.invalidUsage("\(token) must be the first command word.")
        default:
            if token.hasPrefix("-") {
                throw CLIError.invalidUsage("unknown option '\(token)'.")
            }
            guard looksLikeHost(token) else {
                throw CLIError.invalidUsage("unknown command or host '\(token)'.")
            }
            state.addresses.append(token)
        }
    }

    private static func makeOptions(command: String?, state: ParseState) throws -> CLIOptions {
        let json = state.json
        let demo = state.demo
        let addresses = state.addresses
        guard !json || !state.details else { throw CLIError.invalidUsage("--json and --details are alternative output formats.") }
        let watch = command == "watch" || command == "settings" || (command == nil && !json && TerminalSession.isInteractive)
        guard !watch || !json else { throw CLIError.invalidUsage("--json is available with status, not watch.") }
        guard watch || (!demo && state.interval == nil) else {
            throw CLIError.invalidUsage("--demo and --interval require the live dashboard ('hashfleet watch').")
        }
        guard !demo || addresses.isEmpty else { throw CLIError.invalidUsage("--demo cannot be combined with miner hosts.") }
        guard command != "settings" || addresses.count <= 1 else {
            throw CLIError.invalidUsage("settings accepts one miner host. Select other miners in the dashboard.")
        }
        return CLIOptions(
            json: json, details: state.details, addresses: addresses, watch: watch,
            interval: state.interval ?? 5, demo: demo, settings: command == "settings"
        )
    }

    private static func looksLikeHost(_ value: String) -> Bool {
        !value.isEmpty && (value.contains(".") || value.contains(":") || value == "localhost")
    }

    /// Keep remote error bodies useful without allowing a miner to inject terminal controls,
    /// additional rows, or an unbounded log payload into CLI output. The core error retains the
    /// original response body for structured diagnostics.
    private static func sanitizedOutput(_ fleet: FleetStatusSnapshot) -> FleetStatusSnapshot {
        FleetStatusSnapshot(
            observedAt: fleet.observedAt,
            miners: fleet.miners.map { miner in
                MinerStatusSnapshot(
                    device: miner.device,
                    observedAt: miner.observedAt,
                    info: miner.info,
                    error: sanitizedError(miner.error)
                )
            }
        )
    }

    private static func sanitizedError(_ error: String?) -> String? {
        guard let error else { return nil }
        var flattened = ""
        flattened.reserveCapacity(min(error.utf8.count, 256))
        for scalar in error.unicodeScalars {
            if scalar.value < 0x20 || scalar.value == 0x7F {
                flattened.append(" ")
            } else {
                flattened.unicodeScalars.append(scalar)
            }
        }
        let collapsed = flattened.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        let bounded = String(collapsed.prefix(240))
        return bounded.isEmpty ? "unreachable" : bounded
    }

    private static func printTable(_ fleet: FleetStatusSnapshot, searchedLocally: Bool, details: Bool) {
        if TerminalSession.hasTerminalOutput {
            FleetStatusPrinter.print(fleet, searchedLocally: searchedLocally, details: details)
            return
        }
        if searchedLocally && fleet.miners.isEmpty {
            print("HashFleet status · no miners found on the local network")
            print("The read-only scan checked the active private IPv4 network and found no compatible devices.")
            return
        }
        print("HashFleet status · \(fleet.onlineCount)/\(fleet.miners.count) online")
        print("NAME                 HOST                         HASHRATE       TEMP       POWER      BEST (ALL)     BEST (SESSION)   STATE")
        print("──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────")
        for miner in fleet.miners {
            let rate = miner.hashrate.map { FleetFormat.hashrateWithUnit($0) } ?? "--"
            let temp = miner.temperatureCelsius.map { "\(FleetFormat.number($0, decimals: 1)) °C" } ?? "--"
            let power = miner.powerWatts.map { "\(FleetFormat.number($0, decimals: 1)) W" } ?? "--"
            let state = miner.isOnline ? "ONLINE" : "OFFLINE: \(miner.error ?? "unreachable")"
            let name = miner.name.padding(toLength: 20, withPad: " ", startingAt: 0)
            let host = miner.address.padding(toLength: 28, withPad: " ", startingAt: 0)
            let paddedRate = rate.padding(toLength: 14, withPad: " ", startingAt: 0)
            let paddedTemp = temp.padding(toLength: 10, withPad: " ", startingAt: 0)
            let paddedPower = power.padding(toLength: 10, withPad: " ", startingAt: 0)
            let allTime = difficulty(miner.info?.bestDiff).padding(toLength: 14, withPad: " ", startingAt: 0)
            let session = difficulty(miner.info?.bestSessionDiff).padding(toLength: 16, withPad: " ", startingAt: 0)
            print("\(name) \(host) \(paddedRate) \(paddedTemp) \(paddedPower) \(allTime) \(session) \(state)")
            if details, miner.isOnline { printDetails(miner) }
        }
    }

    private static func printDetails(_ miner: MinerStatusSnapshot) {
        let palette = DashboardPalette(environment: ["NO_COLOR": "1"])
        for section in MinerDetailSection.allCases {
            for line in MinerDetails.lines(for: miner, section: section, width: 120, palette: palette) {
                print(TerminalText.safe(line.runs.map(\.text).joined()).trimmingCharacters(in: .whitespaces))
            }
        }
    }

    static func difficulty(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty, raw.count <= 128 else { return "--" }
        let suffixes: [Character: Double] = ["K": 1e3, "M": 1e6, "G": 1e9, "T": 1e12, "P": 1e15, "E": 1e18]
        var numeric = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var multiplier = 1.0
        if let last = numeric.uppercased().last, let scale = suffixes[last] {
            multiplier = scale
            numeric.removeLast()
        }
        guard let base = Double(numeric), base.isFinite, base >= 0 else { return "--" }
        let value = base * multiplier
        guard value.isFinite else { return "--" }
        for (scale, suffix) in [(1e18, "E"), (1e15, "P"), (1e12, "T"), (1e9, "G"), (1e6, "M"), (1e3, "K")] where value >= scale {
            return FleetFormat.number(value / scale, decimals: 2) + suffix
        }
        return FleetFormat.number(value, decimals: 2)
    }
}
