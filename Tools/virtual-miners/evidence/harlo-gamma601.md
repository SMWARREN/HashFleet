# Harlo Gamma 601 factory artifact evidence

Date: 2026-11-21 (local session date)

## Scope and outcome

The official publisher manifest and factory image were independently checked. On November 21, 2026, a byte-identical private copy **booted into its first-run setup access point** under Espressif `esp-emu` v1.2.0 on Apple Silicon. It returned `200 application/json` to all six requested GETs over a single isolated TCP forward. The original firmware reports that the rails are off in this state. No claim is made about configured-network behavior, ASIC initialization, authentication on other builds, or mining.

No physical hardware or LAN device was accessed, no mutations were sent, and no GUI was used. Only publisher artifacts were fetched. No host egress was permitted to the emulator, and the publisher binaries and raw responses are not included in this repository.

## Artifact provenance and byte validation

- Publisher manifest: `https://updates.harlolabs.com/v2/manifest.json`
- Manifest release: `bitaxe-gamma-601`, version `0.2.101`
- Factory URL listed by manifest: `https://updates.harlolabs.com/v2/bitaxe-gamma-601/0.2.101/Harlo-OS-bitaxe-gamma-601-0.2.101-factory.bin`
- Manifest factory size: `16,777,216` bytes
- Independently downloaded byte count: `16,777,216`
- Manifest SHA-256: `363b1a43fcf55632a0f2c8b6ad3095de462ff38262f5f6fc4a3c3c1c87d3578a`
- Independently calculated SHA-256: `363b1a43fcf55632a0f2c8b6ad3095de462ff38262f5f6fc4a3c3c1c87d3578a` (match)

This establishes that the bytes fetched from the publisher URL match the publisher manifest's digest. It does not establish source availability, redistribution permission, or permission to flash hardware.

## Standard image and partition metadata

Inspection used installed esptool v5.4.0 `image_info` on the local scratch image. Reported metadata:

- Detected target: ESP32-S3 (chip ID 9)
- Image version: 1; entry point `0x403c8900`; 3 image segments
- Declared flash size: 16 MB; DIO, 80 MHz
- Image checksum and validation hash: valid
- Bootloader metadata: ESP-IDF `v6.1-dev-5572-g4288cd3334`, build time `Oct 6 2026 01:12:43`
- The standard ESP-IDF partition table at offset `0x8000` has valid `0x50aa` entries and an `0xebeb` terminator. Entries observed:

| Label | Type/subtype | Offset | Size |
|---|---:|---:|---:|
| `nvs` | `0x01/0x02` | `0x9000` | `0x6000` |
| `phy_init` | `0x01/0x01` | `0xf000` | `0x1000` |
| `ota_0` | `0x00/0x10` | `0x10000` | `0x700000` |
| `artwork` | `0x01/0x40` | `0x710000` | `0x100000` |
| `ota_1` | `0x00/0x11` | `0x810000` | `0x700000` |
| `otadata` | `0x01/0x00` | `0xf10000` | `0x2000` |

The manufacturer artifact path identifies Gamma 601 and the image header establishes the ESP32-S3 target. No independently verified Harlo source, board schematic, or physical ASIC identity was established.

## Safe execution and observed serial output

A bounded local string-indicator inspection (only category-matched lines retained in notes) found pool configuration and stratum-related keys, Wi-Fi `ssid`/`password` keys, and compiled URLs for the publisher update service, contest service, and Discord webhook service. No secret values or full credential-bearing configuration were copied into this report. This confirms the image has configuration/network-sensitive surfaces; it does not establish which NVS values are active or what requests the firmware makes at runtime.

The static-inspection lane did not execute the image because `restrict=yes` alone is not an egress boundary. The later native test used the OS boundary from [NETWORK.md](../NETWORK.md), first with **no network permissions or host forwards**, then with only one assigned TCP listen port. The exact verified factory image was copied into a fresh directory for each launch. No NVS provisioning, guest driver patch or setup credential was used. Harlo did not get ESP-Miner's board sidecars.

