# ThorOS board hardware map (from the original firmware under esp-emu)

Observed 2026-11-26 by booting the unmodified Hammer THOR X1 v1.0.6 (20260916)
app in esp-emu 1.2.0 and answering I2C addresses until the firmware's own log
reported each part as found. The app logs over USB-Serial/JTAG, so run esp-emu
with `--console usb-jtag` to see it.

| Part | Role | Bus | 7-bit addr | Evidence |
| --- | --- | --- | --- | --- |
| HUSB238A | USB-PD sink (5/9/12/15 V) | I2C port 0 | 0x42 | `HUSB238A: init ok` only with 0:0x42 |
| TMP75 | Board temperature | I2C port 0 | 0x4D | `TMP75 temperature sensor configuration success` only with 0:0x4D |
| TPS546 | VCORE buck (PMBus) | I2C port 1, SCL GPIO 12 (SDA probably GPIO 11) | 0x24 | cosim claim on GPIO 12/11 received all 0x24 PMBus traffic |
| Fan | PWM (LEDC) + tach (PCNT) on GPIO | n/a | n/a | `EMC2302_wrapper_gpio: GPIO fan initialized` with no I2C part |
| BM1370 / BM1373 | ASIC chain | UART1 (`THOR_PIN_ASIC_TXD/RXD`) | n/a | `bmlib_bm137x.c`, ASIC_RX/TX tasks |

Alert lines: TPS546 SMBALERT# on GPIO 13. VBUS cut-off on GPIO 16.

## Boot gating

- No HUSB238A: `PD negotiation failed`, then `Restarting with reason: power error` after about 34 s.
- No TPS546, or one returning ID `FF..`: `Pmbus_Init failed`, ASIC power stays OFF and UART1 stays silent. The firmware restarts with `peripheral error` after about 35 s.
- With every address answered by a plain register file, PD reaches `attached=1 ready=1`
  but never reports a negotiated voltage. The firmware therefore walks 5 V, 9 V, 12 V and 15 V and
  times out each one.

So the firmware only drives the ASIC chain once the board sidecar models:

1. HUSB238A PD status with a contract at the requested voltage.
2. TPS546 with a real device ID (`0xAD`, 6 bytes), PMBus OPERATION on/off and
   READ_VIN/VOUT/IOUT/TEMP words.
3. TMP75 temperature (register 0, 12-bit).
4. Then a BM1370/BM1373 chain on UART1 (lab `asic_uart.ASICChain`).

PMBus registers read at boot, in order: 0xAD (ID, 6 bytes), 0x10, 0x02, 0x01, 0xEE, 0x20,
0x29, 0x24, 0x2B, 0x21, 0x40, 0x42-0x44, 0x55, 0x56, 0x1B, 0x03, 0x88, 0x8B, 0x8C,
0x8D and 0x79.
