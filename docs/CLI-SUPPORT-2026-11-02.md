# Interactive CLI Support acceptance: November 2, 2026

## Delivered scope

The terminal dashboard previously had no Support entry, and the standalone `support`
command omitted the already-configured native/website crypto destinations.

- **Shift+S** now opens Support from the fleet, miner details, or logo view.
- The read-only page shares PayPal and the existing BTC, ETH, and SOL mainnet
  destinations with the standalone command. No receiving destination was changed.
- Full addresses wrap instead of truncating. Arrows or j/k scroll, g/G jump to
  top/end, S/b/Escape returns to the previous view, and q/Ctrl+C exits normally.
- New dashboard polls are suppressed while Support is visible. Existing pending
  read completion is not represented as a new request.
- Opening Support never opens a browser/wallet, changes the clipboard, contacts a
  payment service, or sends payment. Support destinations are real in demo mode.
- Existing settings, snapshot/JSON, sort, details, logo, invalid-argument, and
  standalone unavailable-checkout semantics are preserved.

## Source-bound checks

Final acceptance used a fresh CLI-only SwiftPM scratch build, without generating
or installing any `.app` bundle. No original acceptance test was removed or changed.

| Requirement | Observed check | Result |
| --- | --- | --- |
| Discoverable interactive entry | Actual PTY help/footer checks at 120x40, 80x18, 60x12, and 45x12 | Pass |
| Crypto configuration integrity | Exact private comparison to shared configuration, plus unchanged native/website parity tests | Pass |
| Complete addresses and bounded layout | Actual wrapped/scrolled/resized PTY frames at 120x40, 54x12, 45x12, and 30x8 | Pass |
| Tiny-terminal escape/quit visibility | Resize to 20x5 with original quit-visibility assertion retained | Pass after production fix |
| Correct return view | Enter/return through selected miner details and logo; Escape/b/S | Pass |
| Input boundaries | Buffered transition keys discarded; pasted shortcuts ignored | Pass |
| No hardware shortcut dispatch or new polling in Support | Loopback fixture held beyond one polling interval, then resumed on return | Pass |
| Terminal restoration | q/Q/Ctrl+C/Ctrl+D and SIGTERM from the actual Support view | Pass |
| Existing CLI functionality | All 54 unchanged standalone/dashboard/settings/firmware-activity tests | Pass |
| Shared core regressions | Full Swift package run: 53 XCTest cases and 293 Swift Testing tests in 32 suites | Pass |
| Static checks | Strict SwiftLint and `git diff --check` | Pass |
| Protected inputs | Shared crypto configuration, root dependency lock, original dirty stability report | SHA-256 unchanged |

The final run passed **8 new Support tests + 54 existing CLI tests + 2 unchanged
crypto parity tests**, with no skips or expected-failure substitutions. Full core
regressions passed separately. The first Support run's 7/8 result is retained: its
20x5 quit hint was clipped. The production hint was shortened and the same test
passed on rerun. No assertion was weakened to obtain that pass.

The delegated read-only reviewer did not return findings within its bounded window
and was stopped. No independent review completion is claimed. The coordinator
reviewed the navigation, shared destination reuse, and absence of external actions.

## Visible preview

At 09:24 UTC the source-built CLI was opened in a separate 124-column, 42-row
Terminal preview using demo miner data. Shift+S opened the actual Support view.
Private inspection confirmed its Support title, PayPal, all three named crypto
options, all three mainnet labels, exact unchanged receiving destinations, and
visible return/quit controls. Receiving addresses were not reproduced in this report
or the user-facing verification summary. No checkout was opened.

This is a **tested source-built preview**, not replacement of the installed native
Mac app or its bundled CLI. The working phone and canonical Mac installation were
not reinstalled or restarted. No physical miner, mining-Mac service, pool, tuning,
firmware, or power setting was changed. The prior native 18-phase audit and Sonar
analysis remain historical evidence for their original source, not a new full
native certification of this CLI change. No new Sonar upload was performed.

The owner reported restored iPhone Mirroring at 09:06 UTC after the iOS update.
Read-only inspection no longer showed the prior authentication prompt, and a
Stage Manager thumbnail showed the mirrored phone home screen. This corroborates
connection restoration, not a new physical-phone Hash Fleet tap-through.

## Evidence references

Owner-private scratch build: `~/.jcode/scratch/hashfleet-cli-support-20261102-0909/`.
Background receipts retained in this session:

- Initial successful CLI build: `7143908czq`.
- Initial Support boundary failure: `906384d6qa`.
- Initial unchanged CLI/core/lint passes: `9063849nxd`, `90638495x1`, `906384h584`.
- Final rebuilt Support acceptance: `143517qyfj`, exit 0.
- Final full core/unchanged CLI/parity/lint/integrity acceptance: `1435181qou`, exit 0.

Protected shared crypto source SHA-256:
`adbd98839b425f1f1fa7858a1d160ea366f8e9e0bc6a32baf111f3e3691b5344`.
