#!/usr/bin/env python3
"""Record the actual CLI's network-free --demo screens for the website walkthrough."""
import errno
import fcntl
import hashlib
import json
import os
from pathlib import Path
import pty
import re
import select
import struct
import subprocess
import sys
import termios
import time

ROOT = Path(__file__).resolve().parents[2]
BINARY = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else ROOT / '.build/out/Products/Release/hashfleet'
OUT = ROOT / 'website/src/lib/cli-dashboard-captures.json'
NAMES = ['Gamma / desk', 'Gamma / studio', 'Naja Duo / rack', 'Naja Duo / spare']
COLUMNS, ROWS = 120, 34
ANSI = re.compile(r'\x1b\[[0-9;?]*[A-Za-z]')


class Capture:
    def __init__(self):
        self.master, self.slave = pty.openpty()
        fcntl.ioctl(self.slave, termios.TIOCSWINSZ, struct.pack('HHHH', ROWS, COLUMNS, 0, 0))
        env = {**os.environ, 'TERM': 'xterm-256color', 'COLORTERM': 'truecolor', 'LC_ALL': 'en_US.UTF-8'}
        env.pop('NO_COLOR', None)
        # --demo bypasses shared fleet storage, discovery and MinerAPIClient entirely.
        self.process = subprocess.Popen([str(BINARY), 'watch', '--demo', '--interval', '3600'],
                                        stdin=self.slave, stdout=self.slave, stderr=self.slave, env=env)
        self.output = b''

    def drain(self, duration=0.16):
        end = time.monotonic() + duration
        while time.monotonic() < end:
            if select.select([self.master], [], [], max(0, end - time.monotonic()))[0]:
                try:
                    self.output += os.read(self.master, 65536)
                except OSError as error:
                    if error.errno != errno.EIO:
                        raise
                    break

    def send(self, keys):
        os.write(self.master, keys)
        self.drain()

    def frame(self):
        self.drain(0.03)
        frames = self.output.split(b'\x1b[H')
        complete = [frame.split(b'\x1b[J')[0] for frame in frames[1:] if b'\x1b[J' in frame]
        if not complete:
            raise RuntimeError('No complete CLI frame')
        frame = complete[-1].decode().replace('\r', '')
        # Keep only SGR color/style codes. Cursor movement belongs to the terminal, not HTML.
        frame = ANSI.sub(lambda match: match[0] if match[0].endswith('m') else '', frame)
        return '\n'.join(line.rstrip(' ') for line in frame.splitlines())

    def close(self):
        self.process.send_signal(2)
        self.process.wait(timeout=3)
        os.close(self.master)
        os.close(self.slave)


def validate_frame(key, frame):
    plain = ANSI.sub('', frame)
    if len(plain.splitlines()) != ROWS:
        raise RuntimeError(f'Incomplete {key}')
    if key.startswith('settings:') and 'HASH FLEET / SETTINGS' not in plain:
        raise RuntimeError(f'Missing settings page: {key}')
    if key.startswith('details:') and 'DETAILS /' not in plain:
        raise RuntimeError(f'Missing details page: {key}')
    if key.startswith(('details:', 'settings:')) and NAMES[int(key.split(':')[1])] not in plain:
        raise RuntimeError(f'Wrong selected miner: {key}')
    if re.search(r'192\.168\.|127\.0\.0\.1|10\.\d+\.\d+\.', plain):
        raise RuntimeError(f'Unexpected non-demo address in {key}')


def intern_frames(frames):
    lines, line_ids, indexed = [], {}, {}
    for key, frame in frames.items():
        indexed[key] = []
        for line in frame.split('\n'):
            if line not in line_ids:
                line_ids[line] = len(lines)
                lines.append(line)
            indexed[key].append(line_ids[line])
    return lines, indexed


def capture_fleet_frames(capture, frames):
    for sort, order in [('name', [0, 1, 2, 3]), ('hashrate', [2, 0, 1, 3]), ('temperature', [0, 1, 2, 3])]:
        for paused in (False, True):
            capture.send(b'[[[[')
            for position, miner in enumerate(order):
                if position:
                    capture.send(b']')
                frames[f'fleet:{sort}:{int(paused)}:{miner}'] = capture.frame()
            capture.send(b' ')
        capture.send(b's')


def capture_miner_frames(capture, frames):
    capture.send(b'[[[[')
    for miner in range(4):
        for section in range(1, 5):
            capture.send(str(section).encode())
            frames[f'details:{miner}:{section}'] = capture.frame()
        capture.send(b'b')
        capture.send(b'e')
        for category in range(1, 6):
            capture.send(str(category).encode())
            frames[f'settings:{miner}:{category}'] = capture.frame()
        capture.send(b'b')
        capture.send(b']')


def main():
    capture = Capture()
    frames = {}
    try:
        for _ in range(30):
            capture.drain(0.1)
            if b'Naja Duo / spare' in capture.output:
                break
        else:
            raise RuntimeError('Demo did not load')
        capture_fleet_frames(capture, frames)
        capture_miner_frames(capture, frames)
        capture.send(b'l')
        frames['logo'] = capture.frame()
        for key, frame in frames.items():
            validate_frame(key, frame)
        # Intern repeated lines without altering a single character or ANSI style.
        lines, indexed = intern_frames(frames)
        OUT.write_text(json.dumps({
            'source': 'Actual hashfleet watch --demo --interval 3600 output; no network or configured fleet access.',
            'binarySHA256': hashlib.sha256(BINARY.read_bytes()).hexdigest(),
            'normalization': 'Cursor-control sequences removed; original SGR colors, spacing, sample readings and captured ages retained. Settings use native read-only demo mode.',
            'columns': COLUMNS - 1, 'rows': ROWS, 'miners': NAMES, 'lines': lines, 'frames': indexed,
        }, indent=2, ensure_ascii=False) + '\n')
        print(f'Captured {len(frames)} actual CLI screens to {OUT.relative_to(ROOT)}')
    finally:
        capture.close()


if __name__ == '__main__':
    main()
