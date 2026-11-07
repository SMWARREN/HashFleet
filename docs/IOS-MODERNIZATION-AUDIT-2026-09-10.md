# HashFleet iOS Platform Modernization Audit (2026-09-10)

## 1. Toolchain, SDK, and Hardware Baseline
- **Installed Toolchain**: Xcode 26.6 (Build 17F113), Apple Swift 6.3.3 (`SWIFT_VERSION: "6.0"`).
- **Installed SDK**: iOS SDK 26.5 (`iPhoneOS26.5.sdk` / `iPhoneSimulator26.5.sdk`).
- **Target Deployment Minimum**: iOS 17.0 (`project.yml`, `Package.swift`). Post-iOS 17 features require explicit `@available` availability guards matching the verified SDK declaration (iOS 18.0, 26.0).
- **Evaluation Hardware**: Paired iPhone 14 Pro Max (A16 Bionic). Cannot run on-device Foundation Models or Apple Intelligence (requires A17 Pro or M-series).
- **Safety Invariant**: New system entry points never mutate hardware (restart, frequency, voltage, pool config). Existing in-app reviewed controls remain unchanged.
- **Brand Invariant**: Preserves graphite palette (`#21201E`, `#111111`), orange accent (`#E9931E`, `#8A5000`), Solo card graphite `#21201E`, and fixed black logo-only splash. FPS monitoring remains disabled by default.

## 2. Existing Platform Features in Codebase
| Feature | Files | Status | Notes |
|---|---|---|---|
| **Swift Observation (`@Observable`)** | `FleetStore.swift`, `FleetGlanceCoordinator.swift` | Implemented | Swift macro data flow (iOS 17.0+). |
| **Live Activities & Dynamic Island** | `Widgets/FleetLiveActivityWidget.swift` | Implemented | `ActivityConfiguration` for Lock Screen and Island. Dark styling. |
| **WidgetKit Multi-Family** | `Widgets/FleetWidget.swift`, `FleetWidgetTheme.swift` | Implemented | `.systemSmall`, `.systemMedium`, accessory inline/circular/rect. |
| **Swift Charts** | `FleetHistoryCard.swift` | Implemented | `LineMark`, `PointMark`, session history bounded to 360 points. |
| **Transitions & Sensory Feedback** | `FleetTheme.swift`, `DashboardView.swift` | Implemented | `.contentTransition(.numericText())`, `.sensoryFeedback(.success)`. |
| **Frame Cadence Diagnostics** | `FleetPerformanceMonitor.swift` | Implemented | `CADisplayLink` runloop cadence only; disabled by default. |
| **Background Refresh** | `HashFleetApp.swift` (`FleetBackgroundRefresh`) | Implemented | `BGAppRefreshTask` (`app.hashfleet.widget-refresh`), registration-checked. |
| **Privacy Redaction** | `FleetWidgetTheme.swift` (`FleetWidgetPrivacy`) | Implemented | `.privacySensitive()`, masks values on locked devices. |

