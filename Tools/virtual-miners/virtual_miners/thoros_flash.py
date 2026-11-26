"""Compose a private flash image that boots an unmodified Hammer ThorOS OTA app.

Hammer publishes only OTA app images for ThorOS boards (no bootloader, partition
table or factory flash). The ThorOS app itself is a normal ESP-IDF v5.5 ESP32-S3
application and is copied byte-for-byte into the ``factory`` slot. Around it we
place, in a disposable copy only:

- the second-stage bootloader from a pinned public ESP-IDF v5.5 factory image
  (Bitfortun BS-1 rev1.3), with its partition-table offset constant changed from
  0x8000 to 0xD000 and the image checksum/SHA-256 recomputed. ThorOS reads its
  table at 0xD000 (``esp_partition_mmap`` in the app), so the bootloader must too;
- a partition table carrying the labels the app opens (``nvs``, ``otadata``,
  ``factory_info``, ``logs``, ``storage``, ``coredump``);
- one NVS page in ``nvs`` with namespace ``thor_cfg`` and ``selftest_done=1``.
  Exactly like the Bitaxe factory self-test flag, this skips the factory
  hardware self-test, which waits forever for real I2C/fan/ASIC hardware.

No ThorOS byte is changed. Nothing is ever written to a device.
"""

from hashlib import md5, sha256
from pathlib import Path
import struct
from zlib import crc32

from .config import LabError

FLASH_SIZE = 0x1000000
BOOTLOADER_SIZE = 0x8000
TABLE_OFFSET = 0xD000
NVS_OFFSET = 0x10000
APP_OFFSET = 0x20000
APP_LIMIT = 0x400000
PAGE = 4096

# name, type, subtype, offset, size. Mirrors the app's expected labels.
PARTITIONS = (
    (b"nvs", 1, 0x02, 0x10000, 0x6000),
    (b"phy_init", 1, 0x01, 0x16000, 0x1000),
    (b"otadata", 1, 0x00, 0x17000, 0x2000),
    (b"factory", 0, 0x00, 0x20000, 0x400000),
    (b"ota_0", 0, 0x10, 0x420000, 0x400000),
    (b"ota_1", 0, 0x11, 0x820000, 0x400000),
    (b"factory_info", 1, 0x02, 0xC20000, 0x6000),
    (b"logs", 1, 0x99, 0xC26000, 0x100000),
    (b"storage", 1, 0x82, 0xD26000, 0x200000),
    (b"coredump", 1, 0x03, 0xF26000, 0x10000),
)


def _crc(data: bytes | bytearray) -> int:
    return crc32(data, 0xFFFFFFFF)


def partition_table() -> bytes:
    rows = bytearray()
    for name, kind, subtype, offset, size in PARTITIONS:
        rows += struct.pack("<2sBBII16sI", b"\xaa\x50", kind, subtype, offset, size, name.ljust(16, b"\0"), 0)
    # ESP-IDF MD5 row: 0xEBEB, padding, then the MD5 of all preceding rows. This is the
    # bootloader's integrity checksum format, not a security control.
    rows += b"\xeb\xeb" + b"\xff" * 14 + md5(rows, usedforsecurity=False).digest()
    return bytes(rows.ljust(0xC00, b"\xff"))


def _nvs_entry(namespace: int, kind: int, key: bytes, value: bytes) -> bytes:
    row = bytearray(b"\xff" * 32)
    row[:4] = bytes((namespace, kind, 1, 0xFF))
    row[8:24] = key.ljust(16, b"\0")
    row[24:24 + len(value)] = value
    struct.pack_into("<I", row, 4, _crc(row[:4] + row[8:]))
    return bytes(row)


def _nvs_string(namespace: int, key: bytes, text: str) -> bytes:
    """ESP-IDF NVS v2 string: header entry plus 32-byte data entries."""
    data = text.encode("ascii") + b"\0"
    if len(key) > 15 or len(data) > 32 * 8:
        raise LabError("ThorOS NVS lab value is too long")
    span = 1 + (len(data) + 31) // 32
    row = bytearray(b"\xff" * 32)
    row[:4] = bytes((namespace, 0x21, span, 0xFF))
    row[8:24] = key.ljust(16, b"\0")
    struct.pack_into("<HHI", row, 24, len(data), 0xFFFF, _crc(data))
    struct.pack_into("<I", row, 4, _crc(row[:4] + row[8:]))
    return bytes(row) + data.ljust((span - 1) * 32, b"\xff")


