# Model and telemetry capability matrix

**Evidence date:** 2026-09-06. **Pinned upstream:** [`2943d206f6c8a4b249bc74c820fb56c874ac316d`](https://github.com/bitaxeorg/ESP-Miner/tree/2943d206f6c8a4b249bc74c820fb56c874ac316d). GitHub `master` resolved to this same existing audit baseline. This replacement is source documentation, not physical-device verification. No builds, tests, device access, or mutations were performed for this correction.

The previous matrix's unverified historical cutoffs, oversized synthetic fixtures, mutation examples, and generalized control table have been removed. The facts below come from the pinned source. **Firmware defaults and option lists are references, not safety recommendations, tested combinations, or proof of write support.**

## 1. Built-in family and board matrix

Source: [`main/device_config.h`](https://github.com/bitaxeorg/ESP-Miner/blob/2943d206f6c8a4b249bc74c820fb56c874ac316d/main/device_config.h), ASIC definitions 105–124, families 135–144, board configurations 158–183.

| Reported family | Reported ASIC | Chips | Hash domains per chip | Built-in board versions | Reference default MHz / mV |
|---|---|---:|---:|---|---|
| Max | BM1397 | 1 | 1 | `2.2`, `102` | 425 / 1400 |
| Ultra | BM1366 | 1 | 4 | `0.11`, `201`, `202`, `203`, `204`, `205`, `207` | 485 / 1200 |
| Hex | BM1366 | 6 | 4 | `302`, `303` | 485 / 1200 |
| Supra | BM1368 | 1 | 4 | `400`, `401`, `402`, `403` | 490 / 1166 |
| SupraHex | BM1368 | 6 | 4 | `701`, `702` | 490 / 1166 |
| Gamma | BM1370 | 1 | 4 | `600`, `601`, `602`, `603` | 525 / 1150 |
| GammaDuo | BM1370 | 2 | 4 | `650` | 400 / 1150 |
| GammaTurbo | BM1370 | 2 | 4 | `801` | 525 / 1150 |
| GammaHex | BM1370 | 6 | 4 | `1300` | 690 / 1200 |
| NajaDuo | BM1372/BM1373 | 2 | 4 | `1201` | 327 / 1000 |

- This is the **built-in configuration table**, not an exhaustive list of usable devices or deployed firmware. Do not reject another model/board string simply because it is absent here.
- `ASICModel:"BM1370"` spans one, two and six chips, with different defaults. GammaDuo uses the internal `ASIC_BM1370XP` configuration but still reports `BM1370`. Fetch actual `asicCount`, `deviceModel`, defaults and options instead of deriving them from the ASIC string.
- `hashDomains` describes ASIC hash-monitor domains. It is **not** the board's electrical `voltage_domains` count. Do not use it to scale voltage or power.
- [`main/device_config.c:11–62`](https://github.com/bitaxeorg/ESP-Miner/blob/2943d206f6c8a4b249bc74c820fb56c874ac316d/main/device_config.c#L11-L62) selects a known board configuration or attempts custom NVS family/ASIC lookups. Later code applies hardware overrides. This does **not** prove that an arbitrary unmatched custom configuration safely returns empty option arrays. Do not fabricate that behavior.

## 2. Info versus ASIC

Sources: [`system_api_json.c`](https://github.com/bitaxeorg/ESP-Miner/blob/2943d206f6c8a4b249bc74c820fb56c874ac316d/main/http_server/system_api_json.c), [`asic_settings.c:24–71`](https://github.com/bitaxeorg/ESP-Miner/blob/2943d206f6c8a4b249bc74c820fb56c874ac316d/main/http_server/axe-os/api/system/asic_settings.c#L24-L71).

| Data in this pinned build | GET `/api/system/info` | GET `/api/system/asic` |
|---|---|---|
| ASIC identity | `ASICModel` | `ASICModel` |
| Board/firmware identity | `boardVersion`, `version`, `axeOSVersion`, `idfVersion` | Not emitted |
| Family/chip count | Not emitted as `deviceModel`/`asicCount` | `deviceModel`, `asicCount`, `swarmColor` |
| Reference options | Not emitted | `hashDomains`, `defaultFrequency`, `frequencyOptions`, `defaultVoltage`, `voltageOptions` |
| Configuration and telemetry | `frequency`, `actualFrequency`, `coreVoltage`, `coreVoltageActual`, hash/power/thermal/fan data | Not emitted |
| Runtime chip/domain monitoring | Optional `hashrateMonitor.asics[]`, entries with `total`, `errorCount`, `domains[]` | Not emitted |
| Pools, faults and system diagnostics | Pool configuration/status, conditional faults, partitions, reset reason and more | Not emitted |

Both responses are **flat top-level objects**, not `{data:...}` envelopes. Info contains nested arrays/objects. Only WebSocket live updates use the `event:"update", data:{...}` envelope.

The Info monitor is omitted until `HASHRATE_MONITOR_MODULE.is_initialized` (`system_api_json.c:242–268`). Its absence is **Not reported**, not proof that `/asic` or the model is unsupported. ASIC reference success does not prove successful hashing, sensor availability, or accepted settings writes.

## 3. Wire units and hardware-dependent meanings

The Info JSON serializer forwards the power-management values. Their producer is [`power_management_task.c:135–142`](https://github.com/bitaxeorg/ESP-Miner/blob/2943d206f6c8a4b249bc74c820fb56c874ac316d/main/tasks/power_management_task.c#L135-L142). Units must be traced through [`main/power/power.c:8–48`](https://github.com/bitaxeorg/ESP-Miner/blob/2943d206f6c8a4b249bc74c820fb56c874ac316d/main/power/power.c#L8-L48), not guessed from field names.

| Fields | Unit / interpretation |
|---|---|
| `voltage` | **mV**, input-voltage telemetry. TPS546 path returns `get_vin()*1000`. INA260 path returns its millivolt reading. A wire value `5150` means 5.150 V. |
| `nominalVoltage` | **V**, a family configuration reference, commonly 5 or 12 in this table. Unlike `voltage`, it is not millivolts and not a live measurement. |
| `current` | **mA**, but measurement location depends on hardware. TPS546 path uses **regulator output current** `IOUT*1000`, not board input current. INA260 path uses its current-sensor reading. |
| `power` | **W**, firmware-reported power. TPS546 path computes `VOUT*IOUT + family.power_offset`, a modeled output-power-plus-overhead figure. INA260 path converts its power reading from mW to W. Do not label either universally verified wall power. |
| `coreVoltage`, `coreVoltageActual`, `defaultVoltage`, `voltageOptions` | **mV**. Configured core target, reported actual core voltage, and firmware references respectively. `VCORE_get_voltage_mv` divides TPS546 VOUT by electrical voltage-domain count before scaling to mV. |
| `frequency`, `actualFrequency`, `defaultFrequency`, `frequencyOptions` | **MHz**. Configured target, firmware-reported running clock, and reference defaults/options respectively. “Actual” is not a promise of an independent physical clock measurement. |
| `hashRate`, averaging windows, `expectedHashrate`, monitor rates | **GH/s**, as used by the existing API/app contract. Expected hashrate is calculated, not an independent measurement. |
| `temp`, `temp2`, `vrTemp` | **°C**, subject to hardware source and unavailable/initialization sentinels. Do not guarantee every `temp` is a sensor physically located on the ASIC. |
| `fanspeed`, `manualFanSpeed`, `minFanSpeed` | **%**, distinguishing current fan control, manual setting and automatic floor. `fanrpm`/`fan2rpm` are **RPM**. |
| `displayTimeout` / `statsFrequency` | **Minutes** / **seconds**, respectively. They are not the app polling interval. |

Additional evidence: [`INA260.c:26–62`](https://github.com/bitaxeorg/ESP-Miner/blob/2943d206f6c8a4b249bc74c820fb56c874ac316d/main/power/INA260.c#L26-L62), [`vcore.c:188–193`](https://github.com/bitaxeorg/ESP-Miner/blob/2943d206f6c8a4b249bc74c820fb56c874ac316d/main/power/vcore.c#L188-L193), `main/screen.c` display-timeout handling, and `main/tasks/statistics_task.c` interval handling.

**Consequences:** Do not derive power using `voltage*current` across all families. Those fields can describe input voltage and output-rail current. For Gamma-class TPS546 boards, power already includes the firmware's family overhead estimate. App J/TH based on reported power inherits that model and is not measured wall efficiency.

## 4. Sensor availability is not key presence or chip count

Sources: [`thermal.c:77–132`](https://github.com/bitaxeorg/ESP-Miner/blob/2943d206f6c8a4b249bc74c820fb56c874ac316d/main/thermal/thermal.c#L77-L132), `device_config.h:158–183`, `system_api_json.c:50–62`.

- Info emits `temp2` and `fan2rpm` even on configurations without a second reading. Temperature functions return `-1` when unavailable and before ASIC initialization. Missing/unavailable is not a permanent unsupported-model verdict.
- Fan 2 is read through EMC2302, otherwise the function returns `0`. Zero can also be a genuinely stopped fan. Do not use zero alone as a hardware capability test.
- Hex/SupraHex built-in boards use EMC2302/TMP1075. GammaTurbo/NajaDuo/GammaHex use EMC2103. GammaDuo has two ASICs but EMC2101. Thus two chips do not imply two fan channels or two exposed temperatures.
- `Power_get_vreg_temp` returns `0` without TPS546. `temp` can use EMC2101 internal temperature when configured that way. Prefer “reported temperature” plus source context over unsupported claims of exact sensor placement.

## 5. Endpoint states and control boundaries

`http_server.c:1885–1910` registers Info and ASIC without model-name conditions. Both handlers return 401 for a failed network-access check and 500 for CORS setup failure. Follow `docs/CAPABILITY-CONTRACT.md`:

- Not checked before explicit action. A compatibility check uses only one Info GET and one ASIC GET.
- Recognized response means that **read endpoint responded**, not that every setting or physical component is supported.
- 404/405/501 indicate endpoint unavailable/not implemented. 401/403, throttling, server errors, malformed responses and transport failures are failures, not hardware non-support. Preserve partial success and cancellation semantics.
- Missing fields say **Not reported**. Retain unknown model strings and raw fields. No historical release cutoff for `/asic` availability is established by this audit.

### Corrected semantics, not a mutation guide

| Topic | Pinned evidence and accurate boundary |
|---|---|
| `overheat_mode` | `nvs_config.c:78` has a REST mapping with bounds 0…0. `http_server.c:902–908,991–992` validates and writes boolean values. **It is not firmware read-only: zero/false is writable.** Keeping it read-only in friendly app UI is a safety/product decision, not a claim about firmware permissions. Do not promote a bypass/reset control. |
| Hostname change | `http_server.c:1090–1105` applies the hostname and returns a **JSON `redirect` object** with `url`, `delay`, and `message`. This is not an HTTP redirect header. The app must not blindly follow an arbitrary returned target. |
| PATCH `pools` array | It **exists** in this build: `http_server.c:925–951` validates entries with slot `id`, and 1000–1011 writes them. Slot IDs are 0…7. That code does not establish a maximum array length of eight objects. Pool PUT/DELETE routes also exist, so PATCH is not the exclusive configuration API. No write fixture is prescribed here. |
| `useFallbackStratum` | A configured user preference, distinct from observed `isUsingFallbackStratum`. `protocol_coordinator.c:329–335` disables automatic switch-back when fallback is explicitly chosen. Paused recovery at 397–423 tries preferred fallback first, then primary if needed. It is neither merely a fallback-enable switch nor a guarantee that the fallback is currently active. |
| Options and encoding bounds | ASIC defaults/options and broad NVS numeric limits do not prove electrical safety, a successful setting application, or a safe pairing. Leave overclock unlock, firmware update, pool security fields and thermal-protection changes advanced and explicitly reviewed. |

## 6. Verification and limitations

Rechecked the pinned family/board definitions, JSON producers, power and thermal implementations, custom-board initialization, REST validation/application, pool recovery, and hostname response. The prior document's fixture voltage, modeled-current/power assumptions, display-timeout units, read-only thermal claim, redirect-header claim and release cutoff must not be reused as test expectations.

This matrix does not certify any physical board, custom fork, safe operating point, sensor installation or mutation outcome. For prioritized native screen work and acceptance criteria, use `docs/SECOND-FIRMWARE-AUDIT.md`. For actual capability checks, use the current Info/ASIC report rather than this static table.
