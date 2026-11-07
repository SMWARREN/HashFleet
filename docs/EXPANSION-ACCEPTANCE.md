# Pool and network expansion acceptance

Scope: the September 6/7 HashWatcher screenshot audit and follow-up requests for home best shares, per-chain odds, configured pool/account data, safe firmware detection, native solo-pool setup and phone installation. This supersedes the old explicit-only compatibility and separate Network-tab interaction requirements. No hardware writes are part of development acceptance.

## Requirement to concrete check mapping

The full-result rerun and observed outcomes are recorded below after execution, rather than inferred from aggregate test counts.

| ID | Requirement and changed public output | Concrete checks and acceptance path |
|---|---|---|
| P01 | Current ESP-Miner method/path coverage, controls retained | `catalogCoversIndependentUpstreamInventoryExactlyOnce`, `methodsPathsTypesAndTimeoutsMatchFirmware`, `everyPoolSlotHasBothMethods`, `everyHTTPOperationTravelsThroughInjectedTransport`; source SHA and 23-current-operation inventory in THIRD-FIRMWARE-AUDIT |
| P02 | Firmware/board/ASIC automatically detected, safe reads only | `autoDetectReusesObservedInfoAndPerformsExactlyOneASICRead`, `autoDetectRunsOnlyOncePerDeviceIdentity`, `autoDetectProbesAgainWhenIdentityChanges`, `failureBacksOffUntilExplicitRetryOrIdentityChange`, `invalidInfoShapeDoesNotTriggerDetection`; native `testManualCheckDistinguishesUnsupportedUnknownModelAndAuthenticationFailure` journals only Info/ASIC GET |
| P03 | Honest unverified endpoint rows, cached timestamps, missing settings, unknown models | `testCatalogStatusesAndLastKnownTelemetryRenderWithoutInventingSupport`, `testMissingFieldsAndReportedReferencesRenderAcrossNativeSettings`; no write support inferred from model or successful Info |
| P04 | Home best-ever/session difficulty, exact maximum not summed | `parsesExactInt64BeyondDouble53BitLimit`, `parsesSISuffixDifficulties`, `preservesZeroAndRejectsNegativeAndMalformedDifficulties`, `selectsFleetMaxNeverSumsAcrossMiners`, `offlineMinersAreExcludedFromBestCalculationAndCounted`; native `testDemoNetworkDataAndLookupRemainExplicitlyOffline` reads home output |
| P05 | BTC price, height, difficulty, hashrate, fee estimates and mempool backlog | `aggregateRefreshUsesOnlyExpectedGETsAndKeepsIndependentSourceTimes`, `optionalFieldsRejectInvalidNumbersWithoutLosingValidSiblings`; `testProductionPublicDataRendersAutomaticallyOnNativeHome` uses real public HTTPS services through the native app |
| P06 | Separate BCH price, height, difficulty, mempool and network hashrate | `bitcoinCashUsesSeparateReadOnlySourceAndPreservesProviderCacheAge`, `bitcoinCashFailuresDoNotBecomeBitcoinValues`; native demo and live home tests assert separately labeled BTC/BCH output |
| P07 | 30-day block odds use correct chain difficulty, no reward/countdown promises, stale cache not fresh | `soloProbabilityUsesStablePoissonMathAndCorrectUnits`, `zeroHashrateAndZeroDurationHaveExplicitMeaning`, `extremeFiniteInputsAvoidIntermediateOverflowAndNaN`, `providerCacheAgeCannotBeRefreshedByNewFetch`, `perChainOddsUseIndependentDifficultyAndRequireFreshness`, `nextCandidateHeightHandlesHalvingAndOverflow`; home comparison explicitly assumes whole online fleet on one chain at a time |
| P08 | All configured slots, fallback, known provider/coin recognition, unknown hosts fail closed | `resolvesPoolsBySlotIDWithPrimaryAndFallbackRoles`, `failsClosedOnMalformedPoolsArrayAndNeverFallsBackToLegacy`, `unknownHostProducesNilCoinAndProvider`, `allDocumentedSoloFury45EndpointsResolveCorrectly`, `allSlotsUseCorrectCoinEndpointsAndDeduplicateAccounts`; read-only real 601 Info observation identifies CKPool BTC primary and SoloFury BCH fallback |
| P09 | Correct pool/account paths, rolling rate, share/best-share/activity display, no wrong-chain wallet transmission | `allSlotsUseCorrectCoinEndpointsAndDeduplicateAccounts`, `fixedAccountPathsNormalizeOnlyTheCorrectChainOffline`, `publicAccountBoundaryRejectsMismatchedCoinAndHostBeforeAnyRequest`, `chainPrefixesAndLegacyFormatsCannotBeSilentlyReusedAcrossChains`, `authorizedConfiguredAccountsDecodeThroughProductionClientsWithoutPrivateOutput`, `absentMalformedAndReportedEmptyWorkersStayDistinct`; native `testConfiguredPoolStatisticsAndSoloPoolPresetAreNativeAndReadOnly` verifies configured BCH account sample and redacted overview |
| P10 | Public errors/404 distinct from offline, no raw response or credentials leaked | `HTTPFailuresAreTypedAndNeverExposeResponseSecrets`, `walletNotFoundIsDistinctFromErrors`, `invalidWalletNeverContactsAnyHost`, `reconfigurationReplacesOldKeysAndErrorsNeverExposeProviderBodies`, `stripsInjectedSecretsCookiesAndCacheWithoutMutatingCaller`, `actualRedirectCallbackNeverForwardsToSecondHost`, `serverFailuresAreTypedAndNeverExposeBodySecrets`, `invalidResponsesAndOverLimitBodiesAreRejected` |
| P11 | Request cooldown, opt-out, demo, cancellation, removal and stale reads | `refreshCooldownPreventsHammeringPublicServices`, `cancellationAndDemoTransitionRejectLatePublicResults`, `demoAndOptOutNeverRequestExternalData`, `unknownPoolAndOfflineSnapshotsNeverAuthorizeLookup`, `configurationChangesAndRemovalCannotPublishDelayedAccounts`; native `testLocalOnlyPreferenceDisablesPublicDataAndAccountLookup` |
| P12 | Home integration without extra tab, sources one tap away, privacy disclosure | `testDemoNetworkDataAndLookupRemainExplicitlyOffline` checks no Network tab and home values; `testLocalOnlyPreferenceDisablesPublicDataAndAccountLookup`; existing About/navigation UI regression validates accessible route |
| P13 | Read-only electrical/thermal/pool/system diagnostics, correct DC/energy units | `efficiencyCalculatesZeroJTHForZeroWattsWithPositiveHashrate`, `percentageParsingEnforcesUpperBoundOf100`, `poolSlotsAreResolvedByIDMatchingActivePool`, `poolURLSanitizationStripsAllUserInfoQueryAndFragment`, `poolConnectionInfoSanitizesSensitiveData`, `electricalClocksDistinguishConfiguredFromMeasuredClocksAndVoltages`; native `testReadOnlyDiagnosticsExposeUnitsWithoutChangingSettings` verifies DC-current and energy-estimate wording |
| P14 | Native solo-pool presets, correct host/port, no reused wallet, empty-slot selection, reviewed writes only | `mappingsMatchOfficialStandardSV1Endpoints`, `anyDifferentPresetClearsPreviousWalletIncludingSameCoinDifferentProvider`, `slotIDsAreNotArrayOffsetsAndReportedRolesRemainUnchanged`, `assignedButMissingRoleSlotsAreNeverAutomaticallyReplaced`, `unknownOrMalformedReportsDoNotClaimAnEmptySlot`, `allEightSlotsAreFullAndSevenIsAValidFinalSlot`, `presetDraftStillRequiresWalletAndFullReplacementAcknowledgementBeforeJSONReview`; native preset test checks BCH host/7070/empty wallet and disabled unacknowledged review |
| P15 | Existing widgets, controls, polling, fleet storage and app navigation not regressed | Complete native/core/UI suite, including `testDemoDashboardAndNativeNavigation`, `testLargestDynamicTypeKeepsMinerNavigationReachable`, `testDemoMinerToolsCannotWrite`, `persistenceSavesAndRestoresAllSettings`, `encodedAndPersistedPayloadContainsOnlyApprovedAggregates`. No tests are removed to excuse an implementation failure |
| P16 | Deliver latest native app to requested phone | Signed device build, strict app/extension signature check and exact App Group entitlements, successful devicectl install. Launch status recorded separately, not inferred from installation |

