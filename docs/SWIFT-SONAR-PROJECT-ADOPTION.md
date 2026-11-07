# HashFleet whole-project Swift Sonar Kit adapter

The existing `Tools/sonar-scan.sh`, server, profiles, and app behavior are unchanged. The reusable toolkit lives in the separate sibling `swift-sonar-kit` repository. This adapter selects HashFleet's reviewed recipe, rather than substituting a Swift-only source list.

## Commands

The preferred one-step entry point runs SwiftLint and Sonar source analysis only. It prepares supported analyzer dependencies automatically, but does not build the app, launch simulators, run tests, collect/import coverage, require native test manifests, or create a Python coverage environment:

```sh
cd ../swift-sonar-kit
./scan "/path/to/hashfleet"
# Dependencies only, without running lint analysis, tests, or Sonar:
./scan "/path/to/hashfleet" --setup-only
```

Change the project path for your checkout. Valid SwiftLint findings still proceed to Sonar and leave the overall result nonzero. Tables remain the default, and the full result is saved at `.swift-sonar/run-result.json`. `--setup-only` saves a separate `.swift-sonar/setup-result.json` and preserves prior scan reports. `--plan-only` remains read-only with no tool probes or downloads. Git and a suitable SwiftLint developer toolchain are required. Docker is required only for automatic local-server use. The reviewed source/test scope is preserved, but native and coverage report properties are omitted from the effective source-only settings without changing the original files.

## Advanced explicit test-driven adapter

The manual commands below are a separate opt-in full audit, not what `./scan PATH` runs. They retain the selected Xcode/simulator prerequisites, native manifests, test phases and real coverage validation, and do not perform automatic dependency setup.

The selected Python 3.11+ interpreter must have `coverage.py` installed. The recipe selects Python using this precedence:
1. An explicit nonempty `PYTHON` environment variable is respected strictly.
2. The project-local isolated environment `.swift-sonar/python/bin/python` is preferred if executable.
3. Otherwise, the existing default `python3.12` is used.

To create the isolated project-local environment with the required coverage dependency:
```sh
python3.12 -m venv .swift-sonar/python && .swift-sonar/python/bin/pip install 'coverage==7.17.2'
```
Because `.swift-sonar/` is git-ignored, this environment stays project-local and does not modify global tools.

To verify toolchain and Python prerequisites without running tests, creating build directories, or triggering collision checks:
```sh
bash Tools/sonar-project-test.sh --check-prerequisites
```

```sh
# Fresh full configured audit. No Sonar publication.
PYTHON=.swift-sonar/python/bin/python bash Tools/swift-sonar-kit.sh project-test

# Test, strict lint, validate, and publish. Requires SONAR_TOKEN in the environment.
PYTHON=.swift-sonar/python/bin/python bash Tools/swift-sonar-kit.sh project-run

# Explicit diagnostic audit/publication retaining known failed tests.
# This still exits nonzero when tests fail, even if Sonar's gate passes.
PYTHON=.swift-sonar/python/bin/python bash Tools/swift-sonar-kit.sh project-run --publish-failed-tests

# Check a completed diagnostic audit locally without contacting Sonar.
PYTHON=.swift-sonar/python/bin/python bash Tools/swift-sonar-kit.sh project-scan --publish-failed-tests --prepare-only
```

Set `SWIFT_SONAR_KIT_ROOT` if the toolkit is not a sibling checkout. The adapter defaults project commands to `Tools/swift-sonar-project.json`. A different reviewed recipe can be selected with `--config`. For comparison, `project-scan --project-key <isolated-key>` changes only the destination project, not source/test classification.

Outputs live in ignored `build/swift-sonar-project/` and `.swift-sonar/`. Existing test artifacts are never overwritten: deliberately move the previous output directory aside before another run. Do not edit source, recipe, manifests, toolkit implementation, or toolchain between testing and scanning. Receipts bind these inputs and the report bytes. They are local unsigned evidence, not a sandbox or cryptographic attestation.

## Advanced audit scope (not the default scan)

The recipe performs a fresh iOS test build, three class-disjoint iOS unit shards, native Mac tests, seven tuning UI tests, three broader dashboard UI tests, native result merging, SwiftPM tests and coverage, a fresh release CLI build, Python Tools tests, CLI dashboard/settings/firmware-activity suites, and Mac packaging tests. Independent phases continue after a failure, preserve logs and exit codes, and leave the overall audit failed.

The retained reference audit has 1,447 iOS logical cases, 118 Mac logical cases, and 10 UI cases. Parameterized native execution totals 2,337 instances. Checked-in manifest files are JSON arrays of exact identities, not counts. The merged manifest additionally binds platform, OS, device name, configuration, and target. Changing simulator/runtime or test identities requires a reviewed manifest update, not automatically accepting observed output. The reference recipe uses iPhone 16 Pro Max for unit shards 1 and 2, iPhone 17 Pro for shard 3 and UI, and native macOS for Mac tests. Overrides include `HF_UNIT_DESTINATION`, `HF_IOS_DESTINATION`, and `HF_MAC_DESTINATION`.

The earlier non-native audit counted 337 SwiftPM tests, 93 Tools tests, and 66 CLI/packaging tests. Fresh run logs, not these historical counts, are authoritative. This is the established audit scope, not all 182 UI tests and not a claim of 100 percent code coverage.

## Historical advanced-audit failure

`CompactDashboardUITests/testAccessibilityTickerExposesStaticUntruncatedMinerSummaries()` failed in the reference audit and in an unchanged focused rerun. It expects three ticker accessibility elements while the dashboard no longer embeds that ticker. This integration does not restore an old UI design, remove the test, or reinterpret its result. Default publication fails closed. Explicit diagnostic mode can retain and publish complete failed evidence, but its final status and exit code remain failed.

## Host and Docker boundary

Xcode, simulators, SwiftPM, SwiftLint, and Python coverage execute on macOS. Docker may run the SonarQube server. Pointing a Linux container at a Swift repository does not make it able to run Xcode tests. The recipe preserves all existing scanner source/test roots, Python settings, exclusions, native Sonar Apple imports, SwiftPM generic coverage, and Python coverage. Strict SwiftLint remains an independent gate before publication.

Full old-versus-new scanner parity must be established using the same fresh artifacts, source revision, server/plugin/profile, and tool versions. Matching a green gate alone is insufficient. See the toolkit's verification report for the actual completed checks and remaining limitations.
