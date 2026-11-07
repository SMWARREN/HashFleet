# Public source preparation

Prepared November 7, 2026 as an independent source workspace. Nothing has been uploaded.

## Source and preservation

This snapshot contains the current tracked working-tree source at development revision `60e5dcd`, including the tracked app changes that were not committed in the development repository. It is not a clone of the old repository history. The original development folder, its untracked work, local signing configuration, Git index, branches and history are left in place.

The preparation copied 1,259 tracked files. It excluded 89 tracked personal-tool/generated files and did not include 334 unreviewed untracked files. The new documentation and edits described below are confined to this separate workspace.

## Omitted from the snapshot

- The original `.git` directory, history, stash, local checkpoints, author email metadata and remotes.
- Personal automation configuration: `.agents/`, `.blitz/`, `.claude/`, `.codex/`, `.mcp.json`, `opencode.json`, `CLAUDE.md` and `skills-lock.json`.
- The tracked generated `swiftlint-report.json` file.
- Ignored local signing material, environment files, production server configuration, databases, build/dependency directories, analysis state, exported applications, archives and packages.
- Unreviewed untracked marketing/screenshot tooling, captures and ZIP exports. They remain in the original folder, not here.

## Sanitization in this workspace only

- Personal absolute home paths in documentation were replaced with `/Users/USER` or `/home/USER` placeholders.
- Physical-device identifiers in historical reports were replaced with `YOUR_DEVICE_ID`.
- The screenshot UI test accepts `HASHFLEET_SCREENSHOT_DIR` and otherwise uses a temporary directory rather than a personal workstation path.
- Private fleet host addresses in source and fixtures were mapped to documentation-only `192.0.2.x` addresses. In particular, the identity-bound Gamma 601a host fixture was changed consistently in the app, CLI and tests. **The 1,150 mV board ceiling, comparison operators, validation branches and risk gates were not changed.** These documentation hosts are not operational miner configuration. Do not treat them as discovered or supported hardware.
- A redaction-test username is generic, and an internal merchant-account description was removed from a support document. Intentionally public support/checkout destinations, GPL text, app identifiers, and source safety rules remain.
- `.gitignore` also excludes common environment variants, signing exports, private keys, profiles, installers, databases and personal automation state. `.env.example` templates remain eligible for source control.

Historical reports remain dated observations, not a new runtime, release or hardware-safety certification. Placeholder commands are not ready-to-run private deployment commands.

## Verification boundaries

Preparation checks cover copied-file integrity, tracked-source completeness against the stated exclusions, targeted privacy/credential patterns, changed-source syntax where available, and original-source preservation. They do not contact miners, run Sonar, launch an app, reproduce a crash, sign a release, or publish to GitHub.

Crash investigation is separate from this source preparation. No private crash logs are included, and no crash fix is claimed by this snapshot.

Completed checks include exact copied-file and exclusion-set verification, targeted privacy patterns, syntax parsing of the six changed Swift files, Python AST parsing, JSON/plist/XML parsing, and an independent read-only review. Original working-tree contents and Git metadata were verified unchanged. These checks are not compilation or runtime acceptance.

The root GPL-3.0 license and upstream API schema license metadata are retained. Research image sets include simulator/loopback captures and AI-generated concepts with recorded provenance. A complete visual privacy review, third-party rights clearance, dedicated secret-scanner pass, dependency security review, fresh app build and device acceptance remain pre-publication/release checks. Pattern checks are not a guarantee that every possible secret format has been detected.

Before publication, inspect the exact new repository contents, configure your own local signing and bundle identifiers, and decide which nonessential research/marketing assets to distribute. Do not add the original development history, private log exports or production settings to this snapshot.
