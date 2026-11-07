#!/usr/bin/env python3
"""Read-only HTTPS acceptance for the original site and metadata-only API. Never enrolls against production."""
from __future__ import annotations

import argparse
import json
import re
import ssl
import urllib.error
import urllib.request
from urllib.parse import urlparse

DEFAULT_BASE = "https://hashfleet.app"
CHECKS = 0
HASHED_ASSET = re.compile(r"^/assets/[A-Za-z0-9_-]+-[A-Za-z0-9_-]{8,}\.(?:js|css)$")


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


def client():
    return urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect(),
        urllib.request.HTTPSHandler(context=ssl.create_default_context()))


def request(opener, base, path, maximum_bytes=131072):
    response = opener.open(urllib.request.Request(base + path, headers={
        "Accept": "application/json,text/html,*/*", "User-Agent": "HashFleet-Deployment-Check/2.0"}), timeout=15)
    with response:
        raw = response.read(maximum_bytes + 1)
        if len(raw) > maximum_bytes:
            raise RuntimeError("Deployment check response exceeded its bound.")
        response_headers = {}
        for key in response.headers.keys():
            values = response.headers.get_all(key) or []
            response_headers[key.lower()] = ", ".join(values)
        return response.status, response_headers, raw


def check(condition, name):
    global CHECKS
    if not condition:
        raise RuntimeError("Deployment check failed: " + name)
    CHECKS += 1


def no_store(headers, name):
    directives = {part.strip().lower() for part in headers.get("cache-control", "").split(",")}
    check("no-store" in directives, name + " Cache-Control no-store")
    check(not any(item.startswith("max-age") or item.startswith("s-maxage") for item in directives),
          name + " has no conflicting freshness lifetime")


def main(base):
    parsed = urlparse(base)
    if (parsed.scheme != "https" or not parsed.netloc or parsed.path not in ("", "/")
            or parsed.username is not None or parsed.password is not None or parsed.query or parsed.fragment):
        raise ValueError("Use an HTTPS origin without path, query, or fragment.")
    opener = client()
    status, headers, body = request(opener, base, "/")
    html = body.decode("utf-8", "replace")
    check(status == 200 and "Hash Fleet | Your hash. Your hardware." in html, "original website homepage")
    check("Your fleet." not in html and "Connect securely" not in html, "no replacement notification dashboard")
    no_store(headers, "homepage")
    for key, required in [("content-security-policy", "style-src 'self' 'unsafe-inline'"),
                          ("referrer-policy", "no-referrer"), ("x-content-type-options", "nosniff")]:
        check(required in headers.get(key, ""), "website security header " + key)
    check("access-control-allow-origin" not in headers, "no public CORS")
    paths = re.findall(r'(?:src|href)="([^\"]+)"', html)
    assets = [path for path in paths if path.startswith("/assets/")]
    check(any(path.endswith(".js") and HASHED_ASSET.fullmatch(path) for path in assets), "approved hashed JS asset referenced")
    check(any(path.endswith(".css") and HASHED_ASSET.fullmatch(path) for path in assets), "approved hashed CSS asset referenced")
    for path in assets:
        check(HASHED_ASSET.fullmatch(path) is not None, "asset path is exact hashed bundle name")
        # Static compiled JS is larger than the API's 128 KiB contract. It has its own
        # bounded 1 MiB ceiling, not a relaxed API response limit.
        asset_status, asset_headers, _ = request(opener, base, path, maximum_bytes=1048576)
        check(asset_status == 200, "original website asset served: " + path)
        no_store(asset_headers, "website asset " + path)
    retired_status, _, retired = request(opener, base, "/app.js")
    check(retired_status == 200 and b"Retired" in retired and b"fetch(" not in retired,
          "old browser dashboard script is inert")
    companion_status, _, companion = request(opener, base, "/companion/")
    check(companion_status == 200 and b"no separate companion" in companion,
          "old companion page explains its retirement")
    try:
        status, api_headers, raw = request(opener, base, "/api/v1.php?action=health")
    except urllib.error.HTTPError as error:
        status, api_headers, raw = error.code, {key.lower(): value for key, value in error.headers.items()}, error.read(131073)
    check(status == 200, "public API health")
    no_store(api_headers, "API health")
    health = json.loads(raw)
    check(health.get("ok") is True and health.get("mode") == "device_check_v1", "metadata-only API wire mode")
    check(isinstance(health.get("provider_ready"), bool), "provider readiness is explicit metadata")
    # Never enroll or write to the public deployment. These read-only probes only assert that
    # private endpoints reject unauthenticated access and deprecated write routes are absent.
    for action in ("preferences", "status"):
        try:
            result, _, _ = request(opener, base, "/api/v1.php?action=" + action)
        except urllib.error.HTTPError as error:
            result = error.code
        check(result in (400, 401), "private " + action + " requires credentials")
    for action in ("telemetry", "relay"):
        try:
            result, _, _ = request(opener, base, "/api/v1.php?action=" + action)
        except urllib.error.HTTPError as error:
            result = error.code
        check(result == 404, "deprecated write action rejected: " + action)
    for path in ("/.htaccess", "/private/config.php", "/hashfleet-private/config.php", "/hashfleet.sqlite", "/api/",
                 "/companion/hashfleet_relay.py"):
        try:
            result, _, _ = request(opener, base, path)
        except urllib.error.HTTPError as error:
            result = error.code
        check(result in (403, 404), "private or index path not public: " + path)
    print(f"PASS: {CHECKS} read-only HTTPS checks against {parsed.netloc}. No enrollment, private writes, or APNs sends.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", default=DEFAULT_BASE, help="HTTPS origin to inspect; read-only only")
    main(parser.parse_args().base.rstrip("/"))
