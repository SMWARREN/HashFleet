# Foreground alerts and desktop layout acceptance, October 6, 2026

## Delivered application

- App: Hash Fleet, bundle `app.hashfleet`, version `0.1.0`, build `6`.
- iPhone: installed over the existing USB pairing on October 6 at approximately 08:16 UTC. `devicectl device info apps` read back build 6. Automatic launch was denied because the phone was locked, not because installation failed. No demo or testing arguments were sent to the phone.
- Mac: signed build 6 installed with the previous build retained for rollback. Inner app passed `codesign --verify --deep --strict`. The separate menu-bar app was not replaced or stopped.
- Mac visual acceptance used only isolated demo/testing mode. After acceptance, the main app was quit and reopened without those arguments at 08:30 UTC. No saved miner records, private database contents, credentials or live device settings were inspected or changed.

## Behavior verified

| Requirement | Observed check |
| --- | --- |
| Notifications above pushed screens and sheets | Four focused simulator UI workflows passed, including alert dismissal, tap-to-miner routing, celebration presentation and sheet reuse. Non-key-window hit testing and notification lifecycle contracts passed in the app unit suite. |
| Mobile branding | Compact menu/footer workflow passed with the original Hash Fleet logo retained. |
| Mac one/two columns | Geometry tests cover preferences, narrow-window fallback, even pairs, odd counts 1/3/5/7 and row-height alignment. Installed build 6 visibly rendered two miner cards followed by one full-width final card. |
| Equal desktop margins | Installed overview and representative standalone pages use the common full-width desktop layout. Captures show aligned left/right margins rather than centered narrow panels. |
| One collapsed-sidebar icon | Native accessibility inspection found exactly one `Show Sidebar` button and no additional custom sidebar toggle. Expanded mode displayed the detail-column Hash Fleet brand. |
| No Done on standalone Mac pages | Direct native accessibility navigation opened About, Alerts & Monitoring and Achievements. Their actual navigation bars had their headings and appropriate brand/filter controls, with no Done button. |
| Real popup dismissal remains supported | Sheet content resets the standalone-page environment flag. Existing dismissal and navigation/reuse workflows passed. No claim is made that every popup was independently clicked on the physical Mac. |

## Test evidence and limits

- Final build 6 app contracts: 731 Swift Testing tests in 74 suites plus five XCTest preference-checkpoint tests passed. The result bundle reports 736 test definitions, with parameterized runs counted separately.
- Build 6 targeted simulator acceptance: the compact logo/menu workflow and four notification UI workflows passed.
- Core library/CLI: earlier complete run passed 198 tests in 23 suites. Coverage-instrumented revalidation is tracked separately in the quality report.
- Full legacy UI coverage is not claimed. An earlier broad UI run timed out, and some legacy ticker/navigation assertions are stale. Those results were retained rather than hidden or converted into passes.
- Hardware telemetry is not part of this report. All displayed miner values in acceptance screenshots are explicit demo fixtures, not current mining-fleet status.

Owner-only detailed artifacts are under the session scratch directory `hashfleet-foreground-20261006`, including signed build logs, simulator result bundles, iPhone installation/readback JSON and Mac demo captures. No credentials are included in this report.
