#!/usr/bin/env python3
"""Offline tests for Server/tools/build_bundle.py using temporary directories only."""
import importlib.util
import json
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import patch

SOURCE = Path(__file__).resolve().parents[2] / 'Server/tools/build_bundle.py'
SPEC = importlib.util.spec_from_file_location('build_bundle', SOURCE)
BB = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BB)

HASH = 'abcdefgh12345'


class AssetRuleTests(unittest.TestCase):
    def test_hashed_asset(self):
        self.assertTrue(BB.hashed_asset(f'index-{HASH}.js'))
        self.assertTrue(BB.hashed_asset(f'main-{HASH}.css'))
        for name in ('index.js', 'index-short.js', f'index-{HASH}.png', '-abcdefgh12.js', 'a b-abcdefgh12.js'):
            self.assertFalse(BB.hashed_asset(name), name)

    def test_allowed_asset(self):
        self.assertTrue(BB.allowed_asset('robots.txt'))
        self.assertTrue(BB.allowed_asset('images/logo.png'))
        self.assertTrue(BB.allowed_asset(f'assets/index-{HASH}.js'))
        for rel in ('assets/index.js', 'assets/sub/x-abcdefgh12.js', '../x.png', 'assets//x.png', 'evil.sh', 'a/./b.png'):
            self.assertFalse(BB.allowed_asset(rel), rel)

    def test_validate_website_asset(self):
        BB.validate_website_asset('robots.txt', Path('robots.txt'))
        with self.assertRaises(ValueError):
            BB.validate_website_asset('evil.sh', Path('evil.sh'))
        with patch.object(BB, 'allowed_asset', return_value=True):
            with self.assertRaises(ValueError):
                BB.validate_website_asset('assets/app.js', Path('app.js'))
            with self.assertRaises(ValueError):
                BB.validate_website_asset('assets/../x.png', Path('x.png'))


class CopyTests(unittest.TestCase):
    def test_safe_copy_and_unsafe_sources(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            src = tmp / 'a.txt'
            src.write_text('hello')
            digest = BB.safe_copy(src, tmp / 'out/b.txt')
            self.assertEqual(len(digest), 64)
            self.assertEqual((tmp / 'out/b.txt').read_text(), 'hello')
            with self.assertRaises(ValueError):
                BB.safe_copy(tmp / 'missing', tmp / 'x')
            link = tmp / 'link'
            link.symlink_to(src)
            with self.assertRaises(ValueError):
                BB.safe_copy(link, tmp / 'y')

    def test_copy_website_assets_skips_index_and_rejects_symlinks(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            dist, bundle = tmp / 'dist', tmp / 'bundle'
            (dist / 'assets').mkdir(parents=True)
            (dist / 'index.html').write_text('<html>')
            (dist / '.htaccess').write_text('x')
            (dist / 'robots.txt').write_text('r')
            (dist / 'assets' / f'app-{HASH}.js').write_text('js')
            manifest = {}
            BB.copy_website_assets(dist, bundle, manifest)
            self.assertEqual(sorted(manifest), ['web/assets/app-' + HASH + '.js', 'web/robots.txt'])
            (dist / 'link.txt').symlink_to(dist / 'robots.txt')
            with self.assertRaises(ValueError):
                BB.copy_website_assets(dist, bundle, {})


class BuildTests(unittest.TestCase):
    def make_root(self, tmp, assets=True):
        root = Path(tmp) / 'repo'
        dist = root / 'website/dist'
        (dist / 'assets').mkdir(parents=True)
        (dist / 'index.html').write_text('<html>')
        if assets:
            (dist / 'assets' / f'app-{HASH}.js').write_text('js')
            (dist / 'assets' / f'app-{HASH}.css').write_text('css')
        for source in list(BB.STATIC_FILES.values()) + ['Server/tools/install.php']:
            path = root / source
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(source)
        return root

    def test_build_produces_archive_and_manifest(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = self.make_root(tmp)
            out = Path(tmp) / 'out'
            with patch.object(BB, 'ROOT', root):
                archive = BB.build(out)
                self.assertTrue(archive.is_file())
                manifest = json.loads((out / 'bundle/manifest.json').read_text())
                self.assertIn('web/index.html', manifest)
                self.assertIn('private/Service.php', manifest)
                with tarfile.open(archive) as stream:
                    self.assertIn('manifest.json', stream.getnames())
                with self.assertRaises(ValueError):
                    BB.build(out)

    def test_build_requires_dist_and_hashed_assets(self):
        with tempfile.TemporaryDirectory() as tmp:
            empty = Path(tmp) / 'empty'
            empty.mkdir()
            with patch.object(BB, 'ROOT', empty):
                with self.assertRaises(ValueError):
                    BB.build(Path(tmp) / 'o1')
            root = self.make_root(Path(tmp) / 'second', assets=False)
            with patch.object(BB, 'ROOT', root):
                with self.assertRaises(ValueError):
                    BB.build(Path(tmp) / 'o2')


if __name__ == '__main__':
    unittest.main()
