# HashFleet

**Your hash. Your hardware.**

Native apps and a terminal dashboard for monitoring your mining fleet. Built for macOS, iPhone, iPad, and Apple Watch, with support for miners running ESP-Miner / AxeOS.

[Website](https://hashfleet.app) · [Downloads](https://github.com/SMWARREN/hashfleet/releases/latest) · [Documentation](docs/README.md) · [Build from source](docs/PUBLIC-BUILD.md)

## Install

The **Mac app** and **CLI** are separate downloads. Choose either or both.
Current binaries support **Apple Silicon Macs running macOS 14 or later** and are Developer ID signed and Apple-notarized.

After the [one-time Homebrew setup](docs/HOMEBREW.md):

```sh
# Native Mac app
brew install --cask hashfleet

# Standalone terminal dashboard
brew install hashfleet-cli
```

Prefer a direct download? Get the Mac ZIP or CLI archive from [GitHub Releases](https://github.com/SMWARREN/hashfleet/releases/latest). Installing one does not install the other.

## Your fleet, at a glance

- Monitor hashrate, temperatures, power, fans, shares, and connection status.
- View trends and inspect individual miners in native interfaces.
- Keep your fleet close with the Mac menu bar, widgets, and Apple Watch.
- Review settings, cooling, and pool changes before sending them to a miner.
- Explore a clearly labeled demo without connecting to hardware.

No HashFleet account is required. Fleet configuration stays on your device. Optional public chain and pool services can be disabled in settings. See the [privacy policy](PRIVACY.md).

### Try the CLI demo

```sh
hashfleet watch --demo
```

The demo uses sample data and does not contact miners. See the [terminal guide](docs/CLI.md) for commands, navigation, and reviewed settings changes.

## Build from source

Open `HashFleet.xcodeproj` in Xcode. Use **HashFleetMac** for macOS or **HashFleet** for iOS. Personal-device builds need your own signing team and matching app/extension identifiers.

The [build guide](docs/PUBLIC-BUILD.md) covers SDK requirements, unsigned simulator and Mac builds, signing, and optional integrations. No original developer credentials are required for demo or simulator builds.

## Safety and compatibility

Keep miners on a trusted local network. Firmware capabilities vary by board and version. Device-changing operations require confirmation, and incorrect voltage, cooling, or firmware changes can damage hardware.

Read the [API reference](docs/API-COVERAGE.md) and [model compatibility guide](docs/MODEL-CAPABILITY-MATRIX.md) before using advanced controls. Background updates on Apple platforms are system-controlled, not continuous monitoring.

## Project structure

| Directory | Purpose |
| --- | --- |
| `App/`, `MacApp/`, `WatchApp/` | Native application interfaces |
| `Sources/` | Shared core library and terminal CLI |
| `Shared/`, `Widgets/` | Shared models, widgets, and Live Activities |
| `AppTests/`, `MacAppTests/`, `Tests/`, `UITests/` | Automated test sources |
| `website/` | Product website |
| `Server/` | Optional server integration |
| `Scripts/`, `Tools/` | Development and packaging tools |
| `docs/` | Setup, usage, and technical reference |

## Contributing

See [Contributing](CONTRIBUTING.md), [Security](SECURITY.md), and [release status](docs/STATUS.md).

## License

[GPL-3.0](LICENSE). HashFleet is an independent community project and is not affiliated with or endorsed by Bitaxe, ESP-Miner, or OSMU.
