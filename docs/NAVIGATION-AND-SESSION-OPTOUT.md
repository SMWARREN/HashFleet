# Original navigation and quiet session-only opt-out

Local user-requested correction, October 24, 2026. Nothing is released or installed into a production app by this work.

## Requested contract

- Restore the dashboard toolbar from immediately before `116218d`, rather than shrinking text to accommodate the rejected additions. Keep the original brand, Hash Fleet title, settings menu and add button.
- Remove the added bell, Fleet activity entry, Activity display submenu and session-alert toggle from the primary-app top bar/menu. Remove the now-obsolete primary activity-list picker from App settings. The separate native Mac menu-bar companion is unchanged.
- Keep the existing illustrated session-best popup. Offer **Turn off session-best alerts** as a small, low-emphasis text button on that popup only, below the ordinary View miner and Keep mining actions.
- Opting out saves only `sessionBestNotificationsEnabled = false`, clears current/waiting session popups, and preserves all-time/block records in their existing order. Other alert preferences remain untouched. A final presentation gate prevents an already-claimed session event from appearing after the opt-out.
- Re-enable the existing Session-best alerts switch inside App settings > Notifications and banners. No extra menu or settings destination is introduced.
- Previewing a record does not itself change preferences. Choosing the explicit opt-out is a preference change. Dismissal or opt-out returns to the same underlying screen and Settings scroll position.
- At accessibility text sizes, popup content scrolls so its actions are not clipped. After the user observed unreadable oversizing in the actual test display, navigation-title and popup heading/control scaling were bounded at `xxxLarge`. The short popup description has the same bound and a Large Content Viewer, while ordinary settings/reading content remains scalable and scrollable rather than globally disabling accessibility. Accessibility-only spacing is reduced so the complete quiet opt-out stays visible. Normal-size artwork and main actions are preserved. The user-facing simulator is restored to normal system text size after testing.

## Evidence and current validation

Receipts are retained under `$JCODE_SCRATCH_DIR/hashfleet-header-restore-20261024`. `verify.sh` in that directory records the exact simulator and Mac compatibility commands.

| Requirement | Check |
| --- | --- |
| Original uncluttered navigation | Diff against `116218d^`; native UI checks the title's available width and original menu entries, and absence of rejected activity controls; inspect actual screenshot |
| Quiet option only on session popup | Native UI and mounted rendering require the session action and forbid it on all-time/block previews |
| Other records survive opting out | Queue tests exercise current and pending sessions, current all-time/block records, FIFO order and idempotent empty removal |
| Only the session preference changes | Actual popup action followed by native settings checks for all six alert choices, preserved-storage relaunch and re-enable |
| Existing record presentation is preserved | Three-kind Settings preview return test, 12-second session hold without a toast, plus surrounding preference/search regression |
| Accessible actions are reachable | Actual phone and desktop-style simulator UI at Accessibility XXXL |
| Delivery and persistence still behave | Focused notification delivery/lifecycle/window/settings/persistence suites |
| Primary Mac compatibility | Designed-for-iPad arm64 compilation, not a native Mac runtime certification |

Final post-edit validation on October 24, 2026 passed in `final-readable-popup-v3.xcresult`: **130 focused native cases in 12 suites and all six actual simulator UI scenarios**, including preserved-storage opt-out/re-enable and phone/desktop-style largest-text layouts. Tests require the complete opt-out frame inside an inset viewport, a 44-88 point quiet action, bounded primary action/description heights and a navigation title no taller than 32 points. Final exported screenshots were visually inspected for the full normal-size Hash Fleet title and readable largest-text popup with all actions visible. `mac-final-readable-popup-v3.log` records the primary Mac compatibility build after the last production edit, also passed. This is scoped simulator acceptance and compatibility compilation, not a whole-app or physical-device certification.

### Post-APNs integration closure, October 25, 2026 UTC

The later APNs replacement was checked against the restored navigation and session-only opt-out rather than assuming the earlier result still applied. Receipts under `$JCODE_SCRATCH_DIR/hashfleet-apns-20261024` record **163 native tests in 15 suites and all eight actual simulator UI cases passing** in `device-check-final-v3.xcresult`. The UI cases include the full original header/menu, preserved Settings preview return, persisted opt-out and re-enable, phone and desktop-style Accessibility XXXL layouts, and inline APNs controls that remain off and disabled in demo. `device-check-mac-build-v1.log` records the passing primary Designed-for-iPad arm64 compatibility build. `core-full-package-final-v1.log` separately records all **271 shared-package tests in 28 suites passing**. These are completed runs, not active tasks or inferred passes.