## Current observations

- Current upstream route re-check and official pool documentation are verified. No new ESP-Miner endpoint gap found.
- Integrated native unit run `build/native-unit-expansion.xcresult` passed 320 expanded tests, zero failed/skipped. Later privacy/identity changes require the final whole-result rerun below.
- Repaired targeted native UI run `build/native-ui-repair.xcresult` passed all nine paths, including real public BTC/BCH home output. The first run caught a SwiftUI ancestor accessibility identifier overriding child identifiers, and outdated compatibility-summary expectations. Those were fixed, not bypassed.
- Root full core rerun at 2026-09-07 00:40:04–00:40:05 UTC passed **138 tests in 17 suites**, with all three live suites explicitly enabled. `build/expansion-final-core.log` records real BTC height 965855, fee 1 sat/vB, backlog 77281, BCH height 967403 and separate difficulty 432104766374.43. Public CKPool and SoloFury summaries decoded. Both authorized configured accounts returned **found: CKPool/BTC and SoloFury/BCH**, using the real 601 configuration without logging its addresses or contacting the miner again.
- The first completed full native regression passed 336 expanded cases and failed the largest Dynamic Type miner-navigation case. A direct home “Your miners” jump fixed the observed reachability problem, and the exact accessibility case then passed in `build/expansion-accessibility-fix.xcresult`. The complete release rerun on this exact executable source passed **197 native test functions / 337 expanded cases**, zero failures and zero skips, at 2026-09-07 01:02:20 UTC (`build/expansion-release-acceptance.xcresult`). Source `cffbd6ed38c0afe65a3a0bfc15b964373e8d6124` was signed and installed on the requested iPhone at 2026-09-07 00:57:22 UTC. Strict signatures and exact `group.app.hashfleet.shared` entitlements passed for app and widget. Remote launch at 00:58 UTC was denied because the phone was locked, not because installation failed. Physical phone UI observation remains blocked by that lock. The signed app/extension build already passed strict signatures and exact HashFleet App Group checks. No phone launch is inferred from signing or installation.

