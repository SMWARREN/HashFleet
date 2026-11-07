#!/usr/bin/env python3
"""Copy or verify original native PNGs. No generated/repainted app imagery."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import struct

ROOT = Path(__file__).resolve().parents[1]
SOURCES = {
    'watch-fleet': '25841F69-45BC-4010-A1FF-C0D7D8B64942.png',
    'watch-miner': '49E589CD-EAEA-4547-9358-901858745AC8.png',
    'watch-status': '1D80807F-A78A-4236-9191-C715D384502B.png',
    'watch-discovery': 'EE2DAA4F-4824-4BA9-BF67-53CDF11CB006.png',
    'watch-add': '242E3D7F-553F-4237-BA42-DDF1B4C954F6.png',
}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--source', required=True, type=Path)
parser.add_argument('--verify', action='store_true')
args = parser.parse_args()
rows = []
for capture_id, filename in SOURCES.items():
    source = args.source / filename
    data = source.read_bytes()
    assert data[:8] == b'\x89PNG\r\n\x1a\n'
    width, height = struct.unpack('>II', data[16:24])
    assert (width, height) == (368, 448)
    target = ROOT / 'public/images/watch' / (capture_id + '-20261104.png')
    if not args.verify:
        target.parent.mkdir(parents=True, exist_ok=True)
        if target.exists():
            assert target.read_bytes() == data, 'Refuse to replace different existing image'
        else:
            shutil.copyfile(source, target)
    assert target.read_bytes() == data, capture_id
    rows.append({'id': capture_id, 'src': '/' + str(target.relative_to(ROOT / 'public')), 'width': width, 'height': height, 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest(), 'sourceSha256': hashlib.sha256(data).hexdigest()})
manifest = {'capturedAt': '2026-11-04', 'sourceRevision': 'a10fec115ba3f74ceed100f023eb235d4a009cd1', 'provenance': 'Unmodified PNG attachments from the native HashFleetWatchUITests demo and independent-setup tests. Fictional readings. No generated app screens.', 'captures': rows}
destination = ROOT / 'src/lib/watch-captures.json'
if args.verify:
    assert json.loads(destination.read_text()) == manifest
else:
    destination.write_text(json.dumps(manifest, indent=2) + '\n')
print(json.dumps({'native_captures': len(rows), 'all_source_and_public_png_bytes_identical': True, 'total_bytes': sum(row['bytes'] for row in rows)}))
