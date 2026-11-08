# Durable record queue, November 7, 2026

## Operator goal and scope

The operator requested queued multiple best shares, durable storage, and an aggressive retest with all best-share alerts enabled. This builds on the existing illustrated FIFO presentation, not a replacement activity menu, notification bell, or transient session toast. Changes are confined to the fix copy. Nothing is installed on a physical phone or production Mac.

## Presentation contract

- Exactly one record is visible. Later records wait in FIFO order without replacing its identity or value.
- Keep mining explicitly acknowledges the current record and advances to the oldest waiting one.
- Review later hides presentation without acknowledging any record. Incoming records continue to enqueue. A compact Review records (N waiting) control resumes the oldest unacknowledged record.
- View miner atomically acknowledges the visible record and pauses presentation, then navigates. The next popup must not cover the detail page.
- Session alert opt-out saves the preference independently of queue storage and removes only pending session-best presentation, including records beyond the first cached page. A presentation-time head gate honors opt-out even if the purge fails, with retries on lifecycle/explicit resume rather than deleting or acknowledging another record. All-time and block records keep their relative order. Underlying telemetry and achievements are not deleted.
- Existing full-screen artwork, primary navigation, accessibility labels and the 44-point minimum control targets are preserved.

## Ownership and persistence

FleetStore remains the canonical telemetry and event authority. Existing per-miner read projections remain unchanged. The celebration database stores presentation acknowledgements, not a second writable telemetry store.

The app owns one queue. The queue keeps one visible head plus at most 32 waiting payloads in memory, backed by an indexed SQLite FIFO. Unacknowledged records and paused state persist across process termination. Ordinarily acknowledged IDs remain as payload-free tombstones to suppress duplicate delivery after a handoff/relaunch window. Session opt-out retains tombstone payload bytes to preserve any unreadable evidence.

Production storage is under Application Support/HashFleetCelebrations/<bundle identifier>/pending.sqlite. Ordinary tests and demos use an ephemeral in-memory database. The explicit diagnostic durable test uses its isolated bundle namespace. Corrupt, foreign and newer-schema files are not replaced with an empty queue. Opening failure produces a visible error and refuses durable acceptance. If a later acknowledge/pause write fails, a session-only, record-ID-keyed hide lets the person navigate while the record stays unacknowledged. Review records retries the durable operation. Record backpressure never blocks status, power or temperature alert surfaces. An unreadable oldest payload is preserved and blocks later presentation rather than silently skipping FIFO.

Settings previews use a separate ephemeral presentation value and never enter the durable queue. Record actions capture the visible UUID and ignore callbacks from an older transitioning view. Tapped notification routes are consumed only after durable acceptance.

Notification delivery may claim an in-app journal entry only after the durable queue accepts it. A backward-compatible optional `inAppAcceptancePending` journal marker distinguishes failed new handoffs from intentionally suppressed historical events. Older failed handoffs are retried before newer records, and a decline prevents later handoffs overtaking it in the same pass. Failed acceptance must be retryable without posting a duplicate system notification. Background events already posted to the system remain excluded from foreground replay.

## Limits and recovery

The queue intentionally does not delete or skip an unreadable oldest record. It surfaces a dedicated queue error, independently of fleet backup errors. There is no automatic destructive recovery UI in this change. Preserve the database and its WAL/SHM companions for support or read-only export before any operator-authorized repair. Acknowledgement tombstones are not pruned automatically, so long-term disk growth remains a measured follow-up, not an unlimited-storage guarantee. Presentation uses a single main-actor owner, not multi-process access. Real disk-full, power-loss and physical-device sandbox recovery are not certified by the tests. The existing notification detection journal retains its existing 100-entry/14-day limits, so a prolonged storage outage is not a guarantee of unlimited delivery retention.

### Failure-mode follow-ups, not acceptance claims

- Failed foreground record handoffs remain explicitly retryable on the next foreground delivery pass. They are marked on the system channel to avoid a duplicate push, so backgrounding before retry does not send a replacement system banner. This is a deliberate current delivery limit, not evidence that a record was durably accepted.
- A retained notification-tap payload has no expiration. If durable enqueue fails, navigation still works and the payload remains available for a later retry, which can navigate to that miner again after a later trigger or cold launch.
- An enqueue or session-purge failure can temporarily hide an unrelated current record. The record remains unacknowledged. A failed session purge also holds new all-time/block acceptance until the purge succeeds. No data-loss claim is inferred from the session-only hide.
- The Mac delivery loop can retry an unavailable queue each second. SQLite busy timeout remains 250 ms. The November 8 repair below moves connection setup, reads and synchronous transactions to an actor-owned worker; retry backoff, real disk-full responsiveness and physical UI acceptance remain follow-ups.
- Notification journal persistence retains its existing last-writer-wins behavior between separate background/foreground stores. A retry marker is not a multi-process transaction or an unlimited outage spool.
- The added Review later/waiting controls have not yet repeated the earlier phone/desktop Accessibility XXXL layout suite or a native Mac click-through acceptance test. Earlier layout receipts predate these controls.

