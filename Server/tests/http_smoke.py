#!/usr/bin/env python3
"""Exercise the actual PHP HTTP entrypoint on loopback, with a temporary private database."""
import argparse
import base64
import http.client
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile
import time
import uuid


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--php', default='php')
    parser.add_argument('--scratch', required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    Path(args.scratch).mkdir(parents=True, exist_ok=True)
    checks = 0
    with tempfile.TemporaryDirectory(prefix='http-', dir=args.scratch) as temporary:
        private = Path(temporary)
        for name in ['APNs.php', 'Service.php']:
            shutil.copyfile(root / 'private' / name, private / name)
        def config(local):
            (private / 'config.php').write_text("<?php return ['database'=>__DIR__.'/fixture.sqlite','privacy_salt'=>'offline-test',"
                                               "'allow_local_http'=>" + ('true' if local else 'false') + "];")
        config(False)
        with socket.socket() as sock:
            sock.bind(('127.0.0.1', 0))
            port = sock.getsockname()[1]
        env = dict(os.environ, HASHFLEET_PRIVATE=str(private))
        with (private / 'http.log').open('w') as log:
            server = subprocess.Popen([args.php, '-S', f'127.0.0.1:{port}', '-t', str(root / 'public')], env=env, stdout=log, stderr=log)
            try:
                deadline = time.monotonic() + 8
                while True:
                    try:
                        with socket.create_connection(('127.0.0.1', port), timeout=.2):
                            break
                    except OSError:
                        if server.poll() is not None or time.monotonic() > deadline:
                            raise AssertionError('Local PHP fixture did not start')
                        time.sleep(.025)
                installation = str(uuid.uuid4())
                miner = str(uuid.uuid4())
                secret = base64.urlsafe_b64encode(os.urandom(32)).decode().rstrip('=')
                headers = {'Authorization': 'Bearer ' + secret, 'X-HashFleet-Installation': installation}
                def request(action, method='GET', body=None, auth=True, extra=None):
                    connection = http.client.HTTPConnection('127.0.0.1', port, timeout=5)
                    values = dict(headers) if auth else {}
                    values.update(extra or {})
                    if body is not None:
                        values.setdefault('Content-Type', 'application/json')
                        if not isinstance(body, str):
                            body = json.dumps(body, allow_nan=False)
                    connection.request(method, '/api/v1.php?action=' + action, body=body, headers=values)
                    response = connection.getresponse()
                    text = response.read(131073).decode()
                    assert 'hashfleet-private' not in text and str(private) not in text, 'Exception details escaped'
                    result = response.status, dict(response.getheaders()), json.loads(text)
                    connection.close()
                    return result
                def check(condition, description):
                    nonlocal checks
                    assert condition, description
                    checks += 1
                check(request('health', auth=False)[0] == 400, 'HTTP refused by default')
                check(request('health', auth=False, extra={'X-Forwarded-Proto': 'https'})[0] == 400, 'Spoofed proxy header ignored')
                config(True)
                code, response_headers, health = request('health', auth=False)
                check(code == 200 and health == {'ok': True, 'service': 'hashfleet-notifications',
                      'mode': 'device_check_v1', 'provider_ready': False}, 'Minimal health metadata with explicit loopback opt-in')
                check(response_headers['Cache-Control'] == 'no-store', 'Private responses never cached')
                check('Access-Control-Allow-Origin' not in response_headers, 'No wildcard CORS')
                check(request('status')[0] == 401, 'Unknown installation cannot read private status')
                registration = {'mode': 'device_check_v1', 'device_token': 'ab' * 32,
                                'environment': 'sandbox', 'miners': [{'id': miner}]}
                code, _, result = request('register', 'POST', registration)
                check(code == 200 and result['mode'] == 'device_check_v1' and result['settings']['enabled'] is False,
                      'Actual HTTP registration in explicit mode starts off')
                check(result['settings']['miners'] == [{'id': miner, 'enabled': True, 'interval_minutes': 60}],
                      'Registration stores only miner ID with hourly defaults')
                prefs = {'enabled': True, 'miners': [{'id': miner, 'enabled': True, 'interval_minutes': 180}]}
                code, _, result = request('preferences', 'PUT', prefs)
                check(code == 200 and result['settings']['enabled'] is True, 'Per-miner interval stored over HTTP')
                code, _, result = request('status')
                check(code == 200 and result['mode'] == 'device_check_v1' and result['schedules'][0]['id'] == miner,
                      'Status returns schedule metadata')
                check(not any(key in result for key in ['token', 'device_token', 'miners', 'readings']),
                      'Status exposes no APNs token or readings')
                check(request('telemetry', 'POST', {'miners': []})[0] == 404, 'Retired telemetry endpoint disabled')
                check(request('relay', 'POST', {})[0] == 404, 'Retired relay endpoint disabled')
                check(request('send', 'POST', {})[0] == 404, 'No public send endpoint')
                check(request('register', 'POST', {**registration, 'miners': [{'id': miner, 'name': 'not allowed'}]})[0] == 400,
                      'Miner names rejected at registration boundary')
                check(request('preferences', 'PUT', {'enabled': True, 'miners': [{'id': miner, 'enabled': True,
                      'interval_minutes': 180, 'name': 'not allowed'}]})[0] == 400, 'Extra preference fields denied')
                check(request('preferences', 'PUT', '[]')[0] == 400, 'JSON arrays rejected at HTTP boundary')
                check(request('preferences', 'PUT', '{bad')[0] == 400, 'Malformed JSON denied without exception details')
                check(request('register', 'POST', '{}', extra={'Content-Type': 'text/plain'})[0] == 415, 'JSON content type required')
                check(request('register', 'POST', 'x' * 131073)[0] == 413, 'HTTP body cap enforced')
                check(request('health&token=never-accepted', auth=False)[0] == 404, 'Query credentials not accepted')
                check(request('register', 'OPTIONS', auth=False)[0] == 405, 'No CORS mutation preflight support')
                check(request('register', 'POST', registration, extra={'Authorization': 'Bearer ' + base64.urlsafe_b64encode(os.urandom(32)).decode().rstrip('=')})[0] == 401,
                      'Wrong credential cannot overwrite known registration')
                check(request('register', 'DELETE')[0] == 200, 'Authorized HTTP deletion')
                check(request('status')[0] == 401, 'Deleted installation stays inaccessible')
            finally:
                server.terminate()
                server.wait(timeout=5)
    print(f'PASS: {checks} actual loopback HTTP checks. No external HTTP calls or miner access.')


if __name__ == '__main__':
    main()
