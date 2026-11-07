# Rollout verification and automation repairs, November 2, 2026

## Delivery state

The existing App Store Connect en-US draft display name was saved and independently reread as **Hash Fleet**. It remains a draft. No build was uploaded or submitted, no new app record was created, and no bundle identifier was changed. See `APP-STORE-NAME-2026-11-02.md`.

The canonical Mac app and physical iPhone app have not been replaced during this rollout. Saved app-owned data was backed up and checked before any proposed installation. Publication and installation remain gated on a fresh complete passing audit.

## Retained failed audit

The fifth complete audit of `b1258c94c49c73b731aa9b0663c45fa5d73e5e5a` ran all 18 original phases from 11:26:49 to 12:05:05 UTC. Seventeen phases passed. The broader UI phase executed three tests, with one failure. All three native unit shards, native Support, SwiftPM, CLI and packaging phases passed, but the whole audit remains **failed**.

The failing numeric-share test first verified the expected `392.00M` and `1.23M` values. It then attempted to return to a miner card above the global Best Share card. Native activities and the retained screenshot show the original `reveal` helper repeatedly scrolling toward the page footer. Production dashboard order puts miners before fleet tools and the global Best Share card. This evidence supports a navigation-helper defect, not moving production sections to satisfy the test.

A separate unchanged eight-test interactive Support run had one footer-visibility failure. The standalone four-test Support and two-test destination-parity suites passed. A bounded diagnostic of 20 actual PTY sessions observed two reads with an incomplete frame and no footer yet. All 20 completed frames included the footer. The original frame ended with the existing `ESC[J` marker.

## Infrastructure-only repair

- The native `reveal` helper now prefers the target's exposed position, searches both scroll directions within bounded limits, and retains the original reachability assertion and failure screenshot.
- The Support PTY helper waits for the newest frame's existing completion marker. It cannot reuse an earlier frame or pretransition output.
- Four deterministic regression tests cover split frames, stale terminators, transition offsets and stale labels.
- Original native test identities, the complete audit recipe, production code, receiving destinations, package lockfile and all original acceptance assertions are unchanged. All eight original interactive Support test bodies are AST-identical.

The four deterministic regression tests and two consecutive complete eight-test interactive Support runs passed after the helper repair. A fresh native build and all three unchanged broader UI cases also passed at 12:33:17 UTC. These focused results do not replace or reinterpret any failed full-audit receipt.

## Sixth audit and observation timing

The sixth audit tested commit `7ab0153c86f958c08f8afea7d3fd91fc3c5aa3b7`. Its outer launcher was terminated by the tool's 600-second timeout. The independently running original recipe was observed without restarting any phase. It completed all 18 phases by 13:17:25 UTC, with 15 passing and three failing. No successful source-bound receipt was produced, and the failure remains retained.

- The celebration readiness failure retained actual early, dim pixels with `0.00M`, not the final `9.20M`. The harness checked the analysis-completion clock after expensive OCR, so a stale entrance frame could consume the entire observation window without a final capture. The repair timestamps the actual pixels and requires an unmet capture at or beyond the same three-second boundary before timing out. It never supplies expected copy to Vision or changes the production celebration.
- The motion negative control captured only about 17.37 points of its intended 40-point movement because its automatic timer could start before baseline OCR completed. The fixture now explicitly arms the same 40-point, 0.5-second animation after baseline capture. The original different-pixels and greater-than-20-point assertions, observation delay and all production information-page stability checks are retained. A new regression also holds the unarmed baseline beyond the old timer before checking real movement.
- The 54-column CLI detail check read a frame ending midway through a UTF-8 footer. The shared terminal reader now waits for the newest frame's own existing `ESC[J` terminator. All 18 original dashboard test bodies and eight original interactive Support test bodies remain unchanged. Five additional deterministic cases cover fragmented UTF-8, stale screens, split terminators, snapshot output and transition offsets.

At 13:31 UTC, all nine deterministic PTY helper regressions and strict SwiftLint passed. Native timing and original acceptance reruns, and a fresh complete passing audit, remain required. No failure was relabeled, excluded, automatically retried or published as green. The original native identity manifests, audit recipe, production code, receiving destinations and package lockfile remain unchanged.

## Evidence and remaining work

Private receipts and original failures are retained under the rollout's nonindexed scratch directory. Raw receiving destinations and clipboard values are not included in this document. Earlier infrastructure failures remain separate records, not successful tests.

After native and full-audit validation: publish only a normally gated new Sonar analysis, install in place while preserving identity and data, verify physical-phone Support without payment, and reversibly retire generated test applications. The latest Mirroring inspection at 12:13 UTC found no open Mirroring window, so physical-phone interaction has not been claimed complete.
