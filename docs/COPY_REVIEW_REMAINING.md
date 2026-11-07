# Copy Review: Remaining Scope (App entry, Widgets, Shared, Store, Core)

Read-only editorial review, 2026-09-12. Scope per assignment: `App/HashFleetApp.swift`,
`App/Store/*`, `App/Design/*`, `Widgets/*`, `Shared/*`, `Sources/HashFleetCore/*`.
Tour/Dashboard/Settings/Reports/Miner/Insights were out of scope (other workers).
No files edited. Semantics, safety limitations, and privacy claims preserved in every suggestion.

## Priority findings (user-visible, awkward wording)

Format: file:line — current → replacement

### Highest priority (notifications, alerts, errors)

1. `App/HashFleetApp.swift:304` (block-found notification body)
   - Current: `The miner explicitly reported a found block at height N.`
   - Suggested: `The miner reported finding a block at height N.`
   - "a found block" is stilted. Keeps the "reported by the miner" semantics (the app did not verify it).

2. `Shared/FleetSystemIntents.swift:65` (Siri/Shortcuts prompt)
   - Current: `No miners are in the last saved fleet summary. Open Hash Fleet to connect a fleet.`
   - Suggested: `There are no miners in the last saved fleet summary. Open Hash Fleet to add one.`
   - `connect a fleet` is wrong framing; you connect miners, the fleet is the collection.

3. `Shared/FleetSystemIntents.swift:74` (Spoken/Shortcuts reply, demo mode)
   - Current: `Demo sample data; no hardware connection is represented.`
   - Suggested: `Sample data; it does not come from real hardware.`
   - Same disclosure, human phrasing, and avoids the demo/sample doubling (see vocabulary rules).

4. `App/Store/FleetStore+Totals.swift:165` (`FleetError.invalidName`)
   - Current: `Use a name of up to 64 characters without line breaks or control characters.`
   - Suggested: `Use a name up to 64 characters with no line breaks or control characters.`

5. `App/Store/FleetStore+Totals.swift` (`FleetError.demoReadOnly`)
   - Current: `Demo miners are read only. Exit the demo to manage your saved fleet.`
   - Suggested: `Demo miners are read-only. Leave the demo to manage your saved fleet.`
   - `read-only` hyphenated when predicative here; `Exit` is a CV, users leave a mode.

6. `App/Store/FleetStore.swift:79` (unreadable-saved-fleet alert, shown via `persistenceError`)
   - Current: `Your saved fleet could not be read. The original data has not been overwritten. \(error.localizedDescription)`
   - Suggested: keep the first two sentences, but append the technical detail on a new line or drop it from the alert body, e.g. prefix with `Details: `. Raw `localizedDescription` (e.g. "The data couldn't be read because it isn't in the correct format.") directly after the friendly copy reads badly. Do not change the safety claim itself.

### Medium priority (descriptions, intents, widget metadata)

7. `Shared/FleetSystemIntents.swift:40` and `Widgets/FleetControlWidget.swift:20`
   - Current: `Open Hash Fleet's fleet dashboard.`
   - Suggested: `Open the fleet dashboard in Hash Fleet.`
   - Avoids possessive repetition and the `Hash Fleet's fleet` stutter.

8. `Shared/FleetSystemIntents.swift:59-61`
   - Current: `The last saved fleet summary is unavailable because it is invalid. Open Hash Fleet to create a new snapshot.`
   - Suggested: `The last saved fleet summary could not be read. Open Hash Fleet to save a new snapshot.`
   - `unavailable because it is invalid` is diagnostic-speak; the outcome for the user is identical.

9. `Widgets/FleetWidget.swift:46-48` (widget gallery description)
   - Current: `A cached fleet snapshot with best-effort background refresh. Readings older than a minute are marked stale.`
   - Suggested: `Your last saved fleet snapshot, refreshed in the background when possible. Readings older than a minute are marked stale.`
   - `best-effort background refresh` is engineering vocabulary in App Store-facing widget gallery text. The staleness limitation sentence should be kept verbatim.

10. `Shared/FleetSystemIntents.swift:104-106`
    - Current: `Fleet summary sharing is off. Enable Share with Widgets in Hash Fleet to read the last saved summary.`
    - Fine overall; only hyphenation/tree nit: consider `Turn on Share with Widgets in Hash Fleet to...` for imperative voice consistency with other shortcuts copy. Low value; skip if churn matters.

11. `Shared/FleetSystemIntents.swift:116` — `Read the last aggregate fleet summary saved for widgets.`
    - Suggested: `Read the last fleet summary saved for widgets.` (`aggregate` adds nothing user-facing; the summary itself is the aggregate.)

### Low priority (nits, style consistency)

12. `App/Design/FleetPerformanceSettingsView.swift:46` header `Measurement Limitations` and `:71` header `Per-Screen Diagnostic Reports` use Title Case while sibling headers (`Callback metrics`, line 28) use sentence case. Apple HIG uses sentence case for section headers. Suggest `Measurement limitations` and `Per-screen diagnostic reports`.

