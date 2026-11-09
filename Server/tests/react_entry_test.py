#!/usr/bin/env python3
"""Real loopback Apache: inherited error documents, React routing and denials.

The fixture removes only the unchanged public HTTPS redirect because it binds
HTTP to loopback. Production TLS is verified separately by live acceptance.
No actual API code, configuration, database or miner endpoint is loaded.
"""
from __future__ import annotations

import argparse
import grp
import http.client
import os
from pathlib import Path
import pwd
import re
import shutil
import signal
import socket
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]
HTTPD = os.environ.get('HASHFLEET_TEST_HTTPD', '/usr/sbin/httpd')
MODULES = Path(os.environ.get('HASHFLEET_TEST_APACHE_MODULES', '/usr/libexec/apache2'))
HTTPS_BLOCK = '''<IfModule mod_rewrite.c>
  RewriteEngine On
  RewriteCond %{HTTPS} !=on
  RewriteRule ^ https://hashfleet.app%{REQUEST_URI} [R=308,L]
</IfModule>
'''
REGION = re.compile(r'# BEGIN HASHFLEET REACT ENTRY\n[\s\S]*?# END HASHFLEET REACT ENTRY\n')


def free_port():
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        return sock.getsockname()[1]


class Fixture:
    def __init__(self, port=None):
        if port:
            with socket.socket() as probe:
                probe.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                probe.bind(('127.0.0.1', port))
        scratch = Path(os.environ.get('JCODE_SCRATCH_DIR', Path.home() / '.jcode/scratch'))
        scratch.mkdir(parents=True, exist_ok=True)
        self.temporary = tempfile.TemporaryDirectory(prefix='hashfleet-react-entry-', dir=scratch)
        self.root = Path(self.temporary.name)
        self.port = port or free_port()
        self.previous_port = free_port()
        source = (ROOT / 'Server/public/.htaccess').read_text()
        assert source.count(HTTPS_BLOCK) == 1
        region = REGION.findall(source)
        assert len(region) == 1
        assert region == REGION.findall((ROOT / 'website/public/.htaccess').read_text())
        self.expected_headers = {name.lower(): value for name, value in re.findall(
            r'^  Header always set ([A-Za-z-]+) "([^"]+)"$', source, re.MULTILINE)}
        assert len(self.expected_headers) == 5
        fixture_policy = source.replace(HTTPS_BLOCK, '')
        for name, policy in [('site', fixture_policy), ('previous', REGION.sub('', fixture_policy))]:
            site = self.root / name
            shutil.copytree(ROOT / 'website/dist', site)
            (site / '.htaccess').write_text(policy)
            (site / 'api').mkdir(exist_ok=True)
            (site / 'api/fixture.json').write_text('{"fixture":true}')
            (site / '.env.local').write_text('synthetic-private-marker')
            (site / '.git').mkdir()
            (site / '.git/config').write_text('synthetic-private-marker')
        self.index = (self.root / 'site/index.html').read_bytes()
        modules = ('mpm_prefork', 'unixd', 'authz_core', 'headers', 'dir', 'mime', 'alias', 'autoindex', 'rewrite')
        for module in modules:
            if not (MODULES / f'mod_{module}.so').is_file():
                self.temporary.cleanup()
                raise unittest.SkipTest('Apache modules unavailable')
        loads = '\n'.join(f'LoadModule {name}_module "{MODULES}/mod_{name}.so"' for name in modules)
        user = pwd.getpwuid(os.getuid()).pw_name
        group = grp.getgrgid(os.getgid()).gr_name
        config = self.root / 'httpd.conf'
        config.write_text(f'''ServerRoot "{self.root}"
Listen 127.0.0.1:{self.port}
Listen 127.0.0.1:{self.previous_port}
ServerName 127.0.0.1
PidFile "{self.root}/httpd.pid"
DefaultRuntimeDir "{self.root}"
{loads}
User {user}
Group {group}
ErrorLog "{self.root}/error.log"
LogLevel warn
TypesConfig /etc/apache2/mime.types
ServerTokens Prod
ServerSignature Off
Header always set X-Frame-Options "SAMEORIGIN"
Header always set X-Content-Type-Options "nosniff"
ErrorDocument 403 /403.shtml
ErrorDocument 404 /404.shtml
<Directory />
  AllowOverride None
  Require all denied
</Directory>
<Directory "{self.root}">
  Options FollowSymLinks
  AllowOverride All
  Require all granted
</Directory>
<VirtualHost 127.0.0.1:{self.port}>
  DocumentRoot "{self.root}/site"
  RedirectMatch 403 "^/(\\.env(?:\\.|$)|\\.git(?:/|$))"
</VirtualHost>
<VirtualHost 127.0.0.1:{self.previous_port}>
  DocumentRoot "{self.root}/previous"
  RedirectMatch 403 "^/(\\.env(?:\\.|$)|\\.git(?:/|$))"
</VirtualHost>
''')
        self.log = (self.root / 'process.log').open('w')
        syntax = subprocess.run([HTTPD, '-t', '-f', str(config)], capture_output=True, text=True)
        if syntax.returncode:
            self.log.close()
            self.temporary.cleanup()
            raise AssertionError(syntax.stderr)
        self.server = subprocess.Popen([HTTPD, '-f', str(config), '-DFOREGROUND'],
                                       stdout=self.log, stderr=self.log, start_new_session=True)
        for _ in range(60):
            if self.server.poll() is not None:
                error = (self.root / 'process.log').read_text()
                self.close()
                raise AssertionError(error)
            try:
                status, _, body = self.request('/')
                if status != 200 or body != self.index:
                    self.close()
                    raise AssertionError('Loopback port served a different artifact')
                return
            except OSError:
                time.sleep(0.05)
        self.close()
        raise AssertionError('Loopback Apache did not start')

    def close(self):
        if self.server.poll() is None:
            self.server.terminate()
            try:
                self.server.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.server.kill()
                self.server.wait(timeout=5)
        self.log.close()
        self.temporary.cleanup()

    def request(self, route, method='GET', previous=False):
        connection = http.client.HTTPConnection('127.0.0.1', self.previous_port if previous else self.port, timeout=3)
        try:
            connection.request(method, route)
            response = connection.getresponse()
            return response.status, response.headers, response.read()
        finally:
            connection.close()


class ReactEntryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.fixture = Fixture()
        cls.addClassCleanup(cls.fixture.close)

    def test_source_regions_match_and_https_redirect_is_preserved(self):
        source = (ROOT / 'Server/public/.htaccess').read_text()
        self.assertEqual(source.count(HTTPS_BLOCK), 1)
        self.assertEqual(REGION.findall(source), REGION.findall((ROOT / 'website/public/.htaccess').read_text()))

    def test_public_routes_share_the_exact_react_entry(self):
        for route in ('/', '/demo', '/demo/', '/demo/mac', '/demo/iphone/', '/demo/terminal?view=sample'):
            with self.subTest(route=route):
                status, headers, body = self.fixture.request(route)
                self.assertEqual(status, 200)
                self.assertEqual(body, self.fixture.index)
                self.assertNotIn('Location', headers)

    def test_inherited_early_denials_gain_headers_without_losing_403(self):
        for route in ('/.env.local', '/.git/config'):
            with self.subTest(route=route):
                old_status, old_headers, old_body = self.fixture.request(route, previous=True)
                self.assertEqual(old_status, 403)
                self.assertEqual(old_headers.get('X-Frame-Options'), 'SAMEORIGIN')
                self.assertIsNone(old_headers.get('Content-Security-Policy'))
                self.assertNotEqual(old_body, self.fixture.index)
                status, headers, body = self.fixture.request(route)
                self.assertEqual(status, 403)
                self.assertEqual(body, self.fixture.index)
                for name, expected in self.fixture.expected_headers.items():
                    self.assertEqual(headers.get_all(name), [expected], name)
                self.assertNotIn(b'synthetic-private-marker', body)

    def test_unknown_page_keeps_404_and_uses_react(self):
        for route in ('/missing-native-parity-page', '/demo/unknown', '/demo/mac/extra'):
            with self.subTest(route=route):
                status, _, body = self.fixture.request(route)
                self.assertEqual(status, 404)
                self.assertEqual(body, self.fixture.index)

    def test_missing_assets_apis_and_private_paths_do_not_become_spa_pages(self):
        for route in ('/assets/missing.js', '/images/missing.webp', '/api/no-such-route',
                      '/hashfleet-private/config.php', '/src/App.tsx'):
            with self.subTest(route=route):
                status, _, body = self.fixture.request(route)
                self.assertEqual(status, 404)
                self.assertNotEqual(body, self.fixture.index)
        status, _, body = self.fixture.request('/api/fixture.json')
        self.assertEqual(status, 200)
        self.assertEqual(body, b'{"fixture":true}')

    def test_existing_asset_bytes_and_directory_denials_are_preserved(self):
        relative = next((self.fixture.root / 'site/assets').glob('*.js')).relative_to(self.fixture.root / 'site')
        status, _, body = self.fixture.request('/' + relative.as_posix())
        self.assertEqual(status, 200)
        self.assertEqual(body, (self.fixture.root / 'site' / relative).read_bytes())
        for route in ('/assets/', '/images/'):
            with self.subTest(route=route):
                status, _, body = self.fixture.request(route)
                self.assertEqual(status, 403)
                self.assertNotEqual(body, self.fixture.index)

    def test_head_and_non_get_page_requests_keep_their_status(self):
        for route, expected in (('/demo/iphone', 200), ('/.env.local', 403), ('/missing', 404)):
            with self.subTest(route=route):
                status, _, body = self.fixture.request(route, 'HEAD')
                self.assertEqual(status, expected)
                self.assertEqual(body, b'')
        status, _, _ = self.fixture.request('/demo/iphone', 'POST')
        self.assertEqual(status, 404)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--serve', action='store_true', help='Serve isolated browser fixtures on loopback 4175 until stopped')
    args, remaining = parser.parse_known_args()
    if args.serve:
        fixture = Fixture(port=4175)
        print(f'ORIGIN=http://127.0.0.1:{fixture.port}', flush=True)
        signal.signal(signal.SIGTERM, lambda *_: exit(0))
        try:
            signal.pause()
        finally:
            fixture.close()
    else:
        unittest.main(argv=[__file__, *remaining], verbosity=2)
