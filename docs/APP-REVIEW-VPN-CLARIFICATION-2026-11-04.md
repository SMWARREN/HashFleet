# App Review VPN clarification, November 4, 2026

## Requested outcome and delivery

The owner requested replies to both Hash Fleet App Review issues. Both exact Apple threads were read in the owner's signed-in Chrome session. Each contained the same automated Guideline 2.1 request for information about suspected VPN functionality.

| Platform | Submitted build | Submission | Reply sent UTC | Persisted reply confirmed UTC |
| --- | --- | --- | --- | --- |
| iOS, including Apple Watch | 1.0 (20) | `60ddc9db-3af7-4c6e-8007-f8f5d00f9cf6` | 09:31:00 | 09:32:02, after reload |
| Native macOS | 1.0 (19) | `ce8e7cd8-2cec-4b98-aaea-f52972ce0ca6` | 09:29:47 | 09:32:15, after fresh navigation |

Each thread contains two messages: Apple's original and exactly one owner reply. The exact prepared reply text was confirmed on the freshly loaded page, with no open reply form or unsent draft. Replies ask Apple to continue review of the currently submitted builds. They do not claim approval.

## Clarification supplied

Hash Fleet uses ordinary local-network discovery and device API requests to discover and monitor compatible external ESP-Miner/AxeOS devices. It does not create or manage a VPN, install VPN profiles, operate a proxy, or capture other apps' traffic. References to a VPN describe an optional, independently configured user VPN that can make the user's remote network reachable. A VPN is not required for same-network use.

All three Apple questions were answered, explicitly scoped to the absence of a VPN feature. The replies do not make a blanket claim that the app collects or transmits no information. Optional public chain/pool network requests remain separately disclosed. No networking permission or app feature was removed.

The submitted source revisions were checked: iOS/Watch `a10fec115ba3f74ceed100f023eb235d4a009cd1`, macOS `320510d645a7e5849d13deff73d312b25ef42781`. The code does not contain VPN/NetworkExtension implementation APIs. The retained signed Mac entitlements contain sandbox, user-selected files and network-client access, not VPN capabilities.

## App Review Information notes

Apple also requested the clarification in App Review Information. It was appended to both existing platform notes through the existing authenticated App Store Connect CLI.

- iOS notes: 3,094 original characters, 3,801 final characters.
- Mac notes: 2,169 original characters, 2,876 final characters.
- Original note text, hardware-free demo instructions and demonstration provenance were preserved exactly.
- Fresh API readbacks matched the expected notes and all other returned review-detail fields. Private contact details are not reproduced here.
- Selected iOS build 20 and Mac build 19 were not replaced. No upload, resubmission, release, price change, agreement acceptance, production app/network setting change or miner operation was performed.

## Current state and release-policy discrepancy

Fresh page reads after sending still show `UNRESOLVED_ISSUES`, and fresh version records show `REJECTED`. Replies are delivered, not approval or a claim that review has resumed.

**Important:** fresh version-list responses on November 4 at approximately 09:33 UTC show `releaseType=AFTER_APPROVAL` for both versions. This conflicts with the earlier submission document's `MANUAL` observation. This task did not change release policy and does not establish who or what changed it. Do not infer that manual release remains configured. Report the live value to the owner rather than silently restoring the older setting.

## Evidence and limits

Private local evidence: `/Users/USER/.jcode/scratch/hashfleet-review-20261104/`. It includes exact reply drafts, protected original/final note snapshots, preservation plans and readback receipts. Native Chrome scripting was used because the browser bridge was disconnected and the separate cached Apple web sessions were expired. No cookies or credentials were printed or exported.

An initial final-verifier attempt stopped with `KeyError: data` because `versions view` returns flattened JSON. The corrected read-only verifier uses the observed flat view and full version-list schema. The manual-release expectation remains explicitly recorded as false, not rewritten into a pass. No application code changed and no application tests were rerun for this correspondence task.
