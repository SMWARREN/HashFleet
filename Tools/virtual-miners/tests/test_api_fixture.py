from __future__ import annotations

import json
from threading import Thread
from urllib.error import HTTPError
from urllib.request import Request, urlopen

import unittest

from virtual_miners.api_fixture import FixtureConfig, make_fixture, serve


def get_json(url: str) -> dict[str, object]:
    with urlopen(url, timeout=2) as response:
        if response.status != 200:
            raise AssertionError(f"expected 200, got {response.status}")
        if response.headers.get_content_type() != "application/json":
            raise AssertionError("expected application/json")
        return json.loads(response.read())


class ApiFixtureTests(unittest.TestCase):
    def test_fixture_serves_documented_typed_info_subset_and_fixture_health(self) -> None:
        with serve(FixtureConfig(name="fixture-a", board="Gamma", http_port=0)) as fixture:
            self.assertEqual(fixture.address[0], "127.0.0.1")
            info = get_json(f"{fixture.base_url}/api/system/info")
            self.assertEqual(info, {
                "ASICModel": "virtual-fixture",
                "boardVersion": "Gamma",
                "hostname": "fixture-a",
                "power": 0.0,
                "current": 0.0,
                "temp": 0.0,
                "hashRate": 0.0,
                "sharesAccepted": 0,
                "sharesRejected": 0,
                "smallCoreCount": 0,
                "voltage": 0.0,
                "uptimeSeconds": 0.0,
                "version": "api-fixture",
            })
            health = get_json(f"{fixture.base_url}/healthz")
            self.assertEqual(health, {
                "status": "ok",
                "fixture": True,
                "kind": "api-only",
                "firmware_execution": False,
            })

    def test_make_fixture_is_synchronously_bound_for_supervisor_lifecycle(self) -> None:
        fixture = make_fixture(FixtureConfig("sync-fixture", "Gamma", 0))
        self.assertEqual(fixture.server_address[0], "127.0.0.1")
        thread = Thread(target=fixture.serve_forever, daemon=True)
        thread.start()
        try:
            self.assertIs(get_json(f"{fixture.base_url}/healthz")["firmware_execution"], False)
        finally:
            fixture.shutdown()
            fixture.server_close()
            thread.join(timeout=2)
            self.assertFalse(thread.is_alive())

    def test_instances_keep_identity_and_scenario_isolated(self) -> None:
        with (
            serve({"name": "alpha", "board": "Gamma", "http_port": 0, "scenario": "normal"}) as first,
            serve({"name": "beta", "board": "NerdQAxe", "http_port": 0, "scenario": "degraded"}) as second,
        ):
            self.assertNotEqual(first.address, second.address)
            self.assertEqual(get_json(f"{first.base_url}/api/system/info")["hostname"], "alpha")
            self.assertEqual(get_json(f"{second.base_url}/api/system/info")["hostname"], "beta")
            self.assertEqual(get_json(f"{first.base_url}/api/system/info")["boardVersion"], "Gamma")
            self.assertEqual(get_json(f"{second.base_url}/api/system/info")["boardVersion"], "NerdQAxe")
            self.assertEqual(get_json(f"{first.base_url}/healthz")["status"], "ok")
            self.assertEqual(get_json(f"{second.base_url}/healthz")["status"], "degraded")

    def test_only_exact_get_routes_are_exposed(self) -> None:
        with serve(FixtureConfig("fixture", "board", 0)) as fixture:
            for path in ("/", "/api/system/info/", "/api/system/info?x=1", "/api/system/logs"):
                with self.subTest(path=path), self.assertRaises(HTTPError) as error:
                    urlopen(fixture.base_url + path, timeout=2)
                self.assertEqual(error.exception.code, 404)

    def test_non_get_methods_are_denied(self) -> None:
        for method in ("HEAD", "POST", "PUT", "PATCH", "DELETE", "OPTIONS", "TRACE"):
            with self.subTest(method=method), serve(FixtureConfig("fixture", "board", 0)) as fixture:
                request = Request(f"{fixture.base_url}/api/system/info", method=method)
                with self.assertRaises(HTTPError) as error:
                    urlopen(request, timeout=2)
                self.assertEqual(error.exception.code, 405)
                self.assertEqual(error.exception.headers["Allow"], "GET")

    def test_config_rejects_invalid_scenarios_and_ports(self) -> None:
        with self.assertRaisesRegex(ValueError, "scenario"):
            serve({"name": "x", "board": "y", "http_port": 0, "scenario": "write-enabled"})
        with self.assertRaisesRegex(ValueError, "http_port"):
            serve({"name": "x", "board": "y", "http_port": -1, "scenario": "normal"})
