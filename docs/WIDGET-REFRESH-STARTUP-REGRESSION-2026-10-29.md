# Widget refresh startup regression, October 29, 2026

## User report and safe scope

The operator reported that tapping the widget's Refresh button worked before the installed build-8 update, but no longer updated the reading. This investigation concerns that explicit action, not ordinary passive WidgetKit scheduling. A read-only installed-app query confirmed Hash Fleet 0.1.0 build 8. Its frozen source is commit `18f409c`.

This repair is source-only. No phone install, app launch, unlock attempt, preference change, real-miner read/write, or remote service change was performed. Existing phone acceptance remains unverified, not silently completed. The earlier chart change is unrelated.

## Reproduced lifetime defect

`FleetGlanceCoordinator.updateWidgetRefreshFleet` previously treated any failure to prepare new identity pins as a revocation. A new coordinator has no complete in-memory observations, so an initial call with the unchanged selected fleet and empty readings deleted an otherwise valid persisted refresh configuration. The foreground guard came after that deletion.

The unchanged app startup hooks call this method before fresh readings necessarily exist. The installed intent now runs through an app-process intent path, making this startup interaction particularly relevant. The offline sequence reproduced deletion, followed by an intent returning `needsSetup` instead of performing its injected read. A later complete foreground observation then created a new permission generation. That could also invalidate a previously generation-bound Live Activity.

This proves a source-level lifetime defect, not that this exact interleaving was observed on the operator's phone. Physical Home Screen routing, actual LAN permission, and the current on-phone refresh outcome were not established. A direct read-only copy of the root App Group state file was denied by the device tool's container-path policy. That restriction was not bypassed.

## Repair contract

- Complete fresh foreground readings remain the only way to prepare or renew permission.
- Missing, cached, reconnecting, errored, stale or partial frames preserve an existing configuration only when the entire credential-free ASIC selection still matches its exact saved IDs and validated URLs.
- Retention does not write the state file. The permission generation, renewal/expiry dates, saved observation, lease and cooldown are therefore not reset by incomplete startup frames.
- Explicit opt-out, Demo, changed selection/address/type/credentials, invalid inventory, or a complete fresh contradictory identity still revoke permission. A background observation cannot repin a changed identity.
- Expired permission may keep its last saved reading, but remains disabled and starts zero reads. Keeping old evidence is not extending its freshness or authorization.
- The authenticated intent, awaited persistence, separately compiled widget provider, bounded read engine, ActivityKit handoff and shipping project identifiers are unchanged.

`FleetWidgetRefreshPreparation` now shares one strict MAC parser between new preparation and matching existing pins. The existing foreground preparation rules, including address and Demo round-trip invalidation, remain intact.

## Requirement-to-check ledger

| Requirement | Observed check |
| --- | --- |
| Cold app process must not destroy prepared refresh | New coordinator with empty frames, then the real intent helper and separately compiled provider: same permission, one injected read, exact new value/time |
| Temporary incomplete frames must not renew or delete state | Both foreground/background across six frame kinds: state-file bytes unchanged |
| Unsafe selection must still revoke | Both foreground/background across eight selection changes: state removed |
| Background cannot silently accept another identity | Changed, ambiguous and malformed fresh MAC observations revoke rather than repin |
| Expiry keeps evidence but forbids reads | Both modes retain the saved observation, disable the action and execute zero injected reads |
| Explicit consent remains authoritative | Sharing and local-refresh opt-outs on an existing coordinator still revoke |
| No background grant or renewal | No configuration from fresh background data; later fresh foreground data renews the same existing generation |
| Existing transactional and ActivityKit boundaries remain intact | Existing engine, handoff, glance, background-publication and widget-integration suites pass unchanged |
| No unrelated work lost | Full pre-existing binary diff, index, status and untracked-file hashes checked against the private starting receipts |

## Validation receipts

Private artifact root: `hashfleet-widget-regression-20261029-2153` under Jcode scratch. Builds use frozen HEAD source plus exactly the three repaired/test files, a separate laboratory bundle namespace and an inert simulator app entry point. No production app store or monitoring startup is constructed by that entry point. Native Mac validation is compilation only, not a lifetime or UI acceptance test.

| Receipt | Actual result |
| --- | --- |
| `baseline-lifecycle-final.xcresult` | Original committed production source, unchanged new test assertions: 7 definitions / 37 executions, 5 definitions / 17 executions failed with 39 assertion issues. The other 20 executions passed. Command exited 65 normally. |
| `fixed-functional.xcresult` | iOS 27.0: 65 definitions / 137 executions passed across five suites. All 7 new definitions / 37 lifecycle executions passed. |
| `fixed-ios26-final.xcresult` | iOS 26.5: the same 65 definitions passed twice, 274 executions. Actual repetition nodes verified. |
| `existing-integration-final.xcresult` | iOS 27.0: all 11 existing definitions / 22 executions passed, including the original consent/preparation, persistence/provider and mounted widget-layout assertions. No old assertion was edited. |
| `fixed-native-build.log` | Native macOS shared-source build succeeded. No native app launch or stress result is claimed. |

The passing result summaries report zero failures, skips, expected failures and runtime warnings. This does not mean every app/build diagnostic or every unrelated suite is warning-free. Earlier unrelated OCR failures documented elsewhere are not erased by this focused passing run.

The first baseline command failed to compile because the source-copy tool output truncated the test fixture. This was corrected by bounded exact source reads and matching SHA-256 checks, not by weakening test assertions. A second baseline executed the failures but stalled collecting diagnostics and was stopped. The final baseline disabled verbose failure-diagnostic collection and completed with the same 39 assertion issues. All earlier receipts remain retained and are not relabeled as passes.

An optional read-only worker review was rejected after an incorrect duplicate handoff edit and unsupported build claim. Its edit was removed and the intent file verified unchanged. It is not independent approval. Root verification relies on the observed receipts and source/preservation checks above.

## Delivery and remaining device acceptance

The repair does not repair an already deleted phone configuration remotely and is not yet installed. Device acceptance requires an approved in-place preserving update, normal user authentication, foreground preparation if the old state was already removed, then an actual Home Screen Refresh tap with the app inactive. Verify a genuinely newer observation and preservation of the selected fleet, consent and saved history. If checking a Live Activity, use a deliberately started activity bound to the current permission generation.

Until that check is observed, do not claim that the user's phone refresh is fixed, promise continuous updates while suspended, reinstall/remove the app, poll indefinitely for unlock, or change miner settings to compensate.