13. `App/Store/FleetStore+Monitoring.swift`-driven message `App/Store/MinerSnapshot.swift:351`: `Offline · showing cached settings. Reconnect to verify.` Good. Keep as the model for terse offline states.

14. `Sources/HashFleetCore/MinerCapabilities.swift:260-262` and `App/Store/MinerCapabilitiesStore.swift:222-224` duplicate `Invalid miner address.` / `The miner returned a non-HTTP response.` strings. Not a wording problem, but future copy fixes must be applied in both places; consider one shared source. `Invalid miner address.` is fine as copy.

15. `App/Store/FleetGlanceCoordinator.swift:103` — `Live Activities are not available. Check Hash Fleet's Live Activities permission in iOS Settings.` Clear and correct. Keep.

16. Empty-state CTAs across widgets use three phrasings for the same action: `Open app to connect` (FleetWidget.swift:127, 341), `Open the app to connect a miner` (FleetLiveActivityWidget.swift:200), `Open Hash Fleet to connect your first miner` (FleetLiveActivityWidget.swift:227), `Open app to connect a miner` (FleetLockScreenWidgets.swift:87). Legal variation, but recommend standardizing on two forms: short label `Open app to connect`, and full sentence `Open the app to connect a miner`.

17. `Widgets/FleetWidget.swift:123` `A little fleet.\nA lot of possibility.` and `214/332` `Your fleet starts in Hash Fleet.` are marketing taglines in empty states. They read well; keep. (Splash tagline `Your miners. One fleet.` in `FleetStartupSplash.swift:46` excluded from edits per instructions.)

## Vocabulary rules proposed for the whole app

These emerged from comparing the reviewed scope; applying them consistently will make other workers' copy converge.

1. **miner vs fleet**: miner = one physical device; fleet = the user's collection. Connect a *miner*. Never "connect a fleet." Notifications name the miner (`Block found by \(minerName)`) and that pattern is good.
2. **live / fresh / sample / demo**:
   - `live`: reserve for "Live Activity" (Apple term, capitalized) and real-time connections (e.g. "Live telemetry"). Do not use "live" to describe fresh-but-cached data.
   - `stale`: only when exceeding the staleness threshold; always user-visible as "marked stale" or "STALE" badge.
   - `cached`: the last saved reading still within bounds ("showing cached settings").
   - `sample` preferred over `demo` in UI badges/captions (`Sample data · no connection` in FleetWidgetTheme.swift:60 is the best current instance). `demo` is acceptable as a mode name ("Leave the demo"), but avoid "Demo sample" doubling (FleetSystemIntents.swift:74) and avoid `DEMO` all-caps chips where `SAMPLE` fits (FleetLiveActivityWidget.swift:34, 66 show `DEMO`; lock screen shows `Demo · `). Recommend one rule: badges say `SAMPLE`, mode is called "the demo."
3. **share / block**: event copy says "Block found by …" and "New best share from …" (HashFleetApp.swift:301, 317). Keep "block found" (not "block discovered") and "best share" everywhere. The setting key copy "Share with Widgets" is a different "share" — acceptable, but don't use "share" unmodified in user copy around pool statistics; say "share submitted" or "best share."
4. **cost / estimate**: any projected earnings, power cost, or network figure must be labeled an estimate and carry its caveat (as the privacy/safety copy currently does for public data sources, e.g. MiningInsightsModels.swift:63 redirect-privacy line). Never state estimated figures as facts; prefer "Estimated", "~", or an explicit "not a guarantee of earnings" qualifier where money amounts appear.
5. **Error message shape**: `<what failed>. <what it means / safety state>. <what to do>.` as in `Could not reach the miner. Check its address, network access and Wi-Fi, then retry.` (MinerCapabilities.swift:281). Add a serial comma rule? App currently omits Oxford commas ("address, network access and Wi-Fi"); pick one and apply app-wide — recommend standard American usage without Oxford comma only if already the dominant pattern, otherwise adopt Oxford comma. Current corpus is mixed.
6. **App name styling**: "Hash Fleet" (two words, no possessive) in prose. Avoid "Hash Fleet's"; rewrite as "in Hash Fleet."
7. **Sentence case** for section headers, buttons, and notification titles per Apple HIG; all-caps only for tiny stat labels (POWER, ONLINE STATUS), which is established widget convention.

## Validation

- Read-only review; no builds or tests run (per instructions).
- String extraction via grep over the assigned directories; all quoted user-facing literals in Widgets/, Shared/, App/Store, App/Design, and the notification-posting section of HashFleetApp.swift were inspected in context.
- Every suggestion above preserves numeric limits (64 chars, 30–110 °C, slots 0–7), safety claims ("not a safe operating limit", original-data-not-overwritten), and privacy statements (redirects blocked, sample-data disclosure).

## Deferred / out of scope

- `App/Features/Settings/FleetTemperatureAlertNotificationContent.swift` and best-share notification content files (assigned to other workers).
- Onboarding, guided tour, FleetChainCard (other workers).
- Splash artwork/tagline (excluded by instructions).
