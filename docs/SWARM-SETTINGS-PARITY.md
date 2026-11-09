# AxeOS Swarm settings parity

Audit baseline: ESP-Miner commit [`2943d206f6c8a4b249bc74c820fb56c874ac316d`](https://github.com/bitaxeorg/ESP-Miner/tree/2943d206f6c8a4b249bc74c820fb56c874ac316d).

## What the Swarm edit actually opens

The Swarm page does not implement a second settings form. Its edit action stores the selected device and opens `app-modal`; the modal body renders `<app-edit [uri]="http://...">`:

- `main/http_server/axe-os/src/app/components/swarm/swarm.component.ts`: `edit(device)`
- `main/http_server/axe-os/src/app/components/swarm/swarm.component.html`: final `app-modal` block, `<app-edit>` body
- `main/http_server/axe-os/src/app/components/modal/modal.component.ts`: visibility/headline shell
- `main/http_server/axe-os/src/app/components/edit/edit.component.ts`: actual settings form and writes

The pinned `modal.component.html` is only the modal shell. Pool configuration is not part of this Swarm edit modal.

## Exact upstream edit fields

`edit.component.ts` creates a form with these controls:

| Upstream control | Native HashFleet status |
|---|---|
| `display` | **Missing native field.** Display rotation, inversion, and timeout exist, but display hardware/type does not. |
| `rotation` | Covered in `MinerSettingsView.swift` Display. |
| `invertscreen` | Covered in `MinerSettingsView.swift` Display. |
| `displayTimeout` | Covered in `MinerSettingsView.swift` Display. |
| `coreVoltage` | Covered by Manual tuning and `MinerTuningDraft`. |
| `frequency` | Covered by Manual tuning and `MinerTuningDraft`. |
| `autofanspeed` | Covered in Cooling. |
| `minFanSpeed` | Covered in Cooling, automatic mode only, after the firmware audit below. |
| `manualFanSpeed` | Covered in Cooling. |
| `temptarget` | Covered in Cooling. |
| `overheat_mode` | Intentionally not exposed as a native control. Available through Advanced JSON. |
| `statsFrequency` | Covered in General, "On-device statistics". |

The same component also supports `overclockEnabled` through the `?oc` unlock flow. It is not a normal form field and should not be added as a casual native setting.

Upstream references:

- Form fields and load/write behavior: `main/http_server/axe-os/src/app/components/edit/edit.component.ts`, `loadDeviceSettings()`, `updateSystem()`, and the `this.fb.group({...})` form definition.
- Display timeout choices: `DISPLAY_TIMEOUT_STEPS` in the same file: `0, 1, 2, 5, 15, 30, 60, 120, 240, 480, -1` minutes.
- Statistics choices: `STATS_FREQUENCY_STEPS` in the same file: `0, 1, 2, 5, 10, 30, 60, 120, 360, 840, 1680, 3600` seconds.

## Bounded native additions

### P1: Statistics frequency — implemented

Add one small **Statistics refresh** picker under Display or Advanced tools, using the upstream step values above. Review only `{"statsFrequency": seconds}` through the existing settings confirmation flow. Keep `0` labeled explicitly as firmware-defined/disabled behavior rather than guessing its meaning. This is the clearest low-risk parity gap.

Implemented as an **On-device statistics** picker in the General page, next to the hostname control it shares a screen with. It uses the exact `STATS_FREQUENCY_STEPS` seconds and reviews only `{"statsFrequency": <seconds>}` through the existing `PendingMinerWrite` / APPLY flow. The copy states explicitly that this is the miner's own on-device logging, not the app's refresh interval, so a user cannot confuse it with HashFleet polling.

Firmware behavior confirmed at the pinned commit rather than inferred from the UI:

- `main/nvs_config.c`: `statsFrequency` is `TYPE_U16` with `.min = 0`, `.max = UINT16_MAX`, and no compiled-in default value.
- `main/tasks/statistics_task.c`: `0` calls `removeStatisticsBuffer()`, which frees the buffer and resets the stored size, so `0` is genuinely "disabled", not "as fast as possible".
- `main/tasks/statistics_task.h`: `MAX_STATISTICS_COUNT` is 720, matching the web UI's `statsLimit` default. The retained-history hint is derived from that count and is described as approximate because `addStatisticData()` thins samples by triangle area rather than keeping a fixed span.
- `edit.component.ts` also appends a device-reported value that is not one of its steps instead of snapping it. `MinerTuningDraft.statsFrequencyOptions(reported:)` mirrors that, so an existing non-standard interval is never silently rewritten.

### P1, only after API-bound confirmation: Minimum fan speed — implemented after audit

Add **Minimum fan speed** under Cooling, shown only when automatic fan control is enabled. Use a percentage control and preserve the device-reported value. Before implementation, confirm the running API's accepted range and semantics for `minFanSpeed`; the pinned UI declares the field but does not establish a safe hardware range in the inspected source. Do not infer a safety recommendation from a UI slider.

The required confirmation was completed against the pinned firmware C sources, not the Angular slider:

- `main/nvs_config.c`: `NVS_CONFIG_MIN_FAN_SPEED` is `{"minfanspeed", TYPE_U16, default 25, rest_name "minFanSpeed", .min = 0, .max = 99}`. The maximum is **99, not 100**, and differs from `manualFanSpeed`, which allows 0–100. The two bounds are deliberately not unified in `MinerTuningDraft`.
- `main/http_server/http_server.c`, `check_settings_and_update()`: a PATCH value is rejected when it falls outside the table's `.min`/`.max`, so those numbers are the actual accepted API range for this build.
- `main/tasks/fan_controller_task.c`: the value is read only inside the `nvs_config_get_bool(NVS_CONFIG_AUTO_FAN_SPEED)` branch and applied as `pid_set_output_limits(&pid, min, 100)`. It is the PID output floor for automatic control. The overheat (100%), mining-paused (30%), no-pool (30%), and pre-valid-temperature startup (70%) branches ignore it entirely.

The native control therefore appears only when automatic fan control is on, reviews only `{"minFanSpeed": <percent>}`, and states the 0–99 range as a firmware input bound plus the fact that `0` permits a fully stopped fan. It does not claim a safe airflow value for any board, and it never emits a thermal protection field. The existing `MinerTuningDraft.coolingPayload(automatic:manualSpeed:target:)` signature and payload shape are unchanged, so the fan floor is never rewritten as a side effect of a target-temperature change.

### P2, optional: Display type

Consider a compact Display type picker only if HashFleet needs to configure boards with replaceable OLED/display modules. Otherwise leave this in Advanced JSON because it is hardware-specific and can clutter the common settings path. If added, use the upstream options exactly: `NONE`, `SSD1306 (128x32)`, `SSD1309 (128x64)`, `SH1107 (64x128)`, `SH1107 (128x128)`.

Not implemented. `display` remains available through the Advanced JSON editor, as the P2 note recommends. `main/http_server/http_server.c` validates it with `get_display_config(item->valuestring)`, so an invalid string is rejected by the device rather than by a native allowlist that could drift from firmware.

## Implementation status

| Addition | Status | Native location | Reviewed payload |
|---|---|---|---|
| `statsFrequency` | Implemented | General › On-device statistics | `{"statsFrequency": <seconds>}` |
| `minFanSpeed` | Implemented, automatic mode only | Cooling | `{"minFanSpeed": <percent>}` |
| `display` | Not implemented by choice | Advanced JSON editor | n/a |

Both additions keep the existing safety posture: values are seeded only from genuinely reported telemetry, nothing is written automatically, each review contains exactly one field, `overheat_mode` is never included, and confirmation still goes through the existing `PendingMinerWrite` / APPLY flow. Unit coverage is in `AppTests/MinerSwarmSettingsTests.swift`.

## Keep out of the friendly native form

- **`overheat_mode`:** Do not add a normal toggle. The upstream edit form can disable it, but that weakens thermal protection. Keep it JSON-only with a prominent warning, matching the existing native tuning safety posture.
- **Overclock unlock / custom presets:** Do not mirror the hidden `?oc` unlock or add boost presets. Existing Manual tuning already requires risk acknowledgement, reviews exact JSON, and keeps thermal protections untouched.
- **Pool fields in the Swarm modal:** No parity gap. AxeOS Swarm delegates to the general edit component, which has no pool controls. HashFleet's dedicated Pools page is broader and safer because it handles slot identity, full-slot replacement warnings, password retention, and active-slot selection.

## Current native coverage evidence

`App/Features/Miner/MinerSettingsView.swift` currently provides General, Cooling, Display, Pools, Manual tuning, and Advanced tools. `App/Features/Miner/MinerTuningDraft.swift` covers frequency/core voltage, cooling, minimum fan speed, statistics frequency, rotation, inversion, and display timeout payloads. `App/Features/Miner/MinerTuningPoolDraft.swift` covers pool-slot replacement semantics. The existing Advanced JSON editor already provides access to firmware-specific fields not promoted into native controls.
