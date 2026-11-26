import struct
import tempfile
import unittest
from hashlib import md5, sha256
from pathlib import Path

from virtual_miners import thoros_flash
from virtual_miners.config import LabError


def _bootloader() -> bytes:
    # One-segment ESP image with a single 0x8000 literal, checksum and appended SHA-256.
    payload = bytearray(b"\x00" * 64)
    struct.pack_into("<I", payload, 16, 0x8000)
    header = bytearray(24)
    header[0], header[1], header[23] = 0xE9, 1, 1
    body = header + struct.pack("<II", 0x403C8700, len(payload)) + payload
    pad = 15 - len(body) % 16
    body += b"\x00" * pad + b"\x00"
    body += sha256(bytes(body)).digest()
    return bytes(body).ljust(0x8000, b"\xff")


class ThorOSFlashTests(unittest.TestCase):
    def test_table_has_labels_and_valid_md5(self):
        table = thoros_flash.partition_table()
        rows = len(thoros_flash.PARTITIONS) * 32
        self.assertEqual(table[rows:rows + 2], b"\xeb\xeb")
        self.assertEqual(table[rows + 16:rows + 32], md5(table[:rows], usedforsecurity=False).digest())
        for label in (b"nvs\0", b"factory\0", b"factory_info\0", b"logs\0", b"storage\0", b"otadata\0"):
            self.assertIn(label, table)

    def test_nvs_page_sets_selftest_done_in_thor_cfg(self):
        page = thoros_flash.selftest_done_page()
        self.assertEqual(page[64 + 8:64 + 16], b"thor_cfg")
        second = page[96:128]
        self.assertEqual(second[0], 1)  # namespace index 1
        self.assertEqual(second[1], 0x01)  # u8
        self.assertEqual(second[8:21], b"selftest_done")
        self.assertEqual(second[24], 1)

    def test_nvs_page_encodes_network_strings_and_u16(self):
        page = thoros_flash.selftest_done_page({"wifi_ssid": "LabNet", "pool_port": 3333})
        self.assertIn(b"wifi_ssid\0", page)
        self.assertIn(b"LabNet\0", page)
        self.assertIn(b"pool_port\0", page)
        self.assertIn(struct.pack("<H", 3333), page)

    def test_compose_keeps_vendor_app_bytes_and_relocates_table(self):
        app = b"\xe9" + b"thor_cfg\0selftest_done\0".ljust(4095, b"\x5a")
        with tempfile.TemporaryDirectory() as tmp:
            reference, update, out = Path(tmp, "ref.bin"), Path(tmp, "app.bin"), Path(tmp, "flash.bin")
            reference.write_bytes(_bootloader())
            update.write_bytes(app)
            digest = thoros_flash.compose(reference, update, out)
            image = out.read_bytes()
        self.assertEqual(sha256(image).hexdigest(), digest)
        self.assertEqual(image[thoros_flash.APP_OFFSET:thoros_flash.APP_OFFSET + len(app)], app)
        self.assertEqual(image[thoros_flash.TABLE_OFFSET:thoros_flash.TABLE_OFFSET + 2], b"\xaa\x50")
        self.assertNotIn(struct.pack("<I", 0x8000), image[:0x100])
        self.assertIn(struct.pack("<I", 0xD000), image[:0x100])

    def test_rejects_non_thoros_app(self):
        with tempfile.TemporaryDirectory() as tmp:
            reference, update = Path(tmp, "ref.bin"), Path(tmp, "app.bin")
            reference.write_bytes(_bootloader())
            update.write_bytes(b"\xe9" + b"\0" * 100)
            with self.assertRaises(LabError):
                thoros_flash.compose(reference, update, Path(tmp, "out.bin"))


if __name__ == "__main__":
    unittest.main()
