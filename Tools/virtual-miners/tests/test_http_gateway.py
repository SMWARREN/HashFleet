from __future__ import annotations

from contextlib import contextmanager
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import threading
from urllib.error import HTTPError
from urllib.request import Request, urlopen

import unittest

from virtual_miners.http_gateway import READ_ONLY_PATHS, make_gateway


class UpstreamHandler(BaseHTTPRequestHandler):
    def do_GET(self) -> None:
        self.server.seen_path = self.path
        self.server.seen_authorization = self.headers.get("Authorization")
        if self.path in {"/api/system/info", "/api/system/statistics"}:
            if getattr(self.server, "redirect", False):
                self.send_response(302)
                self.send_header("Location", "http://example.invalid/secret")
                self.end_headers()
                return
            if self.path == "/api/system/statistics":
                body = b'{"currentTimestamp":1,"labels":["timestamp"],"statistics":[[1]]}'
            else:
                body = getattr(self.server, "body", b'{"exact":true}')
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Set-Cookie", "secret=not-forwarded")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        self.send_error(404)

    def log_message(self, _format: str, *_args: object) -> None:
        return


def start(server: ThreadingHTTPServer) -> threading.Thread:
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return thread


@contextmanager
def running_gateway(guest_port: int, **options: object):
    gateway = make_gateway(0, guest_port, **options)
    thread = start(gateway)
    try:
        yield gateway
    finally:
        gateway.shutdown()
        gateway.server_close()
        thread.join(timeout=2)


class HttpGatewayTests(unittest.TestCase):
    def test_gateway_forwards_exact_body_only_to_fixed_local_guest_port(self) -> None:
        upstream = ThreadingHTTPServer(("127.0.0.1", 0), UpstreamHandler)
        upstream.seen_path = None
        upstream.seen_authorization = None
        thread = start(upstream)
        try:
            with running_gateway(upstream.server_address[1]) as gateway:
                self.assertEqual(gateway.server_address[0], "127.0.0.1")
                request = Request(
                    gateway.base_url + "/api/system/info",
                    headers={"Authorization": "Bearer do-not-forward", "Host": "attacker.invalid"},
                )
                with urlopen(request, timeout=2) as response:
                    payload = response.read()
                    self.assertEqual(response.status, 200)
                    self.assertIsNone(response.headers.get("Set-Cookie"))
                self.assertEqual(payload, b'{"exact":true}')
                self.assertEqual(upstream.seen_path, "/api/system/info")
                self.assertIsNone(upstream.seen_authorization)
        finally:
            upstream.shutdown()
            upstream.server_close()
            thread.join(timeout=2)

    def test_gateway_forwards_exact_statistics_body(self) -> None:
        upstream = ThreadingHTTPServer(("127.0.0.1", 0), UpstreamHandler)
        thread = start(upstream)
        try:
            with running_gateway(upstream.server_address[1]) as gateway:
                with urlopen(gateway.base_url + "/api/system/statistics", timeout=2) as response:
                    payload = response.read()
                    self.assertEqual(response.status, 200)
                    self.assertEqual(response.headers.get_content_type(), "application/json")
                self.assertEqual(
                    payload,
                    b'{"currentTimestamp":1,"labels":["timestamp"],"statistics":[[1]]}',
                )
                self.assertEqual(upstream.seen_path, "/api/system/statistics")
        finally:
            upstream.shutdown()
            upstream.server_close()
            thread.join(timeout=2)

    def test_gateway_allowlist_is_exact_and_non_get_is_denied(self) -> None:
        upstream = ThreadingHTTPServer(("127.0.0.1", 0), UpstreamHandler)
        thread = start(upstream)
        try:
            with running_gateway(upstream.server_address[1]) as gateway:
                for path in (
                    "/api/system",
                    "/api/system/info/",
                    "/api/system/logs",
                    "/api/ws",
                    "/api/system/statistics/",
                    "/api/system/statistics?columns=power",
                    "/api/system/statistics/0",
                    "/api/system/info?x=1",
                ):
                    with self.subTest(path=path), self.assertRaises(HTTPError) as error:
                        urlopen(gateway.base_url + path, timeout=2)
                    self.assertEqual(error.exception.code, 404)
                for method in ("HEAD", "POST", "PUT", "PATCH", "DELETE", "OPTIONS", "TRACE"):
                    request = Request(gateway.base_url + "/api/system/statistics", method=method)
                    with self.subTest(method=method), self.assertRaises(HTTPError) as error:
                        urlopen(request, timeout=2)
                    self.assertEqual(error.exception.code, 405)
                    self.assertEqual(error.exception.headers["Allow"], "GET")
                # AxeOS reads plus the four documented ThorOS GET routes. Writes and
                # /v2/device/reboot, /v2/logs/history and Wi-Fi scan stay excluded.
                self.assertEqual(READ_ONLY_PATHS, {
                    "/api/system/info", "/api/system/statistics",
                    "/v2/device/info", "/v2/device/status", "/v2/miner/status", "/v2/miner/config",
                })
        finally:
            upstream.shutdown()
            upstream.server_close()
            thread.join(timeout=2)

    def test_gateway_rejects_redirect_without_following_or_forwarding_location(self) -> None:
        upstream = ThreadingHTTPServer(("127.0.0.1", 0), UpstreamHandler)
        upstream.redirect = True
        thread = start(upstream)
        try:
            with running_gateway(upstream.server_address[1]) as gateway:
                with self.assertRaises(HTTPError) as error:
                    urlopen(gateway.base_url + "/api/system/info", timeout=2)
                self.assertEqual(error.exception.code, 502)
                self.assertIsNone(error.exception.headers.get("Location"))
        finally:
            upstream.shutdown()
            upstream.server_close()
            thread.join(timeout=2)

    def test_gateway_enforces_response_byte_limit(self) -> None:
        upstream = ThreadingHTTPServer(("127.0.0.1", 0), UpstreamHandler)
        upstream.body = json.dumps({"x": "a" * 80}).encode()
        thread = start(upstream)
        try:
            with running_gateway(upstream.server_address[1], max_response_bytes=32) as gateway:
                with self.assertRaises(HTTPError) as error:
                    urlopen(gateway.base_url + "/api/system/info", timeout=2)
                self.assertEqual(error.exception.code, 502)
        finally:
            upstream.shutdown()
            upstream.server_close()
            thread.join(timeout=2)

    def test_gateway_validates_ports_and_limits(self) -> None:
        with self.assertRaisesRegex(ValueError, "guest_port"):
            make_gateway(0, 0)
        with self.assertRaisesRegex(ValueError, "port"):
            make_gateway(-1, 8080)
        with self.assertRaisesRegex(ValueError, "timeout"):
            make_gateway(0, 8080, timeout_seconds=0)
        with self.assertRaisesRegex(ValueError, "max_response"):
            make_gateway(0, 8080, max_response_bytes=0)