```text
esp-emu --chip esp32s3 --firmware <private-factory-copy> --log-color never \
  --net user,restrict=yes,dns=127.0.0.1,net=10.0.2.0/24,hostfwd=tcp:127.0.0.1:<assigned-port>-:80
```

Do not run that command unsandboxed. The Python runner's `isolated_command(argv, listener_ports=(port,))` wraps it with the tested OS profile. Use `ESP_EMU_DISABLE_AUTOUPDATES=1`, an isolated per-run working directory, and no other process-level network permissions. Omit the forwarding rule and pass no `listener_ports` for serial-only reproduction. Inspect the exact child with `lsof -nP -a -p <pid> -iTCP -sTCP:LISTEN` before sending any HTTP. The first serial-only run was stopped after 20 host seconds. These excerpts are from the guest UART, with the setup SSID suppressed:

```text
I (3) boot: ESP-IDF v6.1-dev-5572-g4288cd3334 2nd stage bootloader
I (270) esp_psram: SPI SRAM memory test OK
I (279) main_task: Calling app_main()
W (283) app: IP display unavailable: ESP_ERR_INVALID_RESPONSE
I (283) app: Bitaxe Gamma 601 rails held off; starting network
I (306) network: setup network [redacted] at 192.168.4.1
I (307) main_task: Returned from app_main()
```

## HTTP capture summary (virtual factory setup only)

Two fresh, sandboxed boots returned the following without adding authorization headers or cookies. Reduced Swift contract-test inputs omit values that were not captured or that cannot safely be shared. No raw bodies, Wi-Fi details, pools, per-child addresses, hardware IDs or log messages are stored.

| GET | Observed result and redacted wire shape |
|---|---|
| `/api/info` | `200`; `firmware: "Harlo-OS-V2"`, `version: "0.2.101"`, `profile.id: "bitaxe-gamma-601"`, `fleet_api_version: 1`. No explicit advertisements observed for the other four optional reads. |
| `/api/telemetry` | `200`; `hashrate_ghs`, `device_power_w`, `asic_temp_c` are present and `null`; `powered: false`. The dashboard's numeric consumer evidence does not make them numeric when unavailable. |
| `/api/network` | `200`; `interfaces` array length 3. Other fields include `wifi_networks`; no contents retained. |
| `/api/pools` | `200`; `pools` array length 4. No per-pool values retained. |
| `/api/fleet` | `200`; `devices` is an empty array. Fleet also has scan progress and job fields. This is an aggregate response, not permission to contact child addresses. |
| `/api/logs` | `200`; `cursor` integer, `paused` boolean, `lines` string. No cursor, pause, or log values retained. |

`HarloInfoProfile.gamma601V02101` is explicitly opt-in: its three identity literals identify this exact observed build, not an authenticated device, and `fleet_api_version: 1` enables only the fleet GET. An HTTP 200 seen in a research experiment is not itself advertised capability. The standard AxeOS runner does not start Harlo or serve these routes.

## Compatibility status

| Property | Evidence/status |
|---|---|
| Publisher-hosted artifact identity | Verified by manifest SHA-256 and byte count |
| Firmware version / product target | Publisher path/manifest: `0.2.101`, `bitaxe-gamma-601` |
| MCU/image target | ESP32-S3, verified by standard image header |
| Partition layout | Parsed from standard table at `0x8000`, listed above |
| ASIC / board electrical peripheral details | Unknown from this inspection |
| Boot in esp-emu | Verified through `app_main`, setup Wi-Fi, and genuine HTTP in Apple Silicon native v1.2.0 |
| HTTP `/api/info` or other route outcome | Six GETs returned 200 in factory setup; authentication requirements in other states unknown |
| API response shapes and capabilities | Partial, as above; optional routes except fleet remain unadvertised |
| Firmware source / redistribution rights | Not established |
