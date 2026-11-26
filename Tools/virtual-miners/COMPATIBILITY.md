# Firmware and hardware compatibility research

Research and lab snapshot: November 21, 2026. The source-research pins below are exact commits. Separate runtime receipts are provided for [AxeOS Gamma 601](evidence/axeos-gamma601.md) and [Harlo Gamma 601](evidence/harlo-gamma601.md). Source, owner-supplied inventory, and observed execution are not interchangeable.

## Executive findings

- **Lab profile:** ESP-Miner/AxeOS v2.15.4 Gamma 601 ran under esp-emu v1.2.0 on Apple Silicon. The unchanged app serves genuine info and statistics. The original board drivers communicate with TPS546 and EMC2101 models and the UART driver detects and initializes one modeled BM1370. This does not validate hash jobs, other hardware profiles, or LAN discovery.
- ESP-Miner's checked-in C sources include chip-specific drivers for BM1366, BM1368, BM1370, BM1373, and BM1397, a board configuration table, an NVS configuration subsystem, and actual HTTP/WebSocket handlers. This is valuable driver/protocol source, not a drop-in ASIC behavioral simulator.
- `dvb-WarpAxe` is a separate Rust firmware plus reusable no_std drivers and a simulated ASIC/chain/board. Its sim is exercised by WarpAxe's own software tests and AxeOS-compatible interface; it does not attach to or transparently satisfy unmodified ESP-Miner's UART/I2C/GPIO drivers. Do not call it original ESP-Miner boot.
- BM1372 is distinct from the task's list and is covered alongside BM1373 by `bm13xx-rs`'s `bm1372` crate. The five requested families have driver implementations in ESP-Miner and/or the Rust library, but chip drivers are not the same thing as a validated virtual-device model.
- **Harlo research:** the genuine Gamma 601 factory image v0.2.101 was verified and exercised in isolated setup mode. All six intended GETs returned 200; only fleet had route-specific evidence in `/api/info`. No physical miner capture or sourced API spec was used.

## Pinned upstreams and evidence scope

