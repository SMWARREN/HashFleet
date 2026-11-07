# Real Mac tuner acceptance, October 8, 2026

## Scope and observed outcome

This follow-up exercises the already installed full **Hash Fleet** Mac application through its real public UI. It is not a copied view, simulator, mock, or HTTP fixture. The native **Hash Fleet Menu Bar** application is separate and was not changed.

Earlier October 8 delivery evidence verified installation but could not complete UI navigation. The fresh observation below supersedes that Mac-window limitation for the explicitly exercised read-only paths. It does not establish physical iPhone acceptance, real miner-write acceptance, or installation of the subsequent firmware-cache fixes.

## Requirement-to-observation map

All times are UTC on October 8, 2026.

| Requirement | Real acceptance action | Observed result |
|---|---|---|
| Installed full Mac app runs the intended redesigned tuner, rather than an old cached image | Read the installed executable and the actual translocated PID 54246 executable at 12:44:52 | Both SHA-256 values equal `b49732186e2698a47f87adfcea062485c1365595f32ea4bc03667ace53240a38`, matching the delivered Mac build |
| A real Mac window is available | Window enumeration at 12:39:31 and exact-PID System Events read at 12:41:05 | Window 6820, title Hash Fleet, physical frame `(0, 39, 2056, 1231)`; exact process identity `HashFleet`, bundle `app.hashfleet`, one AX window |
| Public detail Tuning quick link opens the workspace | Clicked the observed Tuning quick link at screen point `(1400, 283)` at 12:43:50, after checking that its production action only assigns `tuningSessionRoute` | At 12:43:59 the same physical Mac window displays Tuning session, both frequency and core-voltage dials, step controls, FREQ/VCORE summaries, live-context and reference sections |
| Both ASIC rails and guarded review are reachable without being trapped by the dials | One actual downward scroll from `(1880, 1100)`, below both dials, at 12:45:15 | At 12:45:25 both ASIC 1 and ASIC 2 cards, Safety gate, One settings update, Apply tuning change control and tuning journal are visible |
| Opening and scrolling do not accidentally stage an edit or enable an unacknowledged apply | Observed summaries and review without activating either dial, step button, acknowledgment toggle, restore or Apply | Both summaries remain Matches miner, the payload instruction says to move a dial to stage a valid firmware payload, the risk toggle is off and Apply tuning change is disabled |
| Navigation can return to the original page | Clicked only Back at `(333, 103)` at 12:45:53 | Bounded OCR of the page-title region at 12:46:28 reads the original detail title, not Tuning session; restored-window screenshot retained |
| Connected physical iPhone actually contains the app | Fresh read-only `devicectl device info apps` at 12:40:32 | `app.hashfleet`, Hash Fleet, version 0.1.0, build 7 returned by the physical device |
| Physical phone runtime acceptance is not replaced by simulator evidence | Fresh read-only `devicectl device info lockState` at 12:43:19 | `passcodeRequired: true`, `unlockedSinceBoot: true`; no new launch or lock-screen bypass attempted. Physical tuner navigation remains externally blocked/unverified |

The first name-scoped AX query used Hash Fleet and could not resolve the actual process name. Resolving the exact PID showed the process name is HashFleet and its window exists. A deep Controls AX search later timed out after 20 seconds. Those failures are retained as observations, not represented as successful AX control interactions. The bounded visible navigation used the already observed real window and a source-validated navigation-only target. No app restart, force termination, window resize, permission/security change or device unlock was used.

## Safety and limits

No dial or step value was moved. No Apply, risk acknowledgment, identify, pause/resume, restart, pool, firmware or recovery control was activated. These were public navigation and scrolling actions only. Opening the session creates its ordinary local Session opened journal entry. Back returned the app to its original detail page.

The action sequence issued no miner settings command. This report does not claim a packet-level audit of unrelated background traffic or provide fleet-health telemetry. Telemetry visible in owner-private screenshots is not treated as a fresh all-five fleet-status check.

Actual write confirmation and matching/mismatching readback remain covered by the real production app's explicit loopback UI workflow, not by an unauthorized physical miner write. The newest firmware-cache fixes and subsequent cancellation-test stabilization are not claimed as installed on the phone or Mac.

## Owner-local evidence

Artifact root: `/Users/USER/.jcode/scratch/unit-swarm-20261008/post-map-recheck/`.

- `mac-real-tuner-open.png`, SHA-256 `9ac6224c730f82fa91bd92efdbade4940a7f011eb33efaba2742e19379a32f2d`: both real Mac dials and summaries after the public quick link.
- `mac-real-tuner-review.png`, SHA-256 `937c2bf3f54eebebe72b4e64641165dc99dbae11c4db18f52c68868aad132f81`: both rails, unchecked safety acknowledgment, unstaged payload and disabled Apply.
- `mac-real-detail-restored.png`: physical window after Back; page-title OCR independently confirms the original detail route.
- `physical-phone-apps.{json,log}`: actual installed app identity, not configuration alone.
- `physical-phone-lock-state.{json,log}`: actual read-only lock-state result.
- The Jcode tool transcript retains window enumeration, exact-PID AX identity, the failed name/deep queries, the observed click/scroll/Back actions and the bounded restored-title OCR.

The screenshots stay owner-local and are not committed because they include unrelated fleet telemetry. No wallet address, pool password, Wi-Fi secret or private key is reproduced in this report.
