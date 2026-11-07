#!/usr/bin/env python3
"""Publish reviewed native demo captures losslessly, with pixel-identity receipts.

This tool does not launch apps, connect to devices, or edit the native product.
Pass the directory of reviewed PNG screenshots produced by the actual apps.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
NAMES = (
    "mac-overview", "mac-workshop", "mac-office", "mac-supra", "mac-network",
    "mac-energy", "mac-achievements", "mac-reports", "mac-backup", "mac-settings", "mac-about",
    "ios-fleet", "ios-current", "ios-settings", "ios-fleet-settings", "ios-miners", "ios-office", "ios-about",
)
VERSION = "20261025"


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def pixels(magick: str, path: Path) -> bytes:
    return subprocess.check_output([magick, str(path), "-alpha", "on", "-depth", "8", "RGBA:-"])


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--verify", action="store_true", help="Verify existing captures without rewriting them")
    args = parser.parse_args()
    magick = shutil.which("magick") or "/opt/homebrew/bin/magick"
    cwebp = shutil.which("cwebp") or "/opt/homebrew/bin/cwebp"
    output = ROOT / "public/images/native"
    manifest_path = ROOT / "src/lib/native-captures.json"
    existing = json.loads(manifest_path.read_text()) if args.verify else None
    output.mkdir(parents=True, exist_ok=True)
    captures = []
    for name in NAMES:
        source = args.source / f"{name}.png"
        if not source.is_file() or source.is_symlink():
            raise ValueError(f"Missing reviewed screenshot: {source.name}")
        target = output / f"{name}-{VERSION}.webp"
        if not args.verify:
            subprocess.run([cwebp, "-quiet", "-lossless", "-exact", "-z", "9", str(source), "-o", str(target)], check=True)
        source_pixels = pixels(magick, source)
        if source_pixels != pixels(magick, target):
            raise ValueError(f"Decoded native pixels changed: {name}")
        dimensions = subprocess.check_output([magick, "identify", "-format", "%w %h", str(target)], text=True).split()
        capture = {
            "id": name,
            "src": f"/images/native/{target.name}",
            "width": int(dimensions[0]),
            "height": int(dimensions[1]),
            "sourceSha256": digest(source.read_bytes()),
            "sha256": digest(target.read_bytes()),
            "rgbaSha256": digest(source_pixels),
            "bytes": target.stat().st_size,
        }
        if args.verify and capture not in existing["captures"]:
            raise ValueError(f"Capture receipt changed: {name}")
        captures.append(capture)
    manifest = {
        "capturedAt": "2026-10-25",
        "mode": "Actual current native apps, isolated --ui-testing --demo sample data",
        "encoding": "Lossless WebP. Decoded 8-bit RGBA bytes equal the original native PNG capture.",
        "captures": captures,
    }
    if not args.verify:
        manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps({"verified": len(captures), "bytes": sum(x["bytes"] for x in captures), "pixelIdentity": True}))


if __name__ == "__main__":
    main()
