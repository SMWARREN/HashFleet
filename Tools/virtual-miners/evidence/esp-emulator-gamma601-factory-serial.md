# AxeOS Gamma 601 with untouched factory settings

On November 21, 2026, Espressif esp-emu v1.2.0 executed the ESP32-S3 ROM and original ESP-IDF bootloader and app from the official `esp-miner-factory-601-v2.15.4.bin` factory image (SHA-256 `d6307ce762d3fad529b705ad9c3b8fae96b66bd35125585b006f132c9de10184`). A fresh private copy was used; neither the artifact nor its factory settings were patched. This is distinct from the [successful disposable NVS overlay and HTTP run](axeos-gamma601.md).

The factory NVS marks its production self-test enabled. At this version, the application does not take its normal HTTP startup path while self-test is active. With no hardware sidecar, the original TPS546 driver read an all-zero device ID and self-test failed. In a second run with the early I2C sidecar (before the BM1370 fix), the regulator and sensor initialized, and the original ASIC chain check failed:

```text
TPS546: Device ID: 54 49 54 6d 24 41
EMC2101: Initializing EMC2101 (Temperature offset: 0° C)
common: 0 chip(s) detected on the chain, expected 1
common: ASIC 0 not found
SELF-TEST FAIL!
```

In that run the official esp-emu example `pushbutton.wasm` had its `A` pin wired to GPIO0. The control socket accepted a press after initialization and release more than four virtual seconds later. The firmware did not report an LVGL long press, clear the flag, or restart. The loopback HTTP probe timed out. Running the untouched factory settings through a **passing full factory self-test** was not shown, including with the later successful BM1370 initialization model.

## Serial-only reproduction (no network sockets)

From `Tools/virtual-miners`, with `ESP_EMU_BIN` and `FACTORY_IMAGE` absolute paths to the verified release files in [the main receipt](axeos-gamma601.md):

```sh
scratch=$(mktemp -d)
cp "$FACTORY_IMAGE" "$scratch/flash.bin"
ESP_EMU_DISABLE_AUTOUPDATES=1 /usr/bin/sandbox-exec \
  -p '(version 1) (allow default) (deny network*)' \
  "$ESP_EMU_BIN" --chip esp32s3 --firmware "$scratch/flash.bin" \
  --net user,restrict=yes,dns=127.0.0.1,net=10.0.2.0/24 --log-color never \
  >"$scratch/serial.log" 2>&1
```

Use Ctrl-C to finish the foreground reproduction. The raw UART and GPIO traces and the official WASM are not vendored. The working lab uses a safe initial NVS page in a disposable copy rather than relying on virtual GPIO long-press behavior.