## 3. Evaluated Candidates & Fit Matrix
| ID | Candidate Feature | Availability | Fit | Apple Reference / Contract Scope |
|---|---|---|---|---|
| **REC-01** | Read-Only App Intents & Shortcuts | iOS 17.0+ | **High** | [App Intents](https://developer.apple.com/documentation/appintents). Read from `FleetGlanceStorage`, check sharing opt-in and stale state, route `hashfleet://fleet`. |
| **REC-02** | Control Center Widgets (`ControlWidget`) | iOS 18.0+ | **High** | [Control Center Controls](https://developer.apple.com/documentation/widgetkit/creating-controls-for-control-center). Read-only button to launch app or display status. Verified SDK availability: iOS 18.0+. |
| **REC-03** | WidgetKit Tinted Home Screen Mode | iOS 18.0+ | **High** | [Widget Accents](https://developer.apple.com/documentation/widgetkit). Add `.widgetAccentable()` and `@Environment(\.widgetRenderingMode)` to prevent muddy tinting. |
| **REC-04** | Swift Charts Selection (`chartXSelection`) | iOS 17.0+ | **High** | [Chart Selection](https://developer.apple.com/documentation/charts/chart/chartxselection(value:)). Scrubbing rule mark with date/hashrate callout; coordinate with TabView paging. |
| **REC-05** | Swift Charts Audio Graph | iOS 17.0+ | **Medium** | [AXChartDescriptor](https://developer.apple.com/documentation/accessibility/axchartdescriptor). Accessibility rotor support for audio scrubbing hashrate history. |
| **REC-06** | Native Glass Button Styles (`.glass`, `.glassProminent`) | iOS 26.0+ | **Medium** | SDK interface verification: `.buttonStyle(.glass)` is `@available(iOS 26.0, *)`. System navigation already uses material glass; apply `.glass` to deliberate OpenFleet action only with Reduce Transparency and pre-iOS 26 fallback. |
| **REC-07** | Navigation Zoom Transition | iOS 18.0+ | **Medium** | [Navigation Transitions](https://developer.apple.com/documentation/swiftui/navigationtransition). Verified `@available(iOS 18.0, *)` in SDK. Card-to-detail zoom for miner cards. |
| **REC-08** | Sidebar-Adaptable Tab Hierarchy | iOS 18.0+ | **Medium** | [SwiftUI Tab API](https://developer.apple.com/documentation/swiftui/tab). Sidebar-adaptable tabs for iPadOS while retaining 3-tab bottom bar on iPhone. |
| **EXC-01** | On-Device Apple Intelligence / Foundation Models | Hardware | **Excluded** | Target iPhone 14 Pro Max lacks A17 Pro/M-series hardware required for local execution. |
| **EXC-02** | Remote Hardware Mutation Shortcuts | Contract | **Excluded** | Violates Core Contract (`docs/CORE-CONTRACT.md`). Writes require explicit user review. |
| **EXC-03** | Continuous Background Sockets / Push | Infrastructure| **Excluded** | No remote relay servers exist; violates local-first architecture. |

## 4. Implementation Guidelines & Invariants
1. **App Intents Architecture**: Must query `FleetGlanceStorage.shared.load()`, verify `sharesWithWidgets` is enabled, report honest stale messaging if older than 60 seconds, and never make network calls.
2. **Control Widgets**: Compile within `Widgets/` under `@available(iOS 18.0, *)`. Use native `OpenIntent` to foreground and route to Fleet. Ordinary widget links retain `hashfleet://fleet`. Do not pass custom schemes to `OpenURLIntent` controls.
3. **Materials and Glass**: Do not alter data card surfaces (Solo `#21201E`, miner cards `#F5F5F5` / `#21201E`). Native `.glass` button style is verified at `@available(iOS 26.0, *)` in SDK 26.5; must provide fallback for iOS 17-25 and `@Environment(\.accessibilityReduceTransparency)`.
4. **Availability Discipline**: Use verified SDK annotations (`@available(iOS 18.0, *)` for controls, zoom transitions, tabs; `@available(iOS 26.0, *)` for glass button styles).

## 5. Recommended Acceptance Checks
- **App Intents**: Verify summary sharing opt-in, device-authentication policy, reusable text result, honest stale notice and absence of networking. Verify pending navigation is consumed once.
- **Control Center**: Verify control builds under iOS SDK 26.5, loads in iOS 18+ Control Center gallery, and launches app to root fleet dashboard.
- **Widget Tinting**: Test in iOS 26.5 simulator under Dark, Light, and Accented home screen styles. Ensure labels remain legible.
- **Charts Selection**: Verify drag gesture does not trigger page swipe across daily/weekly/monthly tabs.
- **Accessibility**: Verify VoiceOver audio graph rotor and Reduce Transparency fallback.
