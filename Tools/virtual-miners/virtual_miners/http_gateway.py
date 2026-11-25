"""Loopback-only, GET-only gateway to a fixed guest port forward.

This forwards selected HTTP GET calls to the emulator's host-forward listener on
127.0.0.1. It is not a general proxy and never accepts a target host, port,
URL, path prefix, or forwarding header from an HTTP client. No secrets or
response bodies are logged. WebSocket forwarding is intentionally unsupported.
"""

from __future__ import annotations

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import http.client
import math
from typing import Any


# Verified as GET routes in ESP-Miner v2.15.4 main/http_server/openapi.yaml.
# Exclude logs and Wi-Fi scan. The info response itself may contain sensitive
# device configuration, so callers must handle it as sensitive data.
READ_ONLY_PATHS = frozenset({"/api/system/info", "/api/system/statistics"})


class GatewayServer(ThreadingHTTPServer):
    """Synchronously bound server whose lifecycle remains supervisor-owned."""

    def __init__(self, address: tuple[str, int], handler: type[BaseHTTPRequestHandler]):
        super().__init__(address, handler)
        self.daemon_threads = True

    @property
    def base_url(self) -> str:
        return f"http://127.0.0.1:{self.server_address[1]}"

    def __enter__(self) -> "GatewayServer":
        return self

    def __exit__(self, *_: object) -> None:
        self.server_close()


def make_gateway(
    port: int,
    guest_port: int,
    *,
    timeout_seconds: float = 2.0,
    max_response_bytes: int = 1_048_576,
) -> GatewayServer:
    """Synchronously bind a loopback gateway to one fixed guest forward.

    ``port`` is the local API port. ``guest_port`` is the trusted emulator
    host-forward port and is never sourced from an HTTP request. The server
    binds 127.0.0.1 and supervisor owns ``serve_forever`` / ``shutdown``.
    """

    if isinstance(port, bool) or not isinstance(port, int) or not 0 <= port <= 65535:
        raise ValueError("port must be an integer from 0 to 65535")
    if isinstance(guest_port, bool) or not isinstance(guest_port, int) or not 1 <= guest_port <= 65535:
        raise ValueError("guest_port must be an integer from 1 to 65535")
    upstream_port = guest_port
    http_port = port
    if isinstance(timeout_seconds, bool) or not isinstance(timeout_seconds, (int, float)) or not math.isfinite(timeout_seconds) or not 0 < timeout_seconds <= 30:
        raise ValueError("timeout_seconds must be a finite number greater than 0 and at most 30")
    if isinstance(max_response_bytes, bool) or not isinstance(max_response_bytes, int) or not 1 <= max_response_bytes <= 16 * 1024 * 1024:
        raise ValueError("max_response_bytes must be an integer from 1 byte to 16 MiB")

    class Handler(BaseHTTPRequestHandler):
        def setup(self) -> None:
            super().setup()
            self.connection.settimeout(timeout_seconds)

        def log_message(self, _format: str, *_args: Any) -> None:
            return

        def _reply(
            self,
            status: int,
            body: bytes = b"",
            content_type: str = "application/json",
            *,
            allow: str | None = None,
        ) -> None:
            self.close_connection = True
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            if allow is not None:
                self.send_header("Allow", allow)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            if body:
                self.wfile.write(body)

        def do_GET(self) -> None:
            if self.path not in READ_ONLY_PATHS:
                self._reply(404, b'{"error":"not_found"}')
                return
            if self.headers.get("Transfer-Encoding") or self.headers.get("Content-Length", "0") not in ("", "0"):
                self._reply(400, b'{"error":"request_body_not_allowed"}')
                return

            connection = http.client.HTTPConnection("127.0.0.1", upstream_port, timeout=timeout_seconds)
            try:
                # No inbound headers, credentials, Host, or client body are relayed.
                connection.request("GET", self.path, headers={"Accept": "application/json"})
                response = connection.getresponse()
                if 300 <= response.status < 400:
                    self._reply(502, b'{"error":"upstream_redirect_rejected"}')
                    return
                declared_length = response.getheader("Content-Length")
                if declared_length is not None:
                    try:
                        if int(declared_length) > max_response_bytes:
                            self._reply(502, b'{"error":"upstream_response_too_large"}')
                            return
                    except ValueError:
                        self._reply(502, b'{"error":"invalid_upstream_response"}')
                        return
                body = response.read(max_response_bytes + 1)
                if len(body) > max_response_bytes:
                    self._reply(502, b'{"error":"upstream_response_too_large"}')
                    return
                # This route is documented as JSON. Keep the guest payload
                # bytes unchanged while avoiding reflection of arbitrary headers.
                self._reply(response.status, body, "application/json")
            except (OSError, http.client.HTTPException):
                self._reply(502, b'{"error":"guest_unavailable"}')
            finally:
                connection.close()

        def _deny(self) -> None:
            self._reply(405, b'{"error":"method_not_allowed"}', allow="GET")

        do_HEAD = _deny
        do_POST = _deny
        do_PUT = _deny
        do_PATCH = _deny
        do_DELETE = _deny
        do_OPTIONS = _deny
        do_CONNECT = _deny
        do_TRACE = _deny

    return GatewayServer(("127.0.0.1", http_port), Handler)
