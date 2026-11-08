# History page cache metadata correction, November 8, 2026

## Scope

The requested `avdlee/swiftui-agent-skill` review identified a cache dependency mismatch. `FleetHistoryPageIdentity` represented history signatures, selected range/display/kind and database revision, but omitted device names, addresses and per-device kinds. `minerSeries` consumes names and duplicate-name address suffixes, while `chartDevices` consumes per-device kind. Reusing the same cache after metadata-only changes could therefore return stale labels or series membership.

This is a dataflow/cache correctness issue. It is not established as the cause of the original Swift Charts `HashableText` SIGTRAP, the iPhone background scene-create watchdog, or a Mac panic.

## Changes

- `9f3b08a`: behavior-preserving internal `pageData(for:cache:)` seam and six production-path regression cases. The default caller delegates with the same existing `pageDataCache`. Private identity construction and page-data building remain private.
- `2dc9eed`: mandatory ordered device metadata (`id`, `name`, `address`, `kind`) in the page identity. No default empty metadata or mutable fallback is provided. The sole existing synthetic identity initializer explicitly passes an empty array without changing its revision assertions.
- No telemetry dropping, date normalization, chart mark changes, buffer policy changes or unit thresholds were introduced.

Ordering was already represented by ordered history signatures. Its test is a positive control, not a newly claimed ordering defect.

## Observed native regression evidence

Owned iPhone 18 Pro Max simulator, iOS 27.0, optimized app-hosted Swift Testing. These are not physical-device results.

| Condition | Source | Selected suite | Observed outcome |
| --- | --- | --- | --- |
| Before metadata correction | `9f3b08a`, candidate14 | `FleetHistoryPageCacheMetadataTests` | Six tests, five failed metadata assertions, one ordering control passed. Real xcodebuild exit 65. |
| After metadata correction | `2dc9eed`, candidate15 | Same suite, unchanged test source | Six tests passed, zero failed. Real xcodebuild exit 0. |

The cases cover rename, duplicate-name introduction, duplicate-name resolution, duplicate-name address mutation, ordering, and a per-device kind change with the same active kind and unchanged UUID/history inputs.

The before-run failures contain the actual stale values, including `Alpha` instead of `Beta`, old address suffixes and a single history ID instead of two. Both run receipts report owned children and simulator app stopped, unchanged source/binaries and no cleanup errors. The six-case test file has the same SHA-256 in both source identities and the committed regression source.

Evidence is retained under the owned scratch workspace `hashfleet-stability-20261108T0110.noindex/results/`:

- `native-stability-cache-metadata-red/`: receipt, stdout, `Tests.xcresult`, exported test summary.
- `native-stability-cache-metadata-green/`: corresponding green evidence.
- `source-identity-candidate14-cache-red.json`: SHA-256 `f15f3f2e720c22256ca90da04a6588110bf12b700d0fe3e49cc3636d209245b7`.
- `source-identity-candidate15-cache-green.json`: SHA-256 `b9c21cdac267c329a5a164eeecb14d9903acde0b1977da2b198bd1656bdb08e9`.

The green diagnostic target also compiles the existing history-rendering tests. A separate run of `FleetHistoryRenderingTests` passed all nine cases (0 failed), including data-revision invalidation, time-boundary/clock-rollback behavior and full-resolution reuse. The first attempt failed before test launch because an exclusive fixture port had not yet released. That failed receipt is retained; after all 20 ports were verified bindable without reuse, the same suite succeeded in `native-stability-history-rendering-green-retry/`. No rendering assertions were changed.

Whale independently verified the red and green six-case results, their source identities, unchanged test hash and the scoped production diff. It also verified the separate nine-case rendering pass, matching source/binary hashes and stop/immutability gates, and the preserved pre-test fixture failure.

## Limits

The regressions explicitly share a cache between view values and execute real production identity/series code. SwiftUI warns that selected-kind `@State` is read without installing those test view values. This matches the stated dataflow-only scope: it does not demonstrate a retained installed card across a user edit, rendered AttributeGraph behavior, or crash freedom.

The original accessibility streaming discriminator remains failed at its unchanged 180-second deadline. Its interrupted xcresult did not finalize, so no complete 24-snapshot metrics were exported. Owned children and app were stopped and input immutability verified. Fixture egress totals do not establish continuous app ingress or per-snapshot overlap. That failed result has not been replaced or relabeled as passing.
