#!/usr/bin/env python3
"""Exercise artifact packaging and the real CLI installer against isolated local homes."""
from __future__ import annotations

import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("build_bundle", ROOT / "Server/tools/build_bundle.py")
PACK = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PACK)
PHP = os.environ.get("HASHFLEET_TEST_PHP", "/opt/homebrew/bin/php")
HASHED = re.compile(r"^[A-Za-z0-9_-]+-[A-Za-z0-9_-]{8,}\.(?:js|css)$")


class DeploymentTests(unittest.TestCase):
    def setUp(self):
        scratch = Path(os.environ.get("JCODE_SCRATCH_DIR", Path.home() / ".jcode/scratch"))
        scratch.mkdir(parents=True, exist_ok=True)
        self.temporary = tempfile.TemporaryDirectory(prefix="hashfleet-deploy-test-", dir=scratch)
        self.root = Path(self.temporary.name)
        self.home = self.root / "home"
        self.web = self.home / "hashfleet.app"
        self.web.mkdir(parents=True)
        (self.web / "index.html").write_text("old website placeholder")
        (self.web / "assets").mkdir()
        (self.web / "assets/old.js").write_text("old dashboard must not be referenced")
        (self.web / "unrelated.txt").write_text("keep this")
        (self.home / "mildfun.com").mkdir()
        (self.home / "mildfun.com/keep.txt").write_text("other site")
        PACK.build(self.root / "package")
        self.bundle = self.root / "package/bundle"
        self.manifest = json.loads((self.bundle / "manifest.json").read_text())

    def tearDown(self):
        self.temporary.cleanup()

    def install(self, success=True):
        result = subprocess.run([PHP, str(self.bundle / "install.php"), str(self.home)],
                                capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0 if success else 1, result.stderr)
        return json.loads(result.stdout) if success else result

    def test_manifest_is_original_build_with_exact_hashed_js_css(self):
        dist = ROOT / "website/dist"
        self.assertEqual((self.bundle / "web/index.html").read_bytes(), (dist / "index.html").read_bytes())
        assets = [key.removeprefix("web/") for key in self.manifest if key.startswith("web/assets/")]
        self.assertEqual(set(assets), {path.relative_to(dist).as_posix() for path in (dist / "assets").rglob("*") if path.is_file()})
        scripts = [Path(path).name for path in assets if path.endswith(".js")]
        styles = [Path(path).name for path in assets if path.endswith(".css")]
        self.assertTrue(scripts and all(HASHED.fullmatch(name) for name in scripts))
        self.assertTrue(styles and all(HASHED.fullmatch(name) for name in styles))
        self.assertIn("Retired", (self.bundle / "web/app.js").read_text())
        self.assertIn("Retired", (self.bundle / "web/style.css").read_text())
        self.assertNotIn("Connect securely", (self.bundle / "web/app.js").read_text())
        self.assertFalse(any(key.endswith("hashfleet_relay.py") for key in self.manifest))
        for key, digest in self.manifest.items():
            payload = (self.bundle / key).read_bytes()
            self.assertEqual(hashlib.sha256(payload).hexdigest(), digest)
        self.assertIn("Mac", (self.bundle / "web/index.html").read_text())
        self.assertIn("terminal", (self.bundle / "web/index.html").read_text())

    def test_install_backs_up_exact_files_and_preserves_unrelated_and_private_data(self):
        result = self.install()
        self.assertTrue(result["ok"])
        backup = Path(result["backup"])
        self.assertEqual((backup / "web/index.html").read_text(), "old website placeholder")
        self.assertEqual((self.web / "index.html").read_bytes(), (self.bundle / "web/index.html").read_bytes())
        self.assertEqual((self.web / "unrelated.txt").read_text(), "keep this")
        self.assertEqual((self.home / "mildfun.com/keep.txt").read_text(), "other site")
        self.assertEqual((self.web / "assets/old.js").read_text(), "old dashboard must not be referenced")
        config = self.home / "hashfleet-private/config.php"
        self.assertEqual(config.stat().st_mode & 0o777, 0o600)
        self.assertEqual(config.parent.stat().st_mode & 0o777, 0o700)
        self.assertIn("'key_file' => NULL", config.read_text())
        for key in self.manifest:
            if key.startswith("web/"):
                self.assertTrue((self.web / key.removeprefix("web/")).is_file(), key)
        self.assertEqual((self.web / "support/index.html").read_bytes(),
                         (ROOT / "website/dist/support/index.html").read_bytes())
        self.assertEqual((self.web / "llms.txt").read_bytes(),
                         (ROOT / "website/public/llms.txt").read_bytes())

    def test_repeat_deploy_preserves_private_configuration_and_database(self):
        self.install()
        config = self.home / "hashfleet-private/config.php"
        before = config.read_bytes()
        database = self.home / "hashfleet-private/hashfleet.sqlite"
        database.write_bytes(b"fixture database must survive")
        self.install()
        self.assertEqual(config.read_bytes(), before)
        self.assertEqual(database.read_bytes(), b"fixture database must survive")

    @unittest.skipIf(os.geteuid() == 0, "Permission-denial fixture must run as an unprivileged user")
    def test_mid_promotion_failure_restores_existing_bytes_modes_and_new_config(self):
        private = self.home / "hashfleet-private"
        private.mkdir(mode=0o700)
        service = private / "Service.php"
        service.write_text("original private service")
        service.chmod(0o600)
        old_script = self.web / "app.js"
        old_script.write_text("original script")
        old_script.chmod(0o640)
        # Preflight can inspect and back up this directory. Atomic file promotion
        # cannot write to it, after earlier private files and app.js were promoted.
        assets = self.web / "assets"
        assets.chmod(0o555)
        try:
            result = self.install(success=False)
        finally:
            assets.chmod(0o755)
        self.assertIn("rolled back", result.stderr)
        self.assertEqual(service.read_text(), "original private service")
        self.assertEqual(service.stat().st_mode & 0o777, 0o600)
        self.assertEqual(old_script.read_text(), "original script")
        self.assertEqual(old_script.stat().st_mode & 0o777, 0o640)
        self.assertFalse((private / "APNs.php").exists())
        self.assertFalse((private / "config.php").exists())
        self.assertEqual((self.web / "index.html").read_text(), "old website placeholder")
        self.assertEqual((self.web / "unrelated.txt").read_text(), "keep this")
        backups = list((private / "backups").iterdir())
        self.assertEqual(len(backups), 1)
        self.assertEqual((backups[0] / "private/Service.php").read_text(), "original private service")

    def test_tamper_is_rejected_before_web_changes(self):
        (self.bundle / "web/index.html").write_text("tampered")
        self.install(success=False)
        self.assertEqual((self.web / "index.html").read_text(), "old website placeholder")
        self.assertFalse((self.home / "hashfleet-private").exists())

    def test_arbitrary_script_path_is_rejected_before_web_changes(self):
        manifest = dict(self.manifest)
        manifest["web/notifications.js"] = "0" * 64
        (self.bundle / "web/notifications.js").write_text("not authorized")
        (self.bundle / "manifest.json").write_text(json.dumps(manifest))
        self.install(success=False)
        self.assertEqual((self.web / "index.html").read_text(), "old website placeholder")

    def test_symlink_destination_cannot_modify_another_site(self):
        (self.web / "api").symlink_to(self.home / "mildfun.com", target_is_directory=True)
        self.install(success=False)
        self.assertEqual((self.home / "mildfun.com/keep.txt").read_text(), "other site")
        self.assertEqual((self.web / "index.html").read_text(), "old website placeholder")

    def test_executable_or_unhashed_assets_are_rejected_before_changes(self):
        for relative in ("web/assets/leak.php", "web/images/private.p8", "web/assets/extra.js", "web/images/nested/route.php"):
            with self.subTest(relative=relative):
                payload = b"not an approved static asset"
                path = self.bundle / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(payload)
                manifest = dict(self.manifest)
                manifest[relative] = hashlib.sha256(payload).hexdigest()
                (self.bundle / "manifest.json").write_text(json.dumps(manifest))
                self.install(success=False)
                self.assertEqual((self.web / "index.html").read_text(), "old website placeholder")
                self.assertFalse(PACK.allowed_asset(relative.removeprefix("web/")))

    def test_retirement_stubs_do_not_satisfy_required_hashed_bundle_check(self):
        manifest = {key: digest for key, digest in self.manifest.items() if not key.startswith("web/assets/")}
        (self.bundle / "manifest.json").write_text(json.dumps(manifest))
        self.install(success=False)
        self.assertEqual((self.web / "index.html").read_text(), "old website placeholder")

    def test_missing_webroot_is_not_silently_created(self):
        other_home = self.root / "wrong-home"
        other_home.mkdir()
        result = subprocess.run([PHP, str(self.bundle / "install.php"), str(other_home)], capture_output=True, timeout=20)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(list(other_home.iterdir()), [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
