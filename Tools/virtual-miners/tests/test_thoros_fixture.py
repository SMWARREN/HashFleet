from __future__ import annotations

import json
from pathlib import Path
import tempfile
from urllib.request import urlopen
import unittest

from virtual_miners.api_fixture import FixtureConfig, serve
from virtual_miners.config import LabError, load


class ThorOSFixtureTests(unittest.TestCase):
    def test_thor_profile_serves_thoros_routes_and_html_for_axeos_paths(self) -> None:
        with serve(FixtureConfig(name="thor-p2", board="thor-p2", http_port=0)) as fixture:
            with urlopen(f"{fixture.base_url}/v2/device/info", timeout=2) as response:
                info = json.loads(response.read())["data"]
            self.assertEqual(info["device_model"], "THOR P2")
            self.assertEqual(info["chip_type"], "BM1373")
            self.assertEqual(info["detected_chips_count"], 2)
            with urlopen(f"{fixture.base_url}/v2/miner/status", timeout=2) as response:
                miner = json.loads(response.read())["data"]
            self.assertAlmostEqual(miner["current_hashrate"], 6.4e12)
            with urlopen(f"{fixture.base_url}/api/system/info", timeout=2) as response:
                self.assertEqual(response.headers.get_content_type(), "text/html")

    def test_thor_profile_cannot_select_emulator(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "lab.toml"
            path.write_text(
                '[[miner]]\nname = "thor"\nboard = "thor-x1"\nbackend = "esp-emu"\nhttp_port = 18190\n'
            )
            with self.assertRaises(LabError):
                load(path)


if __name__ == "__main__":
    unittest.main()
