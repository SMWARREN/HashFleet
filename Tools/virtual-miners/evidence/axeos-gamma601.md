# Native AxeOS Gamma 601 acceptance

**Run:** November 21, 2026, ARM64 macOS 27.2.1, Python 3.12 and the existing HashFleet CLI built with Swift 6.4.2. All host requests used literal IPv4 loopback. No network scan, hardware, GUI, pool connection or device mutation was used.

| Asset | Pin | SHA-256 |
|---|---|---|
| Official `esp-miner-factory-601-v2.15.4.bin` (15,802,368 bytes) | [ESP-Miner v2.15.4](https://github.com/bitaxeorg/ESP-Miner/releases/tag/v2.15.4), `d212a0f948cb3ffd90c7ca9572e9b2cf2d865d80` | `d6307ce762d3fad529b705ad9c3b8fae96b66bd35125585b006f132c9de10184` |
| Official `esp-emu-1.2.0-aarch64-apple-darwin.tar.gz` | [Espressif esp-emulator v1.2.0](https://github.com/espressif/esp-emulator/releases/tag/v1.2.0), `34ba27a6e5a3da41743fc861b462cf2452f0ca28` | `2406dbec04bcb8ee207e512cbb98a8c5478c9dad94ee18f1b3b14c384ab5eb6f` |
| Extracted `esp-emu` | Same release archive | `920a8f68bf024251dc62b4b164b96f093f6349d8acf40402c211666f5d5a0544` |

The hash-verified cache is never written by the emulator. The runner adjusts only the first 4 KiB of the NVS partition at `0x9000` on its private launch copy, not the partition table, bootloader or application. The initial-only configuration clears the factory self-test, provides local Wi-Fi, and uses `.invalid` pool names and dummy credentials. The guest can later write its own NVS. This is the original release application, not an original untouched configuration or a custom/recompiled build.

## Observed original-firmware behavior

Truncated UART excerpt from a successful board-mode boot (ANSI color removed):

```text
I (663) TPS546: Device ID: 54 49 54 6d 24 41
I (678) EMC2101: Initializing EMC2101 (Temperature offset: 0° C)
I (679) http_server: Starting HTTP Server
I (4932) common: Chip 0 detected: CORE_NUM: 0x00 ADDR: 0x00
I (13613) serial: Changing UART baud to 1000000
I (13613) asic_init: ASIC initialized successfully with 1 chip(s) (cold boot mode)
```

- **Genuine API:** HTTP 200 from `GET /api/system/info` (`boardVersion: "601"`, `ASICModel: "BM1370"`, `version: "v2.15.4"`, 3,000 RPM from EMC2101) and HTTP 200 with `labels` and `statistics` from the original statistics handler. Responses carried no fixture marker. `POST /api/system/restart` and `PATCH /api/system` returned 405 at the gateway. WebSocket and query variants returned 404.
- **Two concurrent guests and reconnect:** the unchanged HashFleet CLI reported `2/2 online`, `1/2 online` after stopping just one, and `2/2 online` when it restarted on fresh flash. The missing ASIC guest stayed reachable and its UART logs reported `ASIC 0 not found`.
- **Board/network faults:** with injected 95 °C, the real API read 95 °C and the firmware logged `Entering safe mode due to overheat condition`. Removing the TPS546 produced `Cannot find TPS546 regulator`. A wrong STA SSID prevented association, while the same firmware's local setup HTTP API stayed reachable.
- **Isolation:** verifies the native child opens only its assigned numeric loopback TCP listeners, disables host egress at the OS, and forwards only explicitly approved GETs. Requests and responses are not bridged to the LAN. See [NETWORK.md](../NETWORK.md).

## Reproduction and limits

From `Tools/virtual-miners`, run `python3 -B -m virtual_miners setup`, build `hashfleet` from the repo root, and run `python3 -B verify_native.py`. See [the README](../README.md) for cache and CLI overrides. This runs multiple original-application guests and checks original serial driver milestones, API identity and fixture absence, fault paths, safe gateway refusals and HashFleet lifecycle. It never fetches new assets or preserves raw HTTP payloads. The [untouched factory-settings experiment](esp-emulator-gamma601-factory-serial.md) is separate.

The model implements a small, byte-accurate subset for Gamma 601. I2C supplies PMBus identification and selected word/block registers, fan tach, temperature and display acknowledgment. The BM1370 returns exact chip ID/CRC on UART1; the firmware's real log records 1 Mbaud configuration, not physical UART timing. No mining work, shares, complete ASIC register/electrical behavior, graphics rendering, successful factory self-test, WebSocket forwarding or host mDNS is established.

## Code provenance

- The ESP-Miner driver behavior, CRC5 recurrence and reply validation are from pinned GPL-3.0 [`components/asic`](https://github.com/bitaxeorg/ESP-Miner/tree/d212a0f948cb3ffd90c7ca9572e9b2cf2d865d80/components/asic). The lab's Python CRC5 follows that recurrence. PMBus/EMC2101 values are modeled from the same revision's original drivers. HashFleet is GPL-3.0.
- The lab implements the published [esp-emu co-simulation protocol](https://github.com/espressif/esp-emulator/blob/v1.2.0/proto/esp_cosim.proto) in Python without vendoring the Apache-2.0 tool or runtime binaries. WarpAxe (GPL-3.0) and bm13xx-rs (MIT/Apache-2.0) were inspected as protocol references, not embedded. No firmware assets are redistributed here.
