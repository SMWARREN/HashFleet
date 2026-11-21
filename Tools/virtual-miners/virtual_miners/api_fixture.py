"""Loopback-only AxeOS-shaped API fixture, never an emulator or real firmware.

This module exists solely for HashFleet API integration tests. It serves two
read-only GET endpoints on IPv4 loopback and performs no discovery, writes,
proxying, or outbound network access.
"""

from __future__ import annotations

from dataclasses import dataclass
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import threading
from typing import Any, Mapping


@dataclass(frozen=True)
class FixtureConfig:
    """Configuration for one isolated API fixture instance.

    ``scenario`` is metadata only for now. Supported labels are ``normal``
    and ``degraded``. The API is intentionally not a firmware execution.
    Use port 0 to request an OS-assigned ephemeral port in tests.
    """

    name: str
    board: str
    http_port: int
    scenario: str = "normal"


class FixtureServer(ThreadingHTTPServer):
    """Bound, synchronous fixture server for supervisor-owned lifecycle."""

    def __init__(self, address: tuple[str, int], handler: type[BaseHTTPRequestHandler]):
        super().__init__(address, handler)
        self.daemon_threads = True

    @property
    def base_url(self) -> str:
        return f"http://127.0.0.1:{self.server_address[1]}"

    def __enter__(self) -> "FixtureServer":
        return self

    def __exit__(self, *_: object) -> None:
        self.server_close()


class _BackgroundFixture:
    """Convenience wrapper returned by :func:`serve` for standalone use."""

    def __init__(self, server: FixtureServer, thread: threading.Thread):
        self.server = server
        self._thread = thread

    @property
    def address(self) -> tuple[str, int]:
        return str(self.server.server_address[0]), int(self.server.server_address[1])

    @property
    def base_url(self) -> str:
        return self.server.base_url

    def close(self) -> None:
        self.server.shutdown()
        self.server.server_close()
        self._thread.join(timeout=2)

    def __enter__(self) -> "_BackgroundFixture":
        return self

    def __exit__(self, *_: object) -> None:
        self.close()


def _config_value(config: FixtureConfig | Mapping[str, Any] | Any, key: str) -> Any:
    if isinstance(config, Mapping):
        return config[key]
    return getattr(config, key)


def _validate_config(config: FixtureConfig | Mapping[str, Any] | Any) -> tuple[str, str, int, str]:
    name = _config_value(config, "name")
    board = _config_value(config, "board")
    port = _config_value(config, "http_port")
    scenario = _config_value(config, "scenario")
    if not isinstance(name, str) or not name.strip():
        raise ValueError("name must be a non-empty string")
    if not isinstance(board, str) or not board.strip():
        raise ValueError("board must be a non-empty string")
    if isinstance(port, bool) or not isinstance(port, int) or not 0 <= port <= 65535:
        raise ValueError("http_port must be an integer from 0 to 65535")
    if not isinstance(scenario, str) or scenario not in {"normal", "degraded"}:
        raise ValueError("scenario must be 'normal' or 'degraded'")
    return name.strip(), board.strip(), port, scenario


def make_fixture(config: FixtureConfig | Mapping[str, Any] | Any) -> FixtureServer:
    """Bind the fixture synchronously on IPv4 loopback, without a thread.

    Exact routes are GET /api/system/info and GET /healthz. Every other path
    returns 404 and non-GET methods return 405.
    """

    name, board, port, scenario = _validate_config(config)
    # Minimal typed subset of ESP-Miner's documented SystemInfo schema. Values
    # are synthetic test data and do not represent a running miner.
    info = {
        "ASICModel": "virtual-fixture",
        "boardVersion": board,
        "hostname": name,
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
    }
    health = {
        "status": "ok" if scenario == "normal" else "degraded",
        "fixture": True,
        "kind": "api-only",
        "firmware_execution": False,
    }

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, _format: str, *_args: Any) -> None:
            return

        def _send(self, status: int, payload: dict[str, Any]) -> None:
            body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("X-Virtual-Miner-Fixture", "api-only")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self) -> None:
            if self.path == "/api/system/info":
                self._send(200, info)
            elif self.path == "/healthz":
                self._send(200, health)
            else:
                self._send(404, {"error": "not_found", "fixture": True})

        def _deny(self) -> None:
            self.send_response(405)
            self.send_header("Allow", "GET")
            self.send_header("Content-Length", "0")
            self.end_headers()

        do_HEAD = _deny
        do_POST = _deny
        do_PUT = _deny
        do_PATCH = _deny
        do_DELETE = _deny
        do_OPTIONS = _deny
        do_CONNECT = _deny
        do_TRACE = _deny

    return FixtureServer(("127.0.0.1", port), Handler)


def serve(config: FixtureConfig | Mapping[str, Any] | Any) -> _BackgroundFixture:
    """Convenience API: bind and serve a fixture on a background thread.

    Supervisors that own their own thread/lifecycle should use
    :func:`make_fixture`, which returns a synchronously bound server.
    """

    server = make_fixture(config)
    thread = threading.Thread(target=server.serve_forever, name="api-only-fixture", daemon=True)
    thread.start()
    return _BackgroundFixture(server, thread)