def selftest_done_page(network: dict[str, str | int] | None = None) -> bytes:
    """One ``thor_cfg`` NVS page: self-test done, plus optional lab Wi-Fi/pool values.

    ``network`` keys are ThorOS's own NVS names (``wifi_ssid``, ``pool_url`` ...).
    Strings are stored as NVS strings, integers as u16 (ThorOS reads ports and
    flags with ``nvs_get_u16``; NVS keeps one item per key, so no second type). Only lab-owned values are ever passed: the emulator's private AP and
    the loopback zero-reward Stratum fixture, never a real pool or wallet.
    """
    page = bytearray(b"\xff" * PAGE)
    struct.pack_into("<IIB", page, 0, 0xFFFFFFFE, 0, 0xFE)
    struct.pack_into("<I", page, 28, _crc(page[4:28]))

    records = _nvs_entry(0, 0x01, b"thor_cfg", b"\x01") + _nvs_entry(1, 0x01, b"selftest_done", b"\x01")
    for name, value in (network or {}).items():
        key = name.encode("ascii")
        if isinstance(value, bool) or not isinstance(value, (str, int)):
            raise LabError("ThorOS NVS lab value must be text or an integer")
        if isinstance(value, str):
            records += _nvs_string(1, key, value)
        else:
            if not 0 <= value <= 0xFFFF:
                raise LabError("ThorOS NVS lab integer out of range")
            records += _nvs_entry(1, 0x02, key, struct.pack("<H", value))
    if 64 + len(records) > PAGE:
        raise LabError("ThorOS NVS lab page overflow")
    page[64:64 + len(records)] = records
    for index in range(len(records) // 32):
        page[32 + index // 4] &= ~(1 << (2 * (index % 4)))
    return bytes(page)


def _relocated_bootloader(reference: bytes) -> bytes:
    boot = bytearray(reference[:BOOTLOADER_SIZE])
    if boot[0] != 0xE9:
        raise LabError("reference image has no ESP bootloader at offset 0")
    hits = [i for i in range(0, BOOTLOADER_SIZE - 4, 4) if struct.unpack_from("<I", boot, i)[0] == 0x8000]
    if len(hits) != 1:
        raise LabError("reference bootloader table offset is not uniquely identifiable")
    struct.pack_into("<I", boot, hits[0], TABLE_OFFSET)
    cursor, checksum = 24, 0xEF
    for _ in range(boot[1]):
        _, length = struct.unpack_from("<II", boot, cursor)
        for byte in boot[cursor + 8:cursor + 8 + length]:
            checksum ^= byte
        cursor += 8 + length
    cursor += 15 - cursor % 16
    boot[cursor] = checksum
    cursor += 1
    if boot[23] == 1:
        boot[cursor:cursor + 32] = sha256(bytes(boot[:cursor])).digest()
    return bytes(boot)


def compose(reference: Path, app: Path, destination: Path,
            network: dict[str, str | int] | None = None) -> str:
    """Write a private flash image and return its SHA-256."""
    application = app.read_bytes()
    if application[:1] != b"\xe9" or not 0 < len(application) <= APP_LIMIT:
        raise LabError("ThorOS update is not an ESP application image")
    if b"thor_cfg\0" not in application or b"selftest_done\0" not in application:
        raise LabError("ThorOS update lacks the expected self-test configuration keys")
    image = bytearray(b"\xff" * FLASH_SIZE)
    image[:BOOTLOADER_SIZE] = _relocated_bootloader(reference.read_bytes())
    table = partition_table()
    image[TABLE_OFFSET:TABLE_OFFSET + len(table)] = table
    image[NVS_OFFSET:NVS_OFFSET + PAGE] = selftest_done_page(network)
    image[APP_OFFSET:APP_OFFSET + len(application)] = application
    destination.write_bytes(image)
    return sha256(image).hexdigest()