Reproduce the standalone production-storage and real macOS SwiftUI `@State` checks with `Scripts/tests/run-celebration-persistence.sh -O` (or `-Onone`). The script extracts the actual display model, omitting only its three Core-event conversion adapters and unrelated view, then compiles the unchanged production queue/storage and test file. Native app-target tests separately exercise real Core event conversion and notification delivery.

## Interaction-boundary corrections

The real alerts-enabled diagnostic first found an 18-point accessible Review later target despite an outer 44-point frame. The minimum height and content shape now belong to the button label itself. A later actual resume tap exposed a coordinate mismatch: the named SwiftUI control rectangle began at y=786, its visible window rectangle at y=848, and the tap at y=877 missed the old hit region. The notification host now converts named content-root rectangles by the actual window safe-area origin. All producers, including safety banners, use that named space so a banner cannot be double-offset. Native tests cover the observed portrait geometry, a landscape left inset, toolbar/content pass-through, and the banner upper-body and below-banner boundary.

The first count-over-1,000 diagnostic also confirmed localized accessibility values such as `1,480`. Only the test parser changed: it removes the current locale grouping separator and nonbreaking grouping spaces, rejects other nondigits, then parses an exact integer. Growth, restored count, UUID identity, touch target and FIFO assertions were not weakened. Values read at different times can legitimately differ while ingestion continues.

## Verification status

Final iOS acceptance uses production commit `a9e3204` with only the named diagnostic fixture injections. The optimized iOS 27.0 simulator run passed with best-share and session-best in-app alerts enabled, not the earlier notification-suppressed navigation control. No physical phone or production app was installed. Times below are measured receipts, not promised delivery latency. Evidence remains under `~/.jcode/scratch/hashfleet-queue-stress-20261107T2251.noindex/`.

| Check | Observed result | Evidence under the isolated queue-stress workspace |
| --- | --- | --- |
| Core package | 293 tests in 32 suites passed | `results/core-tests.stdout` |
| Optimized production queue/storage and real hosted SwiftUI state | All 17 checks passed; 10,000 records drained FIFO across reopen, cache maximum 33 | `results/queue-final-unified-tests.stdout` |
| Final optimized platform builds | iOS build-for-testing and native Mac build succeeded on `a9e3204` | `results/ios-unified-hit-regions-build.stdout`, `results/mac-unified-hit-regions-build.stdout` |
| Real optimized iOS app-hosted queue, delivery and notification-window tests | 51 passed, 0 failed, 0 skipped; 9.835 s driver elapsed | `results/native-queue-delivery-tests-unified-hit-regions/Tests.xcresult`, exported summary and receipt |
| Alerts-enabled actual UI | 1 passed, 0 failed, 0 skipped; 372.735 s driver elapsed | `results/ios-queue-alerts-unified-hit-regions/UITests.xcresult`, exported summary, attachments, receipt and preserved queue database |
| Native Mac foreground backlog observation | 180 s, 36/36 samples frontmost with a visible window; 2,074 pending rows readable after stop, 0 acknowledgements | `results/mac-queue-alerts-backlog/receipt.json` and byte-preserved database |

The final iOS UI test verified a stable record UUID, Review later without acknowledgement, continuing ingestion while paused (1,460 to 1,700 waiting), actual process termination/relaunch retaining pause and the oldest UUID, resume, Keep mining advancing to the next UUID, and View miner acknowledging and pausing before navigation. All twelve detail/back cycles asserted the real detail marker and its disappearance on back. A real chart tap/drag selected 22.95 TH/s at 19:05:20 EST and 56.80 TH/s at 19:06:21 EST on November 7. The stopped database contained 26,870 pending and exactly two acknowledged rows. Those acknowledged IDs matched the two oldest rows and the UI attachments; paused state was 1 and `quick_check` returned `ok`.

The fixture sent 40,466 frames across all twenty devices (2,020 to 2,025 per device), with 240 information GETs, 80 WebSocket GETs and zero forbidden writes. Twenty Hz per device was the requested cadence, not a guaranteed achieved network rate. Reconnect gaps and process relaunch are part of this workload. Maximum observed iOS RSS was 629,840 KiB and numeric descriptors reached 76 within the bounded run. These are observations, not a leak-free or real-time-throughput certification.

The Mac backlog run used the preceding `c997509` presentation snapshot and sent 55,807 frames across all twenty devices. It proves a foreground workload wrote a backlog that was readable after a bounded stop. It does not prove Mac UI FIFO presentation, relaunch restoration, chart gestures, or the in-memory cache bound. Cache/FIFO/reopen/error behavior is covered by the separate production-storage regression executable. Final source builds are checked separately from this Mac runtime receipt.

All failed and superseded attempts remain preserved: initial exclusive-port refusal, the 18-point control failure, localized-count parse failure, resume coordinate failure, the intermediate 50-test and successful UI snapshot, and the earlier delivery-journal regression. Tests were corrected only for real source/compiler issues or exact diagnostic input parsing. The historical suppression test and interaction/FIFO assertions were not weakened. In-app notification acceptance is exercised here; operating-system authorization and delivered system-banner UI are not certified.

