#!/usr/bin/env python3
"""Exercise site versus virtual-host headers on isolated loopback Apache.

The synthetic early denial models the observed configuration boundary, not
the unproven identity of the production blocking module. No production host,
miner, notification API, or Apache system configuration is contacted/changed.
"""
from __future__ import annotations

import grp
import http.client
import os
from pathlib import Path
import pwd
import re
import shutil
import socket
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]
POLICY = ROOT / "Server/apache/hashfleet-security-headers.conf"
SITE_POLICY = ROOT / "Server/public/.htaccess"
HTTPD = os.environ.get("HASHFLEET_TEST_HTTPD", shutil.which("httpd") or "/usr/sbin/httpd")
MODULES = Path(os.environ.get("HASHFLEET_TEST_APACHE_MODULES", "/usr/libexec/apache2"))
REQUIRED_MODULES = (
    "mpm_prefork", "unixd", "authz_core", "headers", "dir", "alias", "autoindex",
)


def headers_in(path: Path) -> dict[str, str]:
    return {name.lower(): value for name, value in re.findall(
        r'^Header always set ([A-Za-z-]+) "([^"]+)"$', path.read_text(), re.MULTILINE)}


class ApacheHeaderTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not Path(HTTPD).is_file() or any(
                not (MODULES / f"mod_{name}.so").is_file() for name in REQUIRED_MODULES):
            raise unittest.SkipTest("A local Apache and its module directory are required")
        scratch = Path(os.environ.get("JCODE_SCRATCH_DIR", Path.home() / ".jcode/scratch"))
        scratch.mkdir(parents=True, exist_ok=True)
        cls.temporary = tempfile.TemporaryDirectory(prefix="hashfleet-header-test-", dir=scratch)
        cls.addClassCleanup(cls.temporary.cleanup)
        cls.root = Path(cls.temporary.name)
        site = cls.root / "site"
        site.mkdir()
        (site / ".htaccess").write_bytes(SITE_POLICY.read_bytes())
        (site / "index.html").write_text("Hash Fleet loopback fixture")
        (site / "assets").mkdir()
        cls.private_marker = "synthetic-private-data-must-not-be-served"
        (site / ".env.local").write_text(cls.private_marker)
        (site / ".git").mkdir()
        (site / ".git/config").write_text(cls.private_marker)
        (site / "fixture.sqlite").write_text(cls.private_marker)
        with socket.socket() as reservation:
            reservation.bind(("127.0.0.1", 0))
            cls.port = reservation.getsockname()[1]
        username = pwd.getpwuid(os.getuid()).pw_name
        group = grp.getgrgid(os.getgid()).gr_name
        loads = "\n".join(f'LoadModule {name}_module "{MODULES}/mod_{name}.so"'
                          for name in REQUIRED_MODULES)
        # mod_alias at vhost scope rejects these before the directory walk.
        # mod_rewrite is deliberately absent, so a loopback HTTP fixture does
        # not follow the unchanged production HTTPS redirect to a public host.
        early_deny = 'RedirectMatch 403 "^/(\\.env(?:\\.|$)|\\.git(?:/|$))"'
        config = cls.root / "httpd.conf"
        config.write_text(f'''ServerRoot "{cls.root}"
Listen 127.0.0.1:{cls.port}
ServerName 127.0.0.1
PidFile "{cls.root}/httpd.pid"
DefaultRuntimeDir "{cls.root}"
{loads}
User {username}
Group {group}
ErrorLog "{cls.root}/error.log"
LogLevel warn
ServerTokens Prod
ServerSignature Off
DocumentRoot "{site}"
Header always set X-Frame-Options "SAMEORIGIN"
Header always set X-Content-Type-Options "nosniff"
<Directory />
  AllowOverride None
  Require all denied
</Directory>
<Directory "{site}">
  Options FollowSymLinks
  AllowOverride All
  Require all granted
</Directory>
<VirtualHost 127.0.0.1:{cls.port}>
  ServerName site-only.test
  {early_deny}
</VirtualHost>
<VirtualHost 127.0.0.1:{cls.port}>
  ServerName vhost-policy.test
  {early_deny}
  Include "{POLICY}"
</VirtualHost>
''')
        syntax = subprocess.run([HTTPD, "-t", "-f", str(config)], capture_output=True, text=True)
        if syntax.returncode:
            raise AssertionError(syntax.stderr)
        cls.log = (cls.root / "process.log").open("w")
        cls.addClassCleanup(cls.log.close)
        cls.server = subprocess.Popen([HTTPD, "-f", str(config), "-DFOREGROUND"],
                                      stdout=cls.log, stderr=cls.log, start_new_session=True)
        cls.addClassCleanup(cls.stop_server)
        for _ in range(60):
            if cls.server.poll() is not None:
                raise AssertionError((cls.root / "process.log").read_text())
            try:
                cls.request("site-only.test", "/")
                return
            except OSError:
                time.sleep(0.05)
        raise AssertionError("Isolated Apache did not become ready")

    @classmethod
    def stop_server(cls):
        if cls.server.poll() is None:
            cls.server.terminate()
            try:
                cls.server.wait(timeout=5)
            except subprocess.TimeoutExpired:
                cls.server.kill()
                cls.server.wait(timeout=5)

    @classmethod
    def request(cls, host: str, route: str, method: str = "GET"):
        connection = http.client.HTTPConnection("127.0.0.1", cls.port, timeout=3)
        try:
            connection.request(method, route, headers={"Host": host})
            response = connection.getresponse()
            return response.status, response.headers, response.read().decode("utf-8")
        finally:
            connection.close()

    def assert_policy(self, headers):
        for name, value in headers_in(POLICY).items():
            self.assertEqual(headers.get_all(name), [value], name)

    def test_handoff_matches_site_policy_without_changing_access_controls(self):
        expected = headers_in(POLICY)
        self.assertEqual(len(expected), 5)
        site = {name.lower(): value for name, value in re.findall(
            r'^  Header always set ([A-Za-z-]+) "([^"]+)"$',
            SITE_POLICY.read_text(), re.MULTILINE)}
        self.assertEqual(expected, site)
        for line in POLICY.read_text().splitlines():
            self.assertTrue(not line or line.startswith(("#", "Header onsuccess unset ", "Header always set ")), line)

    def test_site_rules_cover_ordinary_pages_and_errors(self):
        for route, status in (("/", 200), ("/.htaccess", 403), ("/missing", 404), ("/assets/", 403)):
            with self.subTest(route=route):
                actual, headers, body = self.request("site-only.test", route)
                self.assertEqual(actual, status)
                self.assert_policy(headers)
                self.assertNotIn(self.private_marker, body)

    def test_early_denials_bypass_site_headers(self):
        for route in ("/.env.local", "/.git/config"):
            with self.subTest(route=route):
                actual, headers, body = self.request("site-only.test", route)
                self.assertEqual(actual, 403)
                self.assertEqual(headers.get_all("x-frame-options"), ["SAMEORIGIN"])
                self.assertIsNone(headers.get("content-security-policy"))
                self.assertIsNone(headers.get("referrer-policy"))
                self.assertIsNone(headers.get("permissions-policy"))
                self.assertNotIn(self.private_marker, body)

    def test_virtual_host_policy_covers_early_and_site_denials(self):
        for route, status in (("/", 200), ("/.htaccess", 403), ("/.env.local", 403),
                              ("/.git/config", 403), ("/missing", 404), ("/assets/", 403),
                              ("/fixture.sqlite", 403)):
            with self.subTest(route=route):
                actual, headers, body = self.request("vhost-policy.test", route)
                self.assertEqual(actual, status)
                self.assert_policy(headers)
                self.assertNotIn(self.private_marker, body)

    def test_head_keeps_denial_status_and_one_value_per_header(self):
        for route in ("/.env.local", "/.git/config", "/fixture.sqlite"):
            with self.subTest(route=route):
                actual, headers, body = self.request("vhost-policy.test", route, "HEAD")
                self.assertEqual(actual, 403)
                self.assert_policy(headers)
                self.assertEqual(body, "")


if __name__ == "__main__":
    unittest.main(verbosity=2)