The remaining regression hypotheses were checked directly:

- A fresh source diff against `116218d^` shows that the dashboard toolbar retains its original structure and menu contents. The only title additions are its documented scaling bound, Large Content Viewer and nonvisual test identifier. The separate Mac menu-bar source has no changes relative to `116218d`, which already contained its independent activity choices.
- Current routing still changes only the session preference and gates late session events. Queue tests retain current and pending all-time/block records in FIFO order while removing sessions, including empty and repeated removal cases.
- Attachments exported from the final integrated result were visually reviewed on October 25 UTC. The normal illustration and low-emphasis action are preserved. Phone and desktop-style largest-text popups show the complete quiet action below both ordinary actions, without clipped labels. The post-dismissal title remains readable, and the actual inline Settings switch can be re-enabled after relaunch.

The reviewed images and export manifest are retained in `$JCODE_SCRATCH_DIR/hashfleet-header-restore-20261024/integrated-final-review`. They include `E125AADD-3555-4FEC-B62E-72BF623D16BA.png` (original header), `D630817C-6935-4482-928C-B84702D86C14.png` (gear menu), `075A1E9F-1167-4DDB-B6BB-5119CC53AD71.png` (normal popup), `040CDDAF-17DA-4280-B785-21A77E012ECC.png` (phone largest text), `18105236-74B1-47A3-8D3D-4F699BF4216D.png` (desktop-style largest text), and `828BD55A-84D7-4577-94D0-4EBF4303DE4B.png` (re-enabled switch).

At 01:56 UTC, the existing demo simulator reported normal system text size `large`. A fresh `fleet-normal-handoff.png` was captured and visually checked with the full Hash Fleet title, original gear and plus controls, and simulated fleet screen. The local demo workflow is complete. No additional production source changes were needed after the passing integrated run. APNs activation, physical-device delivery and production installation remain separate, unperformed gates, not missing steps in this navigation correction.

### Retained attempts

- `header-and-popup.xcresult` and `mac-compatibility.log` retain the first compiler failure. Swift could not diagnose a conditional method reference in the view builder. The action was moved to an explicitly typed optional closure.
- `header-and-popup-verified.xcresult` completed with **128 of 130 focused native tests and five of six UI scenarios passing**, so the bundle remains failed. Its actual failures were the existing alert-explanation phrase contract, a mounted numeric-transition OCR timeout, and re-enable test input aimed at a native switch below the viewport. The screenshot and accessibility debug capture show the switch at y912 in an 874-point window, even though its partially visible wrapper row was hittable. The final test reveals the actual child before tapping it and retains all opt-out, independent-choice, relaunch and re-enable assertions. Only the optional diagnostic subprocess was stopped after all tests had finished so Xcode could finalize this failure.
- The explanation keeps its original all-time-only meaning and tested phrase, adding the popup action/re-enable guidance. The mounted text check uses a settled-animation transaction for pixel capture, with the same visible-label and value requirements. The separate native UI check retains the actual animated popup and 12-second persistence assertion.
- `final-acceptance.xcresult` retains a test compilation failure from trying to override the read-only system Reduce Motion environment value. That unsupported override was removed, not added to production.
- Actual enlarged screenshots from the first completed run exposed oversized headings and controls despite the reachability test passing. The final tests add title/control size bounds instead of accepting existence alone. The original normal-size header screenshot already showed the complete Hash Fleet title without the rejected bell.

No failed attempt is recast as passing. The optional read-only reviewer returned no bounded findings and was stopped. Root source review and observed acceptance checks are used, not an independent-review pass.

The earlier feature UI tests for the added activity menus were replaced because the user explicitly rejected that interface. Their old receipts remain historical, not evidence for the restored navigation. The separate companion's choices and preference keys remain intact.

## Limits

This is simulator/demo acceptance and compatibility compilation. It is not a production installation, store release, physical-device notification certification or mining-fleet operation. No miner settings, firmware, services or wiring change. The earlier whole-app audit's unrelated phone-inset test conflict remains unresolved and is not recast as a green full-suite result. The popup queue remains in-memory, not a durable acknowledgement queue across force quit.
