# SwiftPort audit: Hash Fleet for Mac

## A. Executive summary

**Already there:** A native Mac desktop app with a fleet dashboard, miner detail and settings, history, reporting, a menu-bar item, and an offline demo. The repo also has Swift models, telemetry parsing and math, an API client, storage, and Mac build and packaging workflows.

**Not there:** A Windows app target, a Hash Fleet compatibility layer, Windows implementations of the Mac-only services, or a verified Windows executable. Upstream libraries supply useful pieces, not a Windows version of Hash Fleet.

**Decision:** Hash Fleet for Windows is the first SwiftPort deliverable. Reuse the Mac app's Swift source through a compatibility layer. Do not start the port until the current Hash Fleet work is finished and the operator explicitly resumes it. See the [desktop compatibility decision](HASHFLEET-WINDOWS-COMPATIBILITY.md).

Scope: static review on November 22, 2026 of the stable Hash Fleet checkout at `42aa25e`. The iPhone, Watch, standalone companion, CLI, website, and server are not port targets in this audit. Shared files are included only where the Mac app uses them. No build, install, runtime test, or fleet request was performed.

## B. Current inventory

| Area | What Hash Fleet already has | What it does not have |
|---|---|---|
| Native desktop app | `HashFleetMac` builds SwiftUI/AppKit code from `MacApp/`, selected `App/` and `Shared/` sources, and `HashFleetCore`. The tracked target has 259 source and 5 resource build-phase references. [XcodeGen definition](../project.yml#L91) · [project](../HashFleet.xcodeproj/project.pbxproj) | A corresponding Windows target, entry point, dependency lock, or native runtime. |
| Dashboard and miner workflows | Split sidebar and dashboard, miner detail and settings, plus routes for network, energy, monitoring, reports, backup, and preferences. [Desktop routes and miner rows](../App/Features/Dashboard/DashboardView+WideLayout.swift#L40) · [split navigation](../App/Features/Dashboard/FleetSplitView.swift#L34) · [miner detail](../App/Features/Miner/MinerDetailView.swift) | Windows rendering, navigation or settings behavior for those same screens. |
| Fleet logic and data | Swift models and parsing, hashrate formatting, mining calculations, an injectable `URLSession` miner client, and a GRDB/SQLite telemetry store. [Core manifest](../Package.swift) · [API client](../Sources/HashFleetCore/MinerAPIClient.swift#L50) · [database](../Sources/HashFleetCore/Database/MinerTelemetryDatabase.swift#L103) | A Windows-verified core build, transport, or storage path. Existing implementations are not evidence they work on Windows. |
| Desktop integration | A native window, application delegate, command menus, and built-in `NSStatusBar` item. [Mac window](../MacApp/HashFleetMacApp.swift#L48) · [status item](../MacApp/FleetMacStatusItem.swift#L48) | Windows equivalents for app/window lifecycle, tray, menus, and platform services. |
| Offline data, tests, and distribution | Sample miner snapshots, mock API transport, Mac demo-isolation and layout tests, macOS CI, and `.app`, `.zip`, and `.pkg` packaging. [Demo data](../App/Store/DemoFleet.swift#L57) · [mock transport](../Tests/HashFleetCoreTests/MockTransport.swift) · [Mac tests](../MacAppTests/) · [CI](../.github/workflows/ci.yml) · [Mac distribution](MAC-DISTRIBUTION.md) | Windows build CI, accessibility/runtime coverage, staging of Windows resources and runtime dependencies, or a clean-machine `.exe` launch receipt. |
| Porting tooling | `project.yml` and a checked-in Xcode project already identify the Mac target. | No general Xcode importer, source converter, or SwiftUI shim found in this checkout. A general converter is deferred, not a dependency of Hash Fleet for Windows. |

## C. Compatibility matrix

The status describes the path to reuse, not features already working on Windows.

| Capability | Status | Evidence and needed work |
|---|---|---|
| Plain Swift logic | Candidate for unchanged reuse | `JSONValue`, `MinerInfo`, `MinerDevice`, `HashrateUnit`, and `MiningInsightsMath` in [`HashFleetCore`](../Sources/HashFleetCore/). Verify the dependency closure and compile it on Windows. Do not label the whole target portable. |
| Basic views, inputs, and state | Partial, needs a shim | `MinerSidebarRow`, text fields, pickers, and toggles are already declared in Swift. Retain their shared view code where the compatibility layer can map layout, bindings, focus, and accessibility. [Sidebar row](../App/Features/Dashboard/DashboardView+WideLayout.swift#L71) · [settings controls](../App/Features/Miner/MinerSettingsView+Pages.swift) |
| Navigation, dialogs, and styling | Partial, needs a shim or adapter | Preserve route, selection, and dialog intent. Implement split navigation, sheets, window focus, and theme/resource mapping where platform primitives differ. [Split view](../App/Features/Dashboard/FleetSplitView.swift#L45) |
| Charts, PDF, icons, and window chrome | Apple implementations cannot carry over as-is | Keep chart series and report data, not Swift Charts or PDFKit rendering. Map SF Symbols and asset catalogs to supported Windows assets. Replace AppKit window chrome in the host. [Chart](../App/Features/Dashboard/FleetHistoryCard+Chart.swift) · [PDF](../App/Features/Reports/FleetReportPDFPreview.swift) · [window chrome](../MacApp/FleetMacChrome.swift) |
| Storage and security services | Windows support unknown or missing | Pinned GRDB `7.11.1` Windows behavior is unverified. Keychain (`Security`), notifications (`UserNotifications`), and `CryptoKit` address validation need a supported dependency or a platform adapter. Pinned LucideSwift `0.9.24` documents Apple platforms. [Pins](../HashFleet.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved) · [credentials](../App/Store/MinerCredentialStore.swift) · [notifications](../App/Store/FleetLocalNotifications.swift) · [validation](../Sources/HashFleetCore/CryptoAddressValidator.swift) |
| Network discovery and commands | Missing on Windows or unverified | The current non-Darwin discovery path supplies no local IPv4 address. Transport compatibility is separate from discovery, capability checks, and write safety. Test against fixtures or a mock first. [Discovery](../Sources/HashFleetCore/FleetNetworkDiscovery.swift#L69) · [transport](../Sources/HashFleetCore/MinerAPIClient.swift) |

## D. Reuse in this order

1. Models, parsing, formats, and math, with existing unit tests. Verify missing readings remain missing and units agree across platforms.
2. The actual Mac dashboard and miner views, including their presentation and routing logic. Share their source files, not screenshots or a second implementation. Keep unsupported framework calls behind the compatibility boundary.
3. Existing offline fixtures and Mac tests as the baseline for Windows behavior. Reuse the test scenarios even where macOS UI test code cannot run on Windows.
4. API contracts and storage schema after their Windows implementations pass OS-specific tests. No blanket reuse claim for the whole app store or core target.

## E. What the external projects already provide

| Project | Already provides | Does not provide for Hash Fleet |
|---|---|---|
| [SwiftCrossUI](https://github.com/moreSwift/swift-cross-ui) | SwiftUI-style primitives and a native WinUI backend. | Apple's exact APIs or behavior, Mac-specific services, or proven Hash Fleet accessibility. An [upstream UI Automation crash report](https://github.com/moreSwift/swift-cross-ui/issues/787) on a particular dependency stack makes keyboard and Narrator tests essential. |
| [SwiftOpenUI](https://github.com/codelynx/SwiftOpenUI) | A SwiftUI-like source compatibility layer with Windows Win32 and Direct2D rendering. | A WinUI 3 backend or demonstrated parity with Hash Fleet's screens. It is a fallback to assess, not an automatic substitution. |
| [OpenSwiftUI](https://github.com/OpenSwiftUIProject/OpenSwiftUI) | A SwiftUI reimplementation project. | Windows build, test, and deployment support, which its published platform matrix lists as unsupported. |
| [Swift/Win32](https://github.com/compnerd/swift-win32) and [Swift/WinRT](https://github.com/thebrowsercompany/swift-winrt) | Native Windows API wrappers or generated WinRT bindings. | A SwiftUI-compatible desktop app. Swift/Win32 documents incomplete APIs. Swift/WinRT is interop, not a renderer. |
| [XcodeProj](https://github.com/tuist/XcodeProj) and [SwiftSyntax](https://github.com/swiftlang/swift-syntax) | Xcode metadata reading and Swift source parsing. | A semantic compiler check, a finished compatibility layer, or a native Windows app. Not needed to begin the Hash Fleet-first path. |
| [Swift Bundler](https://swiftbundler.dev/) | Packaging tooling above SwiftPM with documented Windows support. | A validated Hash Fleet bundle or proof it runs cleanly with the required runtime. |

None is integrated into the audited app. Dependency behavior, asset redistribution and notices, and the repo's [GPL-3.0 license](../LICENSE) need checking before distribution.

## F. Architecture recommendation

Keep the existing native macOS host and one set of Swift screen, presentation, and domain files. Put the compatibility layer between the shared screens and each OS's native UI and services. Add a separate Windows entry/build path that uses those same source files. A Mac `.app` binary and Apple-specific framework code do not run unchanged on Windows. The [decision record](HASHFLEET-WINDOWS-COMPATIBILITY.md) defines the boundary and acceptance gate.

## G. Deferred plan

| Stage | Scope and dependency | Acceptance |
|---|---|---|
| First validation checkpoint (M) | Only after the operator authorizes a start. Use a supported Windows toolchain and adapt a real Mac dashboard component with existing offline data. | Both targets compile the same Swift component source. Windows renders native UI, supports keyboard and Narrator, and makes no fleet requests. Mac behavior is unchanged. A checkpoint is not product delivery. |
| First product (L) | Expand to the existing Mac desktop dashboard, miner detail, and agreed Windows workflows. Finish the platform adapters and packaging. | Demonstrate the agreed flows from a packaged Windows executable on a clean machine, including fixtures and safe read-only behavior. List anything still unavailable. |
| Later extensions (L) | Broaden parity as required. Revisit a general-purpose converter only if the operator wants one. | Feature-by-feature acceptance. No assumed Windows parity for the system tray, PDF, device writes, or advanced discovery. |

Effort labels are relative planning estimates, not an authorization or a delivery promise.

## H. Verification when authorized

Use the existing unsigned Mac build and core test commands in [PUBLIC-BUILD.md](PUBLIC-BUILD.md). For the future Windows target, record the pinned [Swift and Windows toolchain](https://www.swift.org/install/windows/) and applicable [Windows App SDK runtime](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/deploy-unpackaged-apps). Proposed commands in the future Windows package directory: `swift --version`, `swift test`, and `swift build -c release --product HashFleetWindows`. That product name is proposed, not present. Check shared source membership, then launch the staged executable on a clean Windows machine. Exercise focus, text entry, selection, split layout, resizing, Narrator, missing data, and local-only fixtures. A successful compile alone does not pass.

## I. Open decisions for later

- Which existing Mac workflows beyond dashboard and detail are required for the first Windows release?
- If WinUI cannot meet the source-reuse or accessibility gate, is a native Win32 fallback acceptable?
