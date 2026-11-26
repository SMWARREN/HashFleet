"""ThorOS board co-simulation sidecar (TPS546 on I2C1 + BM1373 chain on UART1).

HUSB238A (0:0x42) and TMP75 (0:0x4D) live on I2C port 0 and are passed to
esp-emu via ``--i2c-dev`` flags returned by ``i2c_dev_args()``.
TPS546 (0x24) lives on I2C port 1 (SCL GPIO 12, SDA GPIO 11) and is served
over esp-emu's TCP co-simulation protocol.
The BM1373 ASIC chain is served over ``--uart1-tcp``.
"""
from __future__ import annotations

import socket
import threading
import time
from collections.abc import Callable

from .config import Miner
from .cosim import RegisterDevice, _bm_crc5, attach

THOR_TPS546_SCL = 12
THOR_TPS546_SDA = 11
THOR_TPS546_ADDR = 0x24
THOR_HUSB238A_SPEC = (
    "0:0x42,fill=0,reg=0x63=1,reg=0x64=0x10,reg=0x65=0x10,"
    "reg=0x67=0x40,reg=0x6a=0x80,reg=0x6b=0x80,reg=0x6c=0x80,reg=0x6d=0x80"
)


def _lin11(value: float) -> int:
    """Encode a float as PMBus LINEAR11 (5-bit signed exponent, 11-bit mantissa)."""
    exp = -4
    mantissa = round(value / (2 ** exp))
    while not -1024 <= mantissa <= 1023:
        exp += 1
        mantissa = round(value / (2 ** exp))
    return ((exp & 0x1F) << 11) | (mantissa & 0x7FF)


def i2c_dev_args(miner: Miner) -> list[str]:
    """Return ``--i2c-dev`` CLI arguments for ThorOS I2C port 0 peripherals."""
    temp_c = max(miner.temperature_c, 95.0) if miner.scenario == "overheat" else miner.temperature_c
    temp_reg = max(0, min(125, round(temp_c)))
    return [
        "--i2c-dev", THOR_HUSB238A_SPEC,
        "--i2c-dev", f"0:0x4d,fill=0,reg=0x00=0x{temp_reg:02x}",
    ]


class ThorTps546Device(RegisterDevice):
    """TPS546D24A PMBus regulator model for ThorOS I2C1 (address 0x24)."""

    def __init__(self, *, temperature_c: float = 48.0, power_w: float = 14.0):
        super().__init__({
            0x01: 0x00, 0x02: 0x1F, 0x20: 0x17,
            0x7A: 0, 0x7B: 0, 0x7C: 0, 0x7D: 0, 0x7E: 0, 0x80: 0,
        })
        self.temperature_c = temperature_c
        self.power_w = power_w
        self.words: dict[int, int] = {0x21: round(1.0 * 512)}
        self._pending: bytes | None = None

    def vout(self) -> float:
        if not (self.registers.get(0x01, 0) & 0x80):
            return 0.0
        return self.words.get(0x21, 0) / 512.0

    def _word(self, cmd: int) -> int | None:
        on = bool(self.registers.get(0x01, 0) & 0x80)
        vo = self.vout()
        io = (self.power_w / vo) if (on and vo > 0.1) else 0.0
        telemetry = {
            0x79: 0x0000 if on else 0x0040,
            0x88: _lin11(15.0),
            0x8B: round(vo * 512),
            0x8C: _lin11(io),
            0x8D: _lin11(self.temperature_c if on else 30.0),
            0x96: _lin11(vo * io),
        }
        return telemetry.get(cmd, self.words.get(cmd))

    def transfer(self, write: bytes, read_len: int) -> tuple[bool, bytes]:
        if write:
            cmd = write[0]
            self._pending = None
            if len(write) == 1:
                if cmd == 0xAD:
                    self._pending = bytes([6]) + bytes.fromhex("54 49 54 6d 24 41")
                elif cmd in (0x99, 0x9A, 0x9B, 0x9E):
                    self._pending = b"\x00"
                elif cmd == 0xB1:
                    self._pending = bytes([5]) + bytes(5)
                else:
                    word = self._word(cmd)
                    if word is not None and cmd not in self.registers:
                        self._pending = word.to_bytes(2, "little")
            elif len(write) == 3:
                self.words[cmd] = write[1] | (write[2] << 8)
                return True, b""
        if self._pending is not None:
            reply = self._pending[:read_len].ljust(read_len, b"\x00")
            self._pending = self._pending[read_len:]
            return True, reply
        return super().transfer(write, read_len)


def _bm1373_reply(payload: bytes) -> bytes:
    """Wrap a 6-byte BM1373 register response with 0xAA55 preamble and CRC5."""
    body = bytearray(b"\xaa\x55" + payload + b"\x00")
    for crc in range(32):
        body[-1] = crc
        if _bm_crc5(bytes(body[2:])) == 0:
            return bytes(body)
    raise RuntimeError("BM1373 CRC5 completion not found")


