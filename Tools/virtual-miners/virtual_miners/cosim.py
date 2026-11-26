"""Loopback-only ESP emulator co-simulation transport and Gamma 601 board.

Transport helpers are a minimal implementation of Espressif esp-emu's
Apache-2.0 documented protobuf wire protocol (proto/esp_cosim.proto).
"""
from __future__ import annotations

import socket
import struct
import threading
import select
from collections.abc import Callable

from .config import Miner


def _varint(value: int) -> bytes:
    out = bytearray()
    while value > 127:
        out.append((value & 127) | 128)
        value >>= 7
    out.append(value)
    return bytes(out)


def _vfield(number: int, value: int) -> bytes:
    return _varint(number << 3) + _varint(value)


def _bytes_field(number: int, payload: bytes) -> bytes:
    return _varint(number << 3 | 2) + _varint(len(payload)) + payload


def _bm_crc5(data: bytes) -> int:
    """ESP-Miner components/asic/crc.c CRC5, polynomial x^5+x^2+1."""
    crc = 0x1F
    for byte in data:
        for shift in range(7, -1, -1):
            bit = (byte >> shift) & 1
            new_bit = ((crc >> 4) ^ bit) & 1
            crc = ((crc << 1) | new_bit) ^ (new_bit << 2)
            crc &= 0x1F
    return crc


def _decode(payload: bytes) -> dict[int, object]:
    fields: dict[int, object] = {}
    i = 0
    def varint() -> int:
        nonlocal i
        value = shift = 0
        while i < len(payload):
            byte = payload[i]; i += 1
            value |= (byte & 127) << shift
            if byte < 128:
                return value
            shift += 7
            if shift > 63:
                raise ValueError("oversized protobuf varint")
        raise ValueError("truncated protobuf varint")
    while i < len(payload):
        tag = varint(); number, wire = tag >> 3, tag & 7
        if wire == 0:
            value = varint()
        elif wire == 2:
            length = varint(); value = payload[i:i + length]; i += length
            if len(value) != length: raise ValueError("truncated protobuf field")
        elif wire == 1:
            value = payload[i:i + 8]; i += 8
        elif wire == 5:
            value = payload[i:i + 4]; i += 4
        else:
            raise ValueError("unsupported protobuf wire type")
        fields[number] = value
    return fields


def _recv_exact(sock: socket.socket, size: int) -> bytes:
    data = bytearray()
    while len(data) < size:
        chunk = sock.recv(size - len(data))
        if not chunk:
            raise EOFError("co-simulation peer disconnected")
        data.extend(chunk)
    return bytes(data)


def _recv(sock: socket.socket) -> tuple[bytes, bytes]:
    size, = struct.unpack("<I", _recv_exact(sock, 4))
    if size > 262144: raise ValueError("co-simulation frame too large")
    frame = _recv_exact(sock, size)
    topic_size, = struct.unpack("<H", frame[:2])
    return frame[2:2 + topic_size], frame[2 + topic_size:]


def _send(sock: socket.socket, payload: bytes) -> None:
    sock.sendall(struct.pack("<I", len(payload)) + payload)


class RegisterDevice:
    """Simple 8-bit register-pointer peripheral."""
    def __init__(self, registers: dict[int, int] | None = None):
        self.registers = dict(registers or {})
        self.cursor = 0
    def transfer(self, write: bytes, read_len: int) -> tuple[bool, bytes]:
        if write:
            self.cursor = write[0]
            for offset, byte in enumerate(write[1:]):
                self.registers[(self.cursor + offset) & 255] = byte
            self.cursor = (self.cursor + max(0, len(write) - 1)) & 255
        result = bytes(self.registers.get((self.cursor + n) & 255, 0) for n in range(read_len))
        self.cursor = (self.cursor + read_len) & 255
        return True, result


