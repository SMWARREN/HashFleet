# Free Swift analysis: scope and safeguards

Checked October 31, 2026. This documents the existing local setup, not a claim of parity with SonarSource's commercial Swift analyzer.

## Current verified setup

- Local SonarQube reports version `26.9.0.129388`.
- Installed `sonarapple` plugin: `0.5.1`. The server registers the `swift` language and the project's Swift profile has 263 active rules.
- Local SwiftLint: `0.65.1`. Local SonarScanner CLI: `8.3.0.16463`.
- The upstream sonar-apple release page still identifies `0.5.1` as its latest stable release. `0.5.2-SNAPSHOT` is a prerelease, not an upgrade recommendation.
- No server, plugin, package, paid service, quality threshold, exclusion, or new-code baseline was upgraded or relaxed in this work.

## What the free combination actually does

SonarSource documents Swift analysis for SonarQube Server 2026.5 as starting with Developer Edition. Our Community installation instead uses the third-party sonar-apple plugin for language registration, metrics, SwiftLint findings, and real Xcode test/coverage imports. Swift package coverage is converted from observed LCOV line hits, while Python tooling coverage is imported separately.

The plugin advertises Swift 5 syntax support. Its bundled rule catalog and parser are not proof of full Swift 6 semantic or security coverage. The upstream changelog's SwiftLint rule update references 0.53.0, older than our installed SwiftLint. A clean plugin dashboard therefore cannot replace an independent current SwiftLint run.

`swiftlint lint` and `swiftlint analyze` are different commands. The configured `unused_import` analyzer rule requires a separate type-checked analysis using a clean compiler log. Merely listing it in `.swiftlint.yml` does not execute it during lint. Neither compiler success nor zero lint findings proves the absence of bugs or security vulnerabilities.

## Improvements implemented

1. An authenticated, read-only preflight fails before publication unless the selected server has the expected sonar-apple version and actually registers Swift. Credentials stay in environment/header authentication and are not echoed in errors.
2. The scan independently runs `swiftlint lint --quiet --strict --reporter json` against the repository configuration. Warnings and errors stop publication without disabling rules. The latest report is `build/sonar/swiftlint-current.json`.
3. The scanner now waits for the server's quality gate by default and preserves scanner/gate failure exit status. Explicit caller arguments remain explicit overrides and must be recorded when used.
4. `SONAR_REQUIRE_TESTS=1` prevents accidentally publishing a scan without selecting `SONAR_RESULT_BUNDLE`. This checks selection, not test success, exhaustive execution, or source provenance. The caller must independently verify those against fresh enumeration and result summaries.
5. Regression tests cover missing/mismatched plugins, missing Swift registration, HTTP/JSON/schema errors, token privacy, local lint failures, missing result bundles, quality-gate exit propagation, and preservation of an existing server's analysis data.
6. Configuration comments now distinguish lint, type-checked analysis, test execution and coverage instead of calling them equivalent to commercial Swift analysis.

## Remaining boundaries

- A green quality gate is not an all-tests-passed certificate. Report failed and skipped tests independently, including failures observed on other runtime/device configurations.
- A selected `.xcresult` can be old or incomplete. Preserve source revision, fresh test enumeration, actual executed identities and coverage provenance in the delivery report.
- The October 31 final scan reported 733 tests in its aggregate measure despite independently verified execution of all 1,447 native unit identities plus Mac/UI checks. Treat the plugin aggregate as incomplete, not as the exhaustive test census. The retained dashboard failure was imported correctly. See `MINER-CONTROLS-TUNING-AUDIT-2026-10-31.md` for exact results, coverage and remaining UI boundaries.
- CLI process success does not prove every SwiftLint rule exists in the plugin's older catalog. The independent strict lint gate addresses enforcement but does not add those rules to the Sonar UI.
- No separate `swiftlint analyze`, Periphery, or mobile-security analyzer has been added or claimed as executed. These need their own toolchain/target validation before adoption.
- The current bootstrap still uses a floating Community Docker image for a new server. Do not treat that as a tested upgrade path. Existing servers are never removed or restarted by the scan script.
- Swarm review was attempted: three automatic workers failed before inference with provider payload errors; the research worker exceeded its bounded review period without an accepted deliverable and was stopped. There is no accepted independent swarm approval for this change. Routing and accounts were not overridden.

## Primary sources checked

Google access was attempted but returned an access/interstitial page; the browser bridge was unavailable. Research used web search and the primary project/vendor pages below, not an invented Google result.

- SonarSource Swift edition and language support: https://docs.sonarsource.com/sonarqube-server/analyzing-source-code/languages/swift
- sonar-apple capabilities and Swift 5 support statement: https://github.com/insideapp-fr/sonar-apple
- sonar-apple stable and snapshot release status: https://github.com/insideapp-fr/sonar-apple/releases
- SwiftLint command and analyzer documentation: https://github.com/realm/SwiftLint#analyze

## Reproducible invocation

Keep `SONAR_TOKEN` private in the environment, select the newly verified result bundle, and run:

```sh
SONAR_REQUIRE_TESTS=1 \
SONAR_RESULT_BUNDLE=build/CURRENT_VERIFIED_RESULTS.xcresult \
bash Tools/sonar-scan.sh \
  -Dsonar.coverageReportPaths=build/sonar/CURRENT_CORE_COVERAGE.xml \
  -Dsonar.python.coverage.reportPaths=build/sonar/CURRENT_PYTHON_COVERAGE.xml
```

The paths above are explicit placeholders, not previously verified results. Do not copy an old bundle into a new validation claim.
