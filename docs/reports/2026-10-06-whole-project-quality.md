# Whole-project quality verification, October 6, 2026

## Outcome and remaining gate

The local SonarQube server processed the final analysis successfully at **09:19:48 UTC**. The scan reports **zero unresolved issues**, including zero reported bugs, vulnerabilities, code smells, security hotspots and complexity-rule findings. Reported duplication is **0.0%**.

**The quality gate is still ERROR, not green.** New-code coverage is **48.6%**, below the unchanged **80%** requirement. Overall reported coverage is **48.4%**. New violations and new duplication pass their existing gate conditions. No source exclusions, rules, baseline dates or coverage thresholds were weakened to obtain these results.

Zero reported findings does not mean the application is independently proven bug-free or that unexecuted paths have been tested.

## Source revision and analysis identity

- Tested source revision: `1881dcb03ad06bb26ab6ef669ff9f0e505ef1382`.
- Compute-engine task: `566b8eb1-e444-4d5c-ab2a-fc19489b90cd`, status `SUCCESS`.
- Analysis: `290a5bc9-2d8b-4d37-9e3c-9bc6a6f09079`.
- SonarQube: local Community server, version `26.9.0.129388`.
- Native plugin: `insideapp-fr/sonar-apple`, version `0.5.1`.
- Native issues independently checked with strict SwiftLint `0.65.1`.
- Scanner indexed **487 files** across source and test inputs. Server measures report **253 source files** and **37,617 non-comment source lines**.

## Whole-project scope

Production scope is `App`, `Shared`, `Sources`, `Widgets`, `MacMenuBar`, `PushProvider`, `Tools` and `Scripts`. This includes the iOS/Mac application, core library and CLI sources, menu-bar application, widgets, push extension and repository tooling.

Tests are path-scoped to `AppTests`, `Tests` and `UITests`. The earlier blanket Swift test pattern incorrectly removed production Swift from source analysis. That first scan is **not** accepted as native zero-finding evidence. It was corrected before the production-inclusive baseline and both final analyses.

Existing generated/build/document exclusions were retained unchanged. The native lint scope was expanded to cover `MacMenuBar` and `PushProvider`.

## Findings fixed

The valid production-inclusive baseline had eight Python findings: one direct floating-point equality check, two loop-variable closure captures, one redundant exception type, three assertions with more than one potentially throwing expression, and one function with cognitive complexity 21 against the rule's limit 15.

The fixes use `math.isclose`, explicitly bind closure defaults, retain the correct `OSError` handling, move fixture construction outside exception assertions, and separate acceptance verification into cohesive parsing/evaluation helpers. Regression tests cover the refactored acceptance checker.

The scan runner now refuses to delete/reset an existing unavailable Sonar container, requires SwiftLint, forwards caller arguments safely on macOS Bash 3.2, and imports a supplied real Xcode bundle using a project-relative path. Isolated mock-based tests cover the relative path conversion, missing bundle, empty-argument path and refusal to remove/restart an existing server. They neither contact Sonar nor delete real service data.

A nested closure's existing strong connection capture in the loopback UI-test server was made explicit. This removed the compiler capture warning without changing the intended connection ownership. The native tests and four foreground-notification UI workflows passed afterward.

## Test evidence

| Check | Observed result |
| --- | --- |
| Complete app unit contracts | 731 Swift Testing tests in 74 suites, plus five XCTest preference-checkpoint tests, passed |
| Final foreground-notification acceptance | Four simulator UI workflows passed with zero failures |
| Core library contracts | 198 tests in 23 suites passed with coverage enabled |
| Complete Python tooling suite | 26 tests passed |
| Strict whole-scope SwiftLint | Zero findings |
| Shell syntax and staged diff checks | Passed |
| Native test warnings | Only the non-source AppIntents metadata extraction notice remained |

An earlier broader legacy UI run timed out and has stale assertions. It is not presented as a passing full UI suite. Sonar imported 960 native test executions, not an authoritative count of all defined tests: its older importer could not associate four suite/class names with source resources. The actual Xcode result bundle and test logs are the primary acceptance evidence.

## Genuine coverage imports

The final scan imported both:

1. `native-quality-final.xcresult`, produced by the complete app unit run and four notification UI workflows with code coverage explicitly enabled. The Xcode coverage sensor parsed 308 coverage-bearing files before applying source scope.
2. Original LLVM LCOV physical-line execution records from the existing coverage-instrumented core test executable. The generic coverage sensor imported **42 owned Sources files**. Test/vendor records were not used as production coverage.

The core converter preserves the original `DA` line-hit records rather than inventing execution for missing entries. It checks that LLVM's LCOV `LF`/`LH` aggregate headers match the independently exported LLVM JSON summaries, validates source paths, and round-trips the generated XML. The observed representations differ: the JSON/header aggregate is **4,084 covered / 5,101 lines**, while the physical `DA` records contain **3,200 covered / 3,948 lines**. Both original reports are retained. Neither value is silently substituted for the other.

The source-only native Xcode report contains 19,311 covered lines out of 51,255 executable lines across App, Shared, Widgets and PushProvider. It does not include Sources or the menu-bar target in that native result. Core test coverage was therefore imported separately. These instrumenter-level line denominators differ from Sonar's coverage measure and are not represented as the same percentage.

Coverage of the core library is not proof that every CLI entry point or command has executed. Widget, menu-bar and push-extension workflows are not fully exercised by the selected simulator UI tests. Tooling tests passed, but this scan did not import a Python coverage report. These are genuine coverage gaps, not reasons to exclude production code from the gate.

## Complexity interpretation

The final scan reports zero **complexity-rule violations**, not zero total control-flow complexity. Aggregate cyclomatic complexity is **2,123** and aggregate cognitive complexity is **142**. Aggregate counts include normal functions and branching and are different from a rule violation count. The acceptance checker was refactored to remove its reported cognitive-complexity violation without suppressing the rule.

## Analyzer limits

Swift source, SwiftLint, Xcode tests, Xcode coverage, Xcode warnings, generic core coverage, Python and text/secrets sensors ran. Optional Periphery and MobSF tools were not available and are **not** claimed to have performed independent unused-code or mobile-security audits.

The older native parser emitted eight text-range mapping warnings in `FleetLocalNotifications.swift`; it also emitted test-file duplication and four test-resource association warnings. These warnings are retained in the scanner log. Native strict lint and compiler/test validation passed independently, but the plugin is not a certification of complete modern-Swift semantic or security analysis.

No miners were restarted, reflashed, retuned or queried by this quality workflow. The deployed application remains build 6. Changes after its delivery affected tooling, test-server capture annotation and documentation, not its production app source.

## Owner-private evidence

Generated logs, JSON API responses, coverage exports, the validated conversion script and original result bundles remain in the session scratch directory `hashfleet-foreground-20261006`. The final log is `sonar-final-native-core.log`; machine-readable verification is `sonar-combined-summary.json`. No authentication token, wallet, password, Wi-Fi credential or raw device export is included here.

A green coverage gate requires additional genuine tests and workflow coverage. This report intentionally stops short of claiming that gate has passed.