class Tps546Device(RegisterDevice):
    """PMBus block device response needed by ESP-Miner's original init."""
    def __init__(self, registers: dict[int, int] | None = None,
                 words: dict[int, int] | None = None):
        super().__init__(registers)
        self.words = dict(words or {})

    def transfer(self, write: bytes, read_len: int) -> tuple[bool, bytes]:
        blocks = {
            0xAD: bytes.fromhex("54 49 54 6d 24 41"),  # exact accepted TPS546D24A ID
            0x99: b"", 0x9A: b"", 0x9B: b"",  # safe empty manufacturer text
            0xB1: bytes(5),  # default compensation block used by Gamma config
        }
        if write and write[0] in blocks and read_len:
            data = blocks[write[0]]
            return True, bytes([len(data)]) + data + bytes(max(0, read_len - 1 - len(data)))
        if write and len(write) == 1 and read_len:
            command = write[0]
            if command in self.words:
                return True, self.words[command].to_bytes(2, "little")[:read_len]
            if command == 0x20:
                return True, b"\x17"[:read_len]
            if command == 0x79:
                return True, b"\x00" * read_len
        return super().transfer(write, read_len)


class GammaBoard:
    """Gamma 601 peripheral set. BM1370 UART modeling is exposed separately."""
    addresses = (0x4C, 0x24, 0x3C)
    def __init__(self, temperature_c: float = 48.0, *, power_w: float = 14.0,
                 scenario: str = "normal"):
        self.scenario = scenario
        if scenario == "overheat":
            temperature_c = max(temperature_c, 95.0)  # above firmware MAX_TEMP 90C
        self.power_w = power_w
        external = round(temperature_c * 8) << 5
        tach = 1800  # 5400000 / 1800 = 3000 RPM, nonzero to avoid driver divide-by-zero.
        self.emc2101 = RegisterDevice({
            0x00: round(temperature_c), 0x01: (external >> 8) & 0xFF,
            0x10: external & 0xFF, 0x46: tach & 0xFF, 0x47: tach >> 8,
            0xFD: 0x16, 0xFE: 0xFF,
        })
        # STATUS_WORD defaults to no asserted fault; the prior placeholder's
        # 0x21 falsely asserted VOUT_OV and blocked regulator startup.
        iout = max(0, min(255, round(power_w / 1.15)))
        vout = round(1.15 * 512)  # VOUT_MODE 0x17: exponent -9, 1.15 V
        self.tps546 = Tps546Device({0x7e: 0x00, 0x7f: 0x00}, {
            0x88: 0x0005, 0x8b: vout, 0x8c: iout, 0x79: 0,
        })
        self.oled = RegisterDevice()
        self.i2c = {0x4c: self.emc2101, 0x24: self.tps546, 0x3c: self.oled}
        self.marker = False
        self.uart_baud = 115200
        self.uart_baud_milestones = [115200]
    def transfer(self, address: int, write: bytes, read_len: int) -> tuple[bool, bytes]:
        if self.scenario == "no-power" and address == 0x24: return False, b""
        device = self.i2c.get(address)
        if device is None: return False, b""
        self.marker = True
        return device.transfer(write, read_len)
    def uart(self, frame: bytes) -> bytes:
        """Return the original ESP-Miner BM1370 CHIP_ID response fixture.

        ESP-Miner's accepted ID is 0x1370 (components/asic/bm1370.c),
        compared literally by asic_common.c. The 0x1368 comment in bm1370.c
        is stale. CRC5 is computed from the pinned ESP-Miner implementation.
        """
        if len(frame) < 7 or frame[:2] != b"\x55\xaa": return b""
        header, length = frame[2], frame[3]
        if len(frame) != length + 2 or _bm_crc5(frame[2:-1]) != (frame[-1] & 0x1F): return b""
        if self.scenario == "asic-missing" and frame[2] == 0x52 and frame[4:6] == b"\x00\x00":
            return b""
        if header == 0x51 and len(frame) >= 10 and frame[5] == 0x28:
            # BM1370_set_max_baud writes FAST_UART_CONFIGURATION then ESP-Miner
            # changes UART1 from 115200 to 1000000 after the TX drains.
            self.uart_baud = 1_000_000
            self.uart_baud_milestones.append(self.uart_baud)
            return b""
        if length == 5 and header == 0x52 and frame[4:6] == b"\x00\x00":
            response = bytearray.fromhex("aa 55 13 70 00 00 00 00 00 00 00")
            for crc in range(32):
                response[-1] = crc
                if _bm_crc5(bytes(response[2:])) == 0:
                    break
            else:
                raise RuntimeError("BM1370 CRC5 completion not found")
            return bytes(response)
        return b""


