#!/usr/bin/env python3
"""Build a constrained hosting bundle from the approved Vite production artifact."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import tarfile

ROOT = Path(__file__).resolve().parents[2]
STATIC_FILES = {
    "web/app.js": "Server/public/app.js",
    "web/style.css": "Server/public/style.css",
    "web/.htaccess": "Server/public/.htaccess",
    "web/api/v1.php": "Server/public/api/v1.php",
    "web/companion/index.html": "Server/public/companion/index.html",
    "private/Service.php": "Server/private/Service.php",
    "private/APNs.php": "Server/private/APNs.php",
    "private/dispatch.php": "Server/private/dispatch.php",
    "private/config.example.php": "Server/private/config.example.php",
}
HASHED = re.compile(r"^[A-Za-z0-9_-]+-[A-Za-z0-9_-]{8,}\.(?:js|css)$")
MEDIA = re.compile(r"^(?:assets|images)/[A-Za-z0-9._/-]+\.(?:png|jpe?g|gif|svg|webp|avif|ico|woff2?)$")
ROOT_ASSETS = {"_headers", "apple-touch-icon.png", "favicon.png", "robots.txt", "sitemap.xml", "social-card.png"}


def allowed_asset(relative: str) -> bool:
    if any(part in ("", ".", "..") for part in relative.split("/")):
        return False
    return relative in ROOT_ASSETS or bool(MEDIA.fullmatch(relative)) or (
        relative.startswith("assets/") and "/" not in relative[7:] and bool(HASHED.fullmatch(relative[7:])))


def safe_copy(source: Path, target: Path) -> str:
    if source.is_symlink() or not source.is_file():
        raise ValueError(f"Missing or unsafe bundle source: {source}")
    data = source.read_bytes()
    target.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    target.write_bytes(data)
    target.chmod(0o600)
    return hashlib.sha256(data).hexdigest()


def build(output: Path) -> Path:
    dist = ROOT / "website/dist"
    if dist.is_symlink() or not dist.is_dir() or (dist / "index.html").is_symlink() or not (dist / "index.html").is_file():
        raise ValueError("Build website/ first; a safe website/dist/index.html is required.")
    output.mkdir(parents=True, exist_ok=True, mode=0o700)
    bundle = output / "bundle"
    if bundle.exists():
        raise ValueError("Use a fresh output directory. Existing bundles are never replaced.")
    bundle.mkdir(mode=0o700)
    manifest: dict[str, str] = {}
    manifest["web/index.html"] = safe_copy(dist / "index.html", bundle / "web/index.html")
    for source in sorted(dist.rglob("*")):
        if source.is_symlink():
            raise ValueError(f"Symlink in website build: {source}")
        if source.is_dir():
            continue
        relative = source.relative_to(dist).as_posix()
        if relative == "index.html":
            continue
        if relative == ".htaccess":
            continue
        if not allowed_asset(relative):
            raise ValueError(f"Unapproved website asset path: {relative}")
        if relative.startswith("assets/") and source.suffix in (".js", ".css") and not HASHED.fullmatch(source.name):
            raise ValueError(f"Unhashed production script/style is not permitted: {relative}")
        if relative.startswith("assets/") and (".." in Path(relative).parts or relative.startswith("assets//")):
            raise ValueError(f"Unsafe website asset path: {relative}")
        manifest["web/" + relative] = safe_copy(source, bundle / "web" / relative)
    assets = [Path(path).name for path in manifest if path.startswith("web/assets/") and Path(path).suffix in (".js", ".css")]
    if not any(name.endswith(".js") and HASHED.fullmatch(name) for name in assets) or not any(name.endswith(".css") and HASHED.fullmatch(name) for name in assets):
        raise ValueError("Vite production build must contain hashed JavaScript and CSS assets.")
    for relative, source in STATIC_FILES.items():
        manifest[relative] = safe_copy(ROOT / source, bundle / relative)
    (bundle / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    shutil.copyfile(ROOT / "Server/tools/install.php", bundle / "install.php")
    archive = output / "hashfleet-hosting.tar.gz"
    with tarfile.open(archive, "w:gz") as stream:
        for path in sorted(bundle.rglob("*")):
            stream.add(path, arcname=path.relative_to(bundle), recursive=False)
    archive.chmod(0o600)
    print(json.dumps({"files": len(manifest), "assets": sorted(assets), "archive": str(archive)}, indent=2))
    return archive


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    build(parser.parse_args().output.resolve())
