"""Provision only initial settings in a private copy of the pinned factory flash.

ESP-IDF v6.0.2 NVS format: page header, two-bit state bitmap, 32-byte entries,
CRC32 with seed 0xffffffff; strings use a header plus contiguous data entries.
Only the known active factory page and entries of the pinned image are supported.
No bootloader, executable, partition table, or hardware device is written.
"""

from hashlib import sha256
from pathlib import Path
import struct
from zlib import crc32

from .config import LabError, Miner


NVS_START = 0x9000
NVS_SIZE = 0x6000
PAGE_SIZE = 4096
ENTRY_SIZE = 32
ENTRY_START = 64
SSID = "HashFleet-Lab"
PASSWORD = "virtual-lab-only"
# The release stores these in four-entry strings (65 to 96 bytes including NUL).
POOL_USER = "hashfleet-virtual-miner-not-a-wallet-no-payout-address-or-account-name"


def _crc(data: bytes | bytearray) -> int:
    return crc32(data, 0xFFFFFFFF)


def _entry_crc(entry: bytes | bytearray) -> int:
    return _crc(entry[:4] + entry[8:ENTRY_SIZE])


def _provision_page(page: bytearray, changes: dict[bytes, int | str]) -> None:
    if len(page) != PAGE_SIZE or page[:9] != b"\xfe\xff\xff\xff\x00\x00\x00\x00\xfe":
        raise LabError("unsupported factory NVS page layout")
    namespace = None
    seen: set[bytes] = set()
    index = 0
    while index < (PAGE_SIZE - ENTRY_START) // ENTRY_SIZE:
        flag = (page[32 + index // 4] >> (2 * (index % 4))) & 3
        if flag != 2:
            index += 1
            continue
        offset = ENTRY_START + index * ENTRY_SIZE
        entry = page[offset:offset + ENTRY_SIZE]
        ns, kind, span, _ = entry[:4]
        end = offset + span * ENTRY_SIZE
        if not span or end > PAGE_SIZE or _entry_crc(entry) != int.from_bytes(entry[4:8], "little"):
            raise LabError("invalid entry in factory NVS page")
        key = bytes(entry[8:24]).partition(b"\0")[0]
        if ns == 0 and key == b"main" and kind == 0x01 and span == 1:
            namespace = entry[24]
        if namespace == ns and key in changes:
            if key in seen:
                raise LabError("duplicate factory NVS key")
            value = changes[key]
            if isinstance(value, int) and kind == 0x02 and span == 1:
                struct.pack_into("<H", entry, 24, value)
            elif isinstance(value, str) and kind == 0x21 and span > 1:
                data = value.encode("ascii") + b"\0"
                capacity = (span - 1) * ENTRY_SIZE
                if not capacity - ENTRY_SIZE < len(data) <= capacity:
                    raise LabError("lab NVS setting would change factory entry span")
                struct.pack_into("<H", entry, 24, len(data))
                struct.pack_into("<I", entry, 28, _crc(data))
                page[offset + ENTRY_SIZE:end] = data.ljust(capacity, b"\xff")
            else:
                raise LabError("factory NVS setting type does not match pinned layout")
            struct.pack_into("<I", entry, 4, _entry_crc(entry))
            page[offset:offset + ENTRY_SIZE] = entry
            seen.add(key)
        index += span
    if seen != changes.keys():
        raise LabError("factory NVS settings are incomplete")


def provision(source: Path, destination: Path, miner: Miner) -> str:
    """Write a new, per-run emulator image. Return its SHA-256, not the factory hash."""
    original = source.read_bytes()
    if sha256(original).hexdigest() != miner.profile.flash_sha256:
        raise LabError("factory image digest changed before provisioning")
    record = struct.unpack_from("<HBBII16sI", original, 0x8000)
    if record != (0x50AA, 1, 2, NVS_START, NVS_SIZE, b"nvs".ljust(16, b"\0"), 0):
        raise LabError("pinned factory image has an unexpected NVS partition")
    end = NVS_START + PAGE_SIZE
    page = bytearray(original[NVS_START:end])
    _provision_page(page, {
        b"selftest": 0,
        b"hostname": miner.name,
        b"wifissid": SSID if miner.scenario != "offline" else "No-Lab-AP",
        b"wifipass": PASSWORD,
        b"stratumurl": "pool.invalid",
        b"fbstratumurl": "backup.invalid",
        b"stratumuser": POOL_USER,
        b"fbstratumuser": POOL_USER,
        b"stratumpass": "unused",
        b"fbstratumpass": "unused",
    })
    provisioned = original[:NVS_START] + page + original[end:]
    with destination.open("xb") as stream:
        stream.write(provisioned)
    return sha256(provisioned).hexdigest()