def attach_uart1(port: int, model: Miner | GammaBoard, stop: threading.Event,
                 *, on_event: Callable[[dict[str, object]], None] | None = None) -> None:
    """Connect to esp-emu's --uart1-tcp server and answer BM1370 ID reads.

    Run alongside esp-emu configured with `--uart1-tcp 127.0.0.1:<port>`.
    This raw TCP bridge exposes bytes only, not baud-rate changes.
    """
    if not 1 <= port <= 65535: raise ValueError("invalid UART1 TCP port")
    board = model if isinstance(model, GammaBoard) else GammaBoard(
        model.temperature_c, power_w=model.power_w, scenario=model.scenario)
    with socket.create_connection(("127.0.0.1", port), timeout=2) as sock:
        sock.settimeout(.25)
        pending = bytearray()
        while not stop.is_set():
            try:
                chunk = sock.recv(256)
            except socket.timeout:
                continue
            if not chunk: return
            pending.extend(chunk)
            while len(pending) >= 4:
                if pending[:2] != b"\x55\xaa":
                    del pending[0]
                    continue
                frame_length = pending[3] + 2
                if frame_length > 128:
                    del pending[0]
                    continue
                if len(pending) < frame_length: break
                frame = bytes(pending[:frame_length])
                del pending[:frame_length]
                response = board.uart(frame)
                if on_event is not None:
                    event: dict[str, object] = {
                        "type": "bm1370_fast_baud" if frame[2:3] == b"\x51" and frame[5:6] == b"\x28"
                        else "bm1370_chip_id_read" if frame[2:3] == b"\x52" and frame[5:6] == b"\x00"
                        else "uart_frame",
                        "rx_hex": frame[:16].hex(), "rx_length": len(frame),
                        "tx_hex": response[:16].hex(), "tx_length": len(response),
                        "baud": board.uart_baud,
                    }
                    on_event(event)
                if response:
                    sock.sendall(response)


def _claim(addr: int, scl: int, sda: int) -> bytes:
    body = _vfield(1, addr) + _vfield(2, scl) + _vfield(3, sda)
    return _bytes_field(2, body)


def attach(port: int, model: Miner | GammaBoard, stop: threading.Event,
           *, scl: int = 48, sda: int = 47) -> None:
    """Connect to esp-emu TCP cosim bound to loopback and serve board I2C."""
    if not 1 <= port <= 65535: raise ValueError("invalid co-simulation port")
    board = model if hasattr(model, "transfer") else GammaBoard(
        model.temperature_c, power_w=model.power_w, scenario=model.scenario)
    claims = () if isinstance(model, Miner) and model.hardware == "bare" else board.addresses
    registration = _vfield(1, 1) + _bytes_field(2, b"gamma-board") + b"".join(
        _bytes_field(3, _claim(addr, scl, sda)) for addr in claims)
    with socket.create_connection(("127.0.0.1", port), timeout=2) as sock:
        _send(sock, _bytes_field(4, registration))
        sock.settimeout(None)
        registered = False
        while not stop.is_set():
            readable, _, _ = select.select([sock], [], [], .25)
            if not readable: continue
            try: topic, payload = _recv(sock)
            except EOFError: return
            if topic.startswith(b"@"):
                outer = _decode(payload)
                ack = outer.get(5)
                if isinstance(ack, bytes):
                    accepted = _decode(ack)
                    if not accepted.get(5, 0):
                        raise RuntimeError("esp-emu refused Gamma board registration")
                    registered = True
                    continue
            if not registered:
                continue
            outer = _decode(payload)
            request = outer.get(7)
            if not isinstance(request, bytes): continue
            msg = _decode(request); correlation = int(msg.get(1, 0))
            tx = msg.get(2)
            if not isinstance(tx, bytes): continue
            bus = _decode(tx)
            ack, data = board.transfer(int(bus.get(2, 0)), bus.get(3, b""), int(bus.get(4, 0)))
            reply = _vfield(1, correlation) + _vfield(2, int(ack)) + _bytes_field(3, data) + _vfield(4, 1)
            _send(sock, _bytes_field(8, reply))
