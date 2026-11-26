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
            self.assertGreater(miner["current_hashrate"], 1e12)
            with urlopen(f"{fixture.base_url}/api/system/info", timeout=2) as response:
                self.assertEqual(response.headers.get_content_type(), "text/html")

    def test_thor_profile_accepts_emulator_board_mode(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "lab.toml"
            path.write_text(
                '[[miner]]\nname = "thor"\nboard = "thor-x1"\nbackend = "esp-emu"\nhttp_port = 18190\n'
            )
            miners = load(path)
            self.assertEqual(miners["thor"].hardware, "board")


if __name__ == "__main__":
    unittest.main()


class ThorOSWriteTests(unittest.TestCase):
    def _call(self, base, path, method="GET", body=None):
        from urllib.request import Request
        from urllib.error import HTTPError
        data = json.dumps(body).encode() if body is not None else None
        req = Request(base + path, data=data, method=method, headers={"Content-Type": "application/json"})
        try:
            with urlopen(req, timeout=2) as r:
                return r.status, json.loads(r.read())
        except HTTPError as e:
            with e:
                return e.code, json.loads(e.read() or b"null")

    def test_settings_writes_drive_telemetry(self) -> None:
        with serve(FixtureConfig(name="thor-x1", board="thor-x1", http_port=0)) as fx:
            b = fx.base_url
            _, before = self._call(b, "/v2/miner/status")
            code, out = self._call(b, "/v2/miner/config", "PUT",
                                   {"core_frequency": 475, "fan_mode": 1, "fan_target_speed": 100})
            self.assertEqual((code, out["ok"]), (200, True))
            _, after = self._call(b, "/v2/miner/status")
            self.assertEqual(after["data"]["frequency"], 475)
            self.assertGreater(after["data"]["current_hashrate"], before["data"]["current_hashrate"])
            self.assertGreater(after["data"]["fan_speed_rpm"], before["data"]["fan_speed_rpm"])
            code, out = self._call(b, "/v2/miner/config", "PUT", {"core_frequency": 5000})
            self.assertEqual((code, out["ok"]), (400, False))
            code, out = self._call(b, "/v2/device/reboot", "POST")
            self.assertEqual((code, out["ok"]), (200, True))
            code, _ = self._call(b, "/v2/miner/config", "DELETE")
            self.assertEqual(code, 405)