Existing unresolved findings remain separate: an earlier simulator Swift Charts HashableText trap, reconnect socket descriptor accumulation, and the physical-phone background watchdog. Passing a bounded simulator run is not proof that these are fixed.

## November 8: off-main-actor storage repair

The app now owns a main-actor `FleetCelebrationQueueController` whose properties read immutable presentation snapshots, not SQLite. Its worker actor exclusively creates the connection, executes queue commands and performs recovery reads. Commands are submitted in main-actor order and awaited through a task chain. A caller cancelling its wait does not discard an already-submitted durable command. Dismiss, pause and acknowledge-and-pause carry the captured visible UUID; the worker rejects a stale action before modifying a newer head. Existing SQLite schema, WAL, synchronous durability, failure refusal, FIFO, pause and tombstone policies are unchanged. This is not a Core Data migration or a telemetry-store change.

Notification delivery retains one asynchronous record-acceptance pump per FleetStore. It leaves the journal pending until the actual queue commit succeeds, stops at a failed oldest handoff, and rechecks device membership and preferences for later records after suspension. Synchronous routing can still deliver safety alerts and append new pending records during a blocked record write. Both iOS and Mac use this path. App construction itself no longer opens the celebration database. The UI publishes a worker snapshot after completion rather than treating command submission as durable acceptance.

### Measured checks and retained evidence

Evidence is under `~/.jcode/scratch/hashfleet-stability-20261108T0110.noindex/`. A shared standalone comparison used a real competing SQLite write transaction and a 5 ms MainActor heartbeat. The original synchronous path failed with a 294.185 ms maximum heartbeat gap and zero ticks during its 288.024 ms write. The scratch worker comparison passed with a 6.348 ms maximum gap and 46 ticks while the write still took 283.064 ms. These are controlled contention measurements, not a trace proving the original app freeze had this cause.

The final production controller was then compiled by `Scripts/tests/run-celebration-persistence.sh -O`. All 17 existing storage/state checks passed unchanged, including 10,000-record FIFO/reopen, maximum cache 33, fail-closed lock/corruption/schema checks and hosted SwiftUI state. New production-controller checks observed 47 heartbeat ticks, a 6.359 ms maximum gap and a 293.014 ms blocked write. They also passed lazy initialization, snapshot reads under contention, failed-commit retry, 60 queued commands awaited in reverse order, cancelled-waiter persistence, stale action refusal, pause/reopen, atomic acknowledge-and-pause, cross-page session purge and durable deduplication. Logs are `queue-io-lab/production-controller-run1.{stdout,stderr,raw-exit}`; raw exit is zero.

The frozen integrated source identity is `5cde30039510d2950560340137f51ec227d11c497a4027231601db38c552b5c4`. Optimized iOS build-for-testing passed in 164.509 s and Mac compile-only passed in 133.702 s. The actual simulator selection was exactly `FleetCelebrationQueueTests` and `FleetNotificationDeliveryTests`: all 45 tests in two suites passed, including three new suspended/failed asynchronous handoff tests. Native test time was 0.898 s and runner elapsed time 14.29 s. The original 42 selected tests were retained; this is not the earlier 51-test window/UI suite. No Mac app was launched by this compile check.

| Retained receipt | SHA-256 |
| --- | --- |
| `results/queue-background-build/receipt.json` | `19a712853148019492ce06faa68757f7667e359f984af24fef090eac36641aeb` |
| `results/queue-background-mac-build/receipt.json` | `c7d92e0d431edee0f5a77e443a65ae384101b1a309cd458e9602fa5dd003c0c8` |
| `results/native-queue-background/receipt.json` | `ffb032b8bdc85a9369fd7eaf8ef6644f4e78c925b4e4d9cf6464697e158b03b4` |

The native receipt has a copied, incorrect `scope` string mentioning a 120-step chart test. Preserve it as recorded: its actual argv, selected test names, 45-test classifier and logs establish queue/delivery testing, not a chart pass. Root rehashed the three receipts' closed logs and product executables, native input pins, all 670 frozen runtime files/modes, and changed repository source parity except the documented diagnostic FleetStore injection. The final verifier initially assumed the wrong literal spelling of that existing injection, then checked the exact two-line source substitution and passed without artifact changes. Existing project build settings were unchanged, the controller is present once in each iOS/Mac source phase, and unrelated generated Watch scheme changes were removed.

Recorded build/test cleanup and immutable-input gates passed. A fresh root native-idle check passed at 13:23:56 UTC before the later Mac compile-only operation. These checks are not independent review, physical-device acceptance, a repeated alerts-enabled UI stress run, or proof of original watchdog/Charts/reconnect causality. UI animation/click-through behavior and the full integrated stress workload remain unaccepted after this asynchronous transition. GRDB contention and large UserDefaults decoding were not repaired by this change.