## Explicit boundaries

- BTC and BCH have home market/network odds. BC2/BCH2/XEC have known pool/coin lookup and presets, not invented prices or independent market feeds.
- Public statistics access is not proof of a payout, confirmed block ownership or wallet balance. Solo shares do not share in other miners' rewards.
- Multi-vendor firmware, solar/remote automation, Watch and arbitrary executable scripts are not implemented or claimed. Native presets cover requested configuration convenience while preserving confirmation gates.
- Tests against loopback miners or intercepted sessions do not prove a physical miner accepted every write. No voltage/fan/pool/firmware write or restart is performed for acceptance.

## Final observed results

The final whole-result core and native runs were matched by name with `Tools/verify_expansion_acceptance.py`. All **73 distinct mapped checks passed**. The verifier was also exercised against the actual earlier failed result and correctly rejected its failed accessibility case. Full named outcomes are retained in [EXPANSION-CHECK-RESULTS.txt](EXPANSION-CHECK-RESULTS.txt).

| Requirement | Observed result |
|---|---|
| P01 | Current upstream inventory and method/path/transport assertions matched. No current API route gap found. |
| P02 | Normal recognized Info reused, exactly one automatic ASIC GET per identity, no demo probe. Native retry transitioned through unsupported, supported unknown model and authentication failure without a write. |
| P03 | Native catalog kept nonprobed operations unverified. Missing fields stayed “not reported,” and cached compatibility data retained its check timestamp. |
| P04 | Native home rendered demo best 18.4G. Integer/Decimal checks preserved exact large values and selected maximum rather than summing. |
| P05 | Real HTTPS BTC data automatically rendered in the native home. Source details exposed actual fees and backlog. Core production parsing also returned height 965855 and fee 1 sat/vB during its observation. |
| P06 | Native BTC and BCH rows rendered separately. Real BCH production response returned height 967403 with its own difficulty and provider cache time, never a relabeled BTC value. |
| P07 | Native rows displayed separate percentages. Math/freshness tests rejected stale source caches, handled zero/extreme inputs and candidate-height halving boundaries. |
| P08 | Real 601 configuration resolved CKPool/BTC primary and SoloFury/BCH fallback. Slot-ID, all 45 documented regional SoloFury hosts and malformed/impostor rejection checks passed. |
| P09 | Both actual configured account requests returned found. Native BCH demo disclosure showed account rolling rates, 24-hour rate and reported workers with a redacted address. No full payout address was printed in live evidence. |
| P10 | Intercepted production URLSession stripped injected secrets/cache and stopped actual redirect callbacks before a second-host request. HTTP failures remained typed and secret-free. |
| P11 | Opt-out/demo produced no external requests. Cooldown deduplicated accounts. Removal, reconfiguration and cancellation did not publish delayed stale-account results. Native local-only lookup remained disabled. |
| P12 | Home retained Fleet/Settings/About, not another Network tab. Home source-details navigation opened successfully. |
| P13 | Native diagnostics explicitly labeled continuous-draw energy as an estimate and current as not mains current. Unit checks preserved zero, sensor sentinels and sanitized pool output. |
| P14 | Native BCH preset prepared local slot 2, host bch.solofury.com and port 7070 with an empty wallet. Review remained disabled without replacement acknowledgement. No preset applied a hardware change. |
| P15 | Final complete native suite passed, including original settings/widget/storage regressions and maximum Dynamic Type navigation using the direct Your miners jump. |
| P16 | Exact executable source cffbd6e signed and installed on the requested iPhone. App and widget signatures and shared-group entitlements verified. Remote launch was denied by iOS because the phone was locked. |

### Reproduce the named-result mapping

```sh
python3 Tools/verify_expansion_acceptance.py docs/EXPANSION-ACCEPTANCE.md \
  build/expansion-final-core.log \
  build/expansion-release-acceptance.tests.json \
  build/expansion-release-acceptance.summary.json
```

Core evidence uses all three explicit live gates. The native live test uses real public HTTPS services and a loopback miner with no wallet. The separate authorized account test uses the real configured pool identities from a private local Info file. These complement, rather than replace, one another. Physical miner write acceptance was intentionally not attempted, and physical phone UI observation is blocked by its lock. No App Store or public repository publication occurred.
