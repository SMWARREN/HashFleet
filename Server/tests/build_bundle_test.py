#!/usr/bin/env python3
"""Offline packaging guards. No deployment, application launch, or network access."""
import importlib.util
import os
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("build_bundle", ROOT / "Server/tools/build_bundle.py")
PACK = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PACK)


class BundleAssetTests(unittest.TestCase):
    def test_hash_name_boundaries_and_hyphens(self):
        cases = {
            "app-12345678.js": True, "app-12345678.css": True,
            "app-1234567.js": False, "-12345678.js": False,
            "--12345678.js": True, "app-1234567-1.js": True,
            "app-abcdefgh.CSS": False, "app-abcdefgh.js\n": False,
            "app/inner-abcdefgh.js": False, "app-abcdefgh.map": False,
            "a\u00e9-abcdefgh.js": False, "a-abcdefgh.js.js": False,
        }
        for name, expected in cases.items():
            with self.subTest(name=name):
                self.assertEqual(PACK.hashed_asset(name), expected)

    def test_long_invalid_name_remains_rejected(self):
        self.assertFalse(PACK.hashed_asset("a-" * 100_000 + "!" + ".js"))

    def test_asset_paths_stay_constrained(self):
        for path in ("assets/app-12345678.js", "images/demo.webp", "favicon.png"):
            with self.subTest(path=path):
                self.assertTrue(PACK.allowed_asset(path))
        for path in ("../assets/app-12345678.js", "assets//app-12345678.js",
                     "assets/./app-12345678.js", "assets/plain.js",
                     "assets/nested/app-12345678.js", "images/../demo.webp"):
            with self.subTest(path=path):
                self.assertFalse(PACK.allowed_asset(path))

    def test_copy_skips_index_and_host_configuration(self):
        scratch = Path(os.environ.get("JCODE_SCRATCH_DIR", Path.home() / ".jcode/scratch"))
        with tempfile.TemporaryDirectory(dir=scratch) as temporary:
            root = Path(temporary)
            dist = root / "dist"
            dist.mkdir()
            (dist / "index.html").write_text("entry")
            (dist / ".htaccess").write_text("untrusted build configuration")
            (dist / "assets").mkdir()
            asset = dist / "assets/app-12345678.js"
            asset.write_bytes(b"verified artifact")
            manifest = {}
            PACK.copy_website_assets(dist, root / "bundle", manifest)
            self.assertEqual(set(manifest), {"web/assets/app-12345678.js"})
            self.assertEqual((root / "bundle/web/assets/app-12345678.js").read_bytes(), asset.read_bytes())

    def test_copy_rejects_symlink_and_unapproved_file(self):
        scratch = Path(os.environ.get("JCODE_SCRATCH_DIR", Path.home() / ".jcode/scratch"))
        for symlink in (False, True):
            with self.subTest(symlink=symlink), tempfile.TemporaryDirectory(dir=scratch) as temporary:
                root = Path(temporary)
                dist = root / "dist"
                dist.mkdir()
                source = dist / "unapproved.txt"
                if symlink:
                    source.symlink_to(root / "missing-target")
                else:
                    source.write_text("not approved")
                manifest = {}
                with self.assertRaises(ValueError):
                    PACK.copy_website_assets(dist, root / "bundle", manifest)
                self.assertEqual(manifest, {})


if __name__ == "__main__":
    unittest.main()