class ThorBoard:
    """ThorOS board model: TPS546 on I2C1 + BM1373 ASIC chain on UART1."""

    addresses = (THOR_TPS546_ADDR,)

    def __init__(self, temperature_c: float = 48.0, *, power_w: float = 14.0,
                 scenario: str = "normal", chip_count: int = 1):
        self.scenario = scenario
        if scenario == "overheat":
            temperature_c = max(temperature_c, 95.0)
        self.temperature_c = temperature_c
        self.power_w = power_w
        self.chip_count = max(1, chip_count)
        self.tps546 = ThorTps546Device(temperature_c=temperature_c, power_w=power_w)
        self.marker = False
        self.uart_baud = 115200
        self._started = time.monotonic()

    def transfer(self, address: int, write: bytes, read_len: int) -> tuple[bool, bytes]:
        if self.scenario == "no-power" and address == THOR_TPS546_ADDR:
            return False, b""
        if address != THOR_TPS546_ADDR:
            return False, b""
        self.marker = True
        return self.tps546.transfer(write, read_len)

    def uart(self, frame: bytes) -> bytes:
        """Answer BM1373 chip-ID discovery, baud switch, and telemetry register reads."""
        if len(frame) < 7 or frame[:2] != b"\x55\xaa":
            return b""
        header, length = frame[2], frame[3]
        if len(frame) != length + 2 or _bm_crc5(frame[2:-1]) != (frame[-1] & 0x1F):
            return b""
        if header == 0x51 and len(frame) >= 10 and frame[5] == 0x28:
            self.uart_baud = 1_000_000
            return b""
        if length == 5 and header in (0x42, 0x52):
            addr, reg = frame[4], frame[5]
            if reg == 0x00:
                if self.scenario == "asic-missing":
                    return b""
                return b"".join(
                    _bm1373_reply(bytes((0x13, 0x73, 0x00, 0x00, idx, 0x00)))
                    for idx in range(self.chip_count)
                )
            if reg == 0x8C:
                count = int((time.monotonic() - self._started) * 235) & 0xFFFFFFFF
                return _bm1373_reply(count.to_bytes(4, "big") + bytes((addr, reg)))
            if reg == 0x4C:
                return _bm1373_reply(b"\x00\x00\x00\x00" + bytes((addr, reg)))
            if reg == 0xB3:
                raw_temp = max(0, min(0xFFFF, round(self.temperature_c * 32)))
                return _bm1373_reply(raw_temp.to_bytes(4, "big") + bytes((addr, reg)))
        return b""


def attach_thor_i2c(port: int, model: Miner | ThorBoard, stop: threading.Event) -> None:
    """Attach ThorBoard TPS546 to esp-emu TCP cosim on GPIO 12/11."""
    board = model if isinstance(model, ThorBoard) else ThorBoard(
        model.temperature_c, power_w=model.power_w, scenario=model.scenario,
        chip_count=model.profile.count,
    )
    attach(port, board, stop, scl=THOR_TPS546_SCL, sda=THOR_TPS546_SDA)


def attach_thor_uart1(port: int, model: Miner | ThorBoard, stop: threading.Event,
                      *, on_event: Callable[[dict[str, object]], None] | None = None) -> None:
    """Connect to esp-emu ``--uart1-tcp`` and serve the ThorOS BM1373 chain."""
    if not 1 <= port <= 65535:
        raise ValueError("invalid UART1 TCP port")
    board = model if isinstance(model, ThorBoard) else ThorBoard(
        model.temperature_c, power_w=model.power_w, scenario=model.scenario,
        chip_count=model.profile.count,
    )
    with socket.create_connection(("127.0.0.1", port), timeout=2) as sock:
        sock.settimeout(0.25)
        pending = bytearray()
        while not stop.is_set():
            try:
                chunk = sock.recv(256)
            except socket.timeout:
                continue
            if not chunk:
                return
            pending.extend(chunk)
            while len(pending) >= 4:
                if pending[:2] != b"\x55\xaa":
                    del pending[0]
                    continue
                if pending[2] == 0x21 and pending[3] == 0xFF:
                    if len(pending) < 88:
                        break
                    del pending[:88]
                    continue
                frame_length = pending[3] + 2
                if frame_length > 128:
                    del pending[0]
                    continue
                if len(pending) < frame_length:
                    break
                frame = bytes(pending[:frame_length])
                del pending[:frame_length]
                response = board.uart(frame)
                if on_event is not None:
                    on_event({
                        "type": "bm1373_chip_id_read" if frame[2:3] == b"\x52" and frame[5:6] == b"\x00"
                        else "uart_frame",
                        "rx_hex": frame[:16].hex(),
                        "tx_hex": response[:16].hex(),
                        "baud": board.uart_baud,
                    })
                if response:
                    sock.sendall(response)