| Upstream | Pinned revision | What the checked-in source establishes | What it does not establish |
|---|---|---|---|
| [espressif/esp-emulator](https://github.com/espressif/esp-emulator/tree/6bc8abda651d123aee59cc7e9822fafcee975fe9) | `6bc8abda651d123aee59cc7e9822fafcee975fe9` (research); `34ba27a6e5a3da41743fc861b462cf2452f0ca28` (runtime v1.2.0) | Docs and tools cover Xtensa LX7 ESP32-S3, merged ESP-IDF flash, UART, GPIO, I2C and Wi-Fi. The repository distributes prebuilt releases and exposes co-simulation tools, not the core emulator source. | Other versions, boards and emulated electrical behavior are not established. |
| [espressif/qemu](https://github.com/espressif/qemu/tree/093b0c343e5457f16ead57d89cf2a75361cf3acf) | `093b0c343e5457f16ead57d89cf2a75361cf3acf` | Espressif QEMU fork source. | No claim that it models this miner's S3 board/peripheral topology or BM ASICs; not run here. |
| [dvb-projekt/dvb-WarpAxe](https://github.com/dvb-projekt/dvb-WarpAxe/tree/93f880b40e4cffa32595309e71c08110497a8f04) | `93f880b40e4cffa32595309e71c08110497a8f04` | Rust firmware supporting BM1370/BM1373/BM1397, AxeOS-compatible API, and source crates including simulated chain/board and simulated UART. README distinguishes boards run from profiles not run. | Its simulator is not a bridge that lets unmodified C firmware use its drivers. Its emulated behavior is not proof of physical hardware fidelity. |
| [GPTechinno/bm13xx-rs](https://github.com/GPTechinno/bm13xx-rs/tree/8de5f568a25168189815ffffb7f38fc0bdf8075b) | `8de5f568a25168189815ffffb7f38fc0bdf8075b` | Rust no_std UART-frame/protocol and chip/chain implementations. README maps BM1366, BM1368, BM1370, BM1372/BM1373, and BM1397 to named crates and example mining products. | Not a complete ESP32 miner board model, firmware, or verified full ASIC/thermal/power simulation. |
| [liaojinguu/bitfortun-BS-1](https://github.com/liaojinguu/bitfortun-BS-1/tree/90d0159e7f2368587582aa8d6a8af9392e9bc770) | `90d0159e7f2368587582aa8d6a8af9392e9bc770` | Public firmware source tree; README specifies ESP32-S3 + single BM1373 and board identifier `BITFORTUN_BS1`; includes NVS partition configuration/build instructions and AxeOS-derived HTTP UI/source. | No BS-1 firmware boot attempt here. The repository's presence of source does not prove released binaries match this revision or hardware. |
| [shufps/ESP-Miner-NerdQAxePlus](https://github.com/shufps/ESP-Miner-NerdQAxePlus/tree/b7ab0b378694adba7b0e18ab665a69ed43274d0b) | `b7ab0b378694adba7b0e18ab665a69ed43274d0b` | Public NerdOS firmware source, API documentation and board implementations. Its API docs identify `/api/v2/...`; source/readme cover ESP32-S3 family and multiple ASIC boards. | API differs from AxeOS and is not automatically covered by AxeOS endpoints; exact binary/board execution not tested here. |
| [IsSasoriDev/AxeForge](https://github.com/IsSasoriDev/AxeForge/tree/57cc1ff32096affe1dfa454756c73841385f1974) | `57cc1ff32096affe1dfa454756c73841385f1974` | Public ForgeOS source, board-specific `sdkconfig.defaults.*`, board matrix, and OpenAPI document. README describes 24 boards, per-board images, and reports tested versus untested boards separately. | README/community board claims are not independently hardware-verified by this lane; no binary executed. |
| [bitaxeorg/ESP-Miner](https://github.com/bitaxeorg/ESP-Miner) | `6175c2272b8e1f59378b2cd1731d8af1e6b72dda` (research); `d212a0f948cb3ffd90c7ca9572e9b2cf2d865d80` (runtime v2.15.4) | Public source includes `components/asic/{bm1366,bm1368,bm1370,bm1373,bm1397}.c`, board-config CSVs, `main/nvs_config.c`, `main/device_config.c`, HTTP server, OpenAPI YAML, and Angular UI source. | Source route declarations are contract evidence, not a guarantee that every route or board works in the lab. |

## ESP-Miner: board selection, NVS and API facts

At the pinned revision, startup initializes NVS (`main/main.c`). NVS uses namespace `main`; default settings include `boardversion` (`000`), `devicemodel` (`unknown`) and `asicmodel` (`unknown`) (`main/nvs_config.c`). `device_config_init` reads board version and resolves the default board configuration, then reads model and ASIC model values and initializes board pins (`main/device_config.c`). The board-specific CSVs demonstrate that these are boot-critical identity inputs, not just cosmetic labels. For a virtual boot fixture, synthesize a clean, non-production NVS partition from explicit safe values; never use factory CSVs unedited because they include pool and Wi-Fi fields.

Source-backed example identity mapping from `configs/config-*.csv`:

| NVS boardversion | devicemodel | asicmodel | Evidence / interpretation |
|---|---|---|---|
| `102` | `max` | `BM1397` | `configs/config-102.csv` |
| `201` | `ultra` | `BM1366` | `configs/config-201.csv` |
| `601` | `gamma` | `BM1370` | `configs/config-601.csv` |
| `602` | `gamma` | `BM1370` | `configs/config-602.csv`; same ASIC family, distinct board version/config. Do not infer identical power/PCB hardware from chip identity. |
| `701` | `suprahex` | `BM1368` | `configs/config-701.csv` |
| `1201` | `NajaDuo` | `BM1373` | `configs/config-1201.csv`; multi-chip board topology is board-specific. |
| `1300` | `GammaHex` | `BM1370` | `configs/config-1300.csv`; six-chip board, board configuration matters beyond ASIC type. |

These CSVs contain sensitive-looking example pool account and Wi-Fi fields. They are intentionally not reproduced here. Treat them as examples only and remove/replace all network and credential values in any fixture or generated NVS image. The safe high-level facts needed by the coordinator are the identity fields above, plus `asicfrequency`/`asicvoltage` values appropriate to a simulator profile, not the raw file contents.

`main/http_server/http_server.c` directly registers the following read-only routes: `GET /api/system/asic`, `/api/system/firmware/checksum`, `/api/system/info`, `/api/system/logs`, `/api/system/scoreboard`, `/api/system/statistics`, and `/api/system/wifi/scan`. It registers `GET /api/ws` and `/api/ws/live` as WebSockets. Mutating routes include `PATCH /api/system`, pool `PUT`/`DELETE`, OTA `POST`, pause/resume/restart `POST`. `main/http_server/openapi.yaml` documents endpoint shapes. Use the OpenAPI as source contract evidence, and separately mark live response schema/runtime behavior unverified until captured from a permitted instance or emulated genuine firmware.

## ASIC and board differences

| ASIC | Public source support found | Board examples evidenced in the pinned sources | Virtualization implication |
|---|---|---|---|
| BM1366 | ESP-Miner C driver; bm13xx-rs `bm1366` crate | Bitaxe Ultra (201-series configs); AxeForge also lists one-chip NerdAxe | Same chip family does not imply same carrier GPIO, regulator, fan, display, or sensor setup. |
| BM1368 | ESP-Miner C driver; bm13xx-rs `bm1368` crate | Bitaxe Supra family; AxeForge NerdQAxe+ / NerdOctaxe+ | Multi-chip chains and regulator/fan peripherals vary by carrier/revision. |
| BM1370 | ESP-Miner C driver; bm13xx-rs `bm1370` crate; WarpAxe | Gamma 601/602, Gamma Hex 1300; AxeForge also lists NerdQaxe++ and other boards | ASIC protocol can be shared while board power topology, ASIC count, sensor IC, display and pin assignment differ. |
| BM1373 | ESP-Miner C driver; bm13xx-rs `bm1372` crate covers BM1372/BM1373; WarpAxe | Naja Duo 1201; BS-1 README identifies one BM1373; NerdOS has Q1373/Gaia family | Do not collapse single-chip BS-1/Gaia and dual-chip Naja Duo or four-chip Q1373. Per-domain initialization and chain arrangement differ. |
| BM1397 | ESP-Miner C driver; bm13xx-rs `bm1397` crate; WarpAxe | Bitaxe Max 102; NerdNOS designs also use BM1397 | Legacy protocol details and board-specific power/temperature behavior need their own model. |

Shared components evidenced by source include Bitmain ASIC UART command/response framing and CRC/protocol layers, chip initialization/register operations, work and nonce paths, plus common concepts such as reset, enable, frequency, and ASIC-result parsing. Board-specific components include UART pins/baud transitions, chain/domain count and wiring, regulator type and enable sequencing, regulator telemetry, voltage/current measurement, fans/tach, thermistors or chip diode sensing, I2C devices, and displays/buttons. A simulator must model both layers. Passing a protocol-level unit test cannot establish board-level compatibility.

WarpAxe's README/docs record useful differences, including Naja Duo's two BM1373 chips in two voltage domains and different initialization/baud sequence from NerdOS; Gamma versus Gamma Duo/Hex use differing chip counts/domains; board choice is guarded by bus/peripheral checks. These are strong evidence against a single generic “BM137x board” profile. They are WarpAxe implementation/source facts, not a substitute for independent measurement.

## Harlo OS: endpoint evidence matrix

### Provenance and identification

The owner-supplied inventory is supplemented by [the publisher manifest](https://updates.harlolabs.com/v2/manifest.json), inspection of the `bitaxe-gamma-601` 0.2.101 OTA asset, and separately executed factory image captures. The [running firmware evidence](evidence/harlo-gamma601.md) documents the distinct factory digest, ESP32-S3 metadata and six GETs. It did not establish normal-operation behavior, physical ASIC type, authenticated-mode behavior, other versions or boards, or any mutation route.

The six safe-read paths have literal occurrences in the reported OTA asset at NUL-terminated file offsets: `/api/fleet` 41100, `/api/logs` 41164, `/api/info` 41176, `/api/pools` 41216, `/api/telemetry` 41228 and `/api/network` 33332. Dashboard code expects `network.interfaces`, `pools.pools`, and `fleet.devices` arrays, and filters fleet devices by local address. Telemetry is assigned to `live` and reads numeric `asic_temp_c` and `device_power_w` around offsets 566356/566563, and `hashrate_ghs` plus `firmware_version` near 567330. These are client-side expectations from static inspection. A separate capture from the original running firmware establishes the subset of shapes below. No physical device capture was made.

Base URL in supplied inventory: `http://<MINER_IP>`. The six observed GETs below were exercised only on the virtual factory setup AP, without authorization. General auth, rate limits, error codes and compatibility are unknown. The adapter opts into a single origin, requires exact firmware/board identity and a positive route-specific advertisement for any optional read. The opt-in factory profile only advertises fleet. The adapter never follows firmware-reported child addresses and never exposes log content or credentials.

| Method | Endpoint | Inventory purpose | Proof/source | Firmware version | Board/MCU/ASIC | Response / outcome |
|---|---|---|---|---|---|---|
| GET, PUT | `/api/miner-name` | Read/save name | Owner inventory only | Unknown | Unknown | Shape/test unknown; PUT mutating, gate |
| GET | `/api/updates` | Update status | Owner inventory only | Unknown | Unknown | Unknown |
| POST | `/api/updates/check` | Check update | Owner inventory only | Unknown | Unknown | Unknown; action-like, do not probe |
| POST | `/api/updates/install` | Install update | Owner inventory only | Unknown | Unknown | Destructive, disabled |
| PUT | `/api/updates/ignore` | Ignore/restore update notice | Owner inventory only | Unknown | Unknown | Unknown; mutating |
| GET, POST | `/api/ota` | OTA status/upload | Owner inventory only | Unknown | Unknown | GET unknown; POST destructive, disabled |
| GET, PUT | `/api/display` | Display mode | Owner inventory only | Unknown | Unknown | GET unknown; PUT mutating |
| GET, POST, DELETE | `/api/display/image` | Display image | Owner inventory only | Unknown | Unknown | GET unknown; writes/deletes disabled |
| GET | `/api/display/image/raw` | Pixel data | Owner inventory only | Unknown | Unknown | Unknown |
| GET | `/api/display/image/alpha` | Opacity data | Owner inventory only | Unknown | Unknown | Unknown |
| GET, POST, DELETE | `/api/display/background` | Display background | Owner inventory only | Unknown | Unknown | GET unknown; writes/deletes disabled |
| GET, PUT, DELETE | `/api/display/layout` | Display layout | Owner inventory only | Unknown | Unknown | GET unknown; writes/deletes disabled |
| GET, PUT, DELETE | `/api/matter` | Power-plug configuration | Owner inventory only | Unknown | Unknown | GET unknown; mutations disabled |
| POST | `/api/matter/pair` | Pair plug | Owner inventory only | Unknown | Unknown | Unknown; pairing/network action disabled |
| POST | `/api/matter/forget` | Forget pairing | Owner inventory only | Unknown | Unknown | Unknown; mutating disabled |
| GET, PUT | `/api/protections` | Protection settings | Owner inventory only | Unknown | Unknown | GET unknown; PUT mutating |
| GET | `/api/fleet` | Detected miners/status | Factory setup capture; OTA dashboard | `0.2.101` | Gamma 601 / ESP32-S3 / ASIC unknown | 200, `devices: []`; `/api/info` advertises `fleet_api_version: 1`. Child addresses untested and never contacted. |
| POST | `/api/fleet/scan` | Scan miners | Owner inventory only | Unknown | Unknown | Unknown; network scan forbidden |
| POST | `/api/fleet/add` | Add miner | Owner inventory only | Unknown | Unknown | Unknown; mutating |
| POST | `/api/fleet/remove` | Remove miner | Owner inventory only | Unknown | Unknown | Unknown; mutating |
| POST | `/api/fleet/retry` | Retry miner | Owner inventory only | Unknown | Unknown | Unknown; action |
| POST | `/api/fleet/command` | Fleet command | Owner inventory only | Unknown | Unknown | Unknown; potentially consequential, disabled |
| GET, PUT | `/api/temperature-unit` | Temperature preference | Owner inventory only | Unknown | Unknown | GET unknown; PUT mutating |
| GET, PUT | `/api/power-supply` | Power-meter limit | Owner inventory only | Unknown | Unknown | GET unknown; PUT mutating |
| GET, PUT | `/api/discord` | Alert settings | Owner inventory only | Unknown | Unknown | GET unknown; PUT mutating |
| GET, PUT | `/api/collection` | Collection setting | Owner inventory only | Unknown | Unknown | GET unknown; PUT mutating |
| POST | `/api/discord/test` | Test alert | Owner inventory only | Unknown | Unknown | Unknown; sends external alert, disabled |
| GET, PUT | `/api/time` | Clock configuration | Owner inventory only | Unknown | Unknown | GET unknown; PUT mutating |
| POST | `/api/time/sync` | Sync clock | Owner inventory only | Unknown | Unknown | Unknown; action |
| GET | `/api/schedules` | List schedules | Owner inventory only | Unknown | Unknown | Unknown |
| PUT, DELETE | `/api/schedules/{slot}` | Save/delete schedule | Owner inventory only | Unknown | Unknown | Unknown; mutating |
| GET | `/api/logs` | Device logs | Factory setup capture; OTA dashboard | `0.2.101` | Gamma 601 / ESP32-S3 / ASIC unknown | 200, integer `cursor`, boolean `paused`, string `lines`; all values withheld, route unadvertised. |
| POST | `/api/logs/pause` | Pause web logs | Owner inventory only | Unknown | Unknown | Unknown; mutating |
| POST | `/api/logs/resume` | Resume web logs | Owner inventory only | Unknown | Unknown | Unknown; mutating |
| GET | `/api/info` | Device identity/capabilities | Factory setup capture; OTA literal | `0.2.101` | Gamma 601 / ESP32-S3 / ASIC unknown | 200, `firmware: "Harlo-OS-V2"`, `version: "0.2.101"`, `profile.id: "bitaxe-gamma-601"`, `fleet_api_version: 1`. Identity is not authentication. |
| GET | `/api/network` | Network status | Factory setup capture; OTA dashboard | `0.2.101` | Gamma 601 / ESP32-S3 / ASIC unknown | 200, `interfaces` array of three; route unadvertised, Wi-Fi values withheld. |
| GET | `/api/pools` | Pool settings/status | Factory setup capture; OTA dashboard | `0.2.101` | Gamma 601 / ESP32-S3 / ASIC unknown | 200, `pools` array of four; route unadvertised, configuration withheld. |
| GET | `/api/telemetry` | Live mining readings | Factory setup capture; OTA dashboard | `0.2.101` | Gamma 601 / ESP32-S3 / ASIC unknown | 200, `asic_temp_c`, `device_power_w`, `hashrate_ghs` all `null` with rails off. Route unadvertised. |
| GET | `/api/wifi/scan` | Scan Wi-Fi | Owner inventory only | Unknown | Unknown | Unknown; avoid on physical devices |
| POST | `/api/wifi/connect` | Connect Wi-Fi | Owner inventory only | Unknown | Unknown | Unknown; network mutation forbidden |
| PUT, DELETE | `/api/pools/{slot}` | Save/delete pool | Owner inventory only | Unknown | Unknown | Unknown; mutation disabled; slot/allocation variants unknown |
| PUT | `/api/tuning` | Frequency/core voltage | Owner inventory only | Unknown | Unknown | Unknown; tuning mutation disabled |
| PUT | `/api/fans/{channel}` | Fan control | Owner inventory only | Unknown | Unknown | Unknown; mutation disabled |
| GET | `/api/lighting` | Lighting status | Owner inventory only | Unknown | Unknown | Unknown |
| PUT | `/api/lighting/rules` | Lighting rules | Owner inventory only | Unknown | Unknown | Unknown; mutation disabled |
| POST | `/api/lighting/test` | Preview event | Owner inventory only | Unknown | Unknown | Unknown; action disabled |
| PUT | `/api/argb/{zone}` | Lighting zone | Owner inventory only | Unknown | Unknown | Unknown; mutation disabled |
| POST | `/api/asic/start` | Resume mining | Owner inventory only | Unknown | Unknown | Unknown; mining control disabled |
| POST | `/api/asic/stop` | Stop mining | Owner inventory only | Unknown | Unknown | Unknown; mining control disabled |
| POST | `/api/reboot` | Restart | Owner inventory only | Unknown | Unknown | Unknown; disruptive, disabled |
| POST | `/api/factory-reset` | Reset device | Owner inventory only | Unknown | Unknown | Unknown; destructive, disabled |

## Binary/source provenance and caveats

ESP-Miner, BS-1, NerdQAxe/NerdOS, AxeForge and WarpAxe have public source repositories at the pins above. The Espressif emulator repository is source for its emulator tooling and also documents downloadable prebuilt emulator release assets. A Harlo publisher-hosted OTA artifact was identified by the Harlo integration lane as listed above, with SHA-256 `74a9c0b3f8f4bd75839d0309be08f7836fd4a4f10840fa2cdd887e6b4555b627`; this lane did not independently download or execute it. The existence and identity of that artifact does not prove source availability, redistribution rights, emulator compatibility, or runtime API behavior. No firmware binary was run in this research lane.

## What to verify next

1. Cover further BM1370 register reads, virtual work/result flow against a local non-production pool model, and hardware timing. Do not infer hashrate fidelity from a successful initialization.
2. Add further boards one at a time with exact image identity, pin maps, and independent receipts. Research on BS-1, NerdOS and AxeForge is not runnable support.
3. If LAN-like discovery or WebSocket coverage is required, design a dedicated isolated test link and a read-only protocol policy. Do not weaken loopback defaults.
4. Harlo running beyond factory setup and identifying other builds needs independent per-build and per-route evidence; do not reuse the AxeOS NVS overlay for Harlo.

## Reproducibility notes

Pinned source review performed in scratch clones under `$JCODE_SCRATCH_DIR/hashfleet-compat`; revisions are in the table. The only repository edit by this lane is this compatibility document. No emulator/test command was run, no device or LAN was contacted, and no GUI was started. `rg` was unavailable in the shell, so source discovery used `git ls-files`, `git grep`, and bounded `grep` on checked-out upstream source.
