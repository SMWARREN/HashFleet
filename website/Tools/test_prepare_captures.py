#!/usr/bin/env python3
"""Offline tests for the capture preparation scripts. All paths live in temporary directories."""
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch
import contextlib
import zlib

TOOLS = Path(__file__).resolve().parent


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, TOOLS / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def png(width, height):
    def chunk(kind, data):
        body = kind + data
        return struct.pack('>I', len(data)) + body + struct.pack('>I', zlib.crc32(body) & 0xffffffff)
    raw = b''.join(b'\x00' + b'\x80\x40\x20' * width for _ in range(height))
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b''))


class NativeCaptureTests(unittest.TestCase):
    def setUp(self):
        self.mod = load('prepare_native_captures', 'prepare-native-captures.py')

    def run_main(self, root, source, *extra, magick=None):
        argv = ['prepare-native-captures.py', '--source', str(source), *extra]
        out = io.StringIO()
        with patch.object(self.mod, 'ROOT', root), patch.object(sys, 'argv', argv), \
             patch.object(self.mod.subprocess, 'run') as run, \
             patch.object(self.mod.subprocess, 'check_output', side_effect=magick), contextlib.redirect_stdout(out):
            self.mod.main()
        return out.getvalue(), run

    def test_digest(self):
        self.assertEqual(self.mod.digest(b'x'), hashlib.sha256(b'x').hexdigest())

    def test_pixels_invokes_magick(self):
        with patch.object(self.mod.subprocess, 'check_output', return_value=b'raw') as call:
            self.assertEqual(self.mod.pixels('magick', Path('a.png')), b'raw')
        self.assertIn('RGBA:-', call.call_args.args[0])

    def fake_magick(self, pixels=b'same'):
        def fake(cmd, **kwargs):
            if 'identify' in cmd:
                return '100 200'
            return pixels
        return fake

    def make_tree(self, tmp):
        source = Path(tmp) / 'source'
        source.mkdir()
        root = Path(tmp) / 'root'
        (root / 'src/lib').mkdir(parents=True)
        for name in self.mod.NAMES:
            (source / f'{name}.png').write_bytes(b'png-' + name.encode())
        return root, source

    def test_write_then_verify_round_trip(self):
        with tempfile.TemporaryDirectory() as tmp:
            root, source = self.make_tree(tmp)
            output = root / 'public/images/native'
            output.mkdir(parents=True)
            for name in self.mod.NAMES:
                (output / f'{name}-{self.mod.VERSION}.webp').write_bytes(b'webp')
            text, run = self.run_main(root, source, magick=self.fake_magick())
            self.assertEqual(json.loads(text)['verified'], len(self.mod.NAMES))
            self.assertEqual(run.call_count, len(self.mod.NAMES))
            manifest = json.loads((root / 'src/lib/native-captures.json').read_text())
            self.assertEqual(len(manifest['captures']), len(self.mod.NAMES))
            text, run = self.run_main(root, source, '--verify', magick=self.fake_magick())
            self.assertEqual(run.call_count, 0)
            self.assertTrue(json.loads(text)['pixelIdentity'])

    def test_verify_detects_changed_receipt_and_pixels_and_missing_source(self):
        with tempfile.TemporaryDirectory() as tmp:
            root, source = self.make_tree(tmp)
            output = root / 'public/images/native'
            output.mkdir(parents=True)
            for name in self.mod.NAMES:
                (output / f'{name}-{self.mod.VERSION}.webp').write_bytes(b'webp')
            self.run_main(root, source, magick=self.fake_magick())
            manifest_path = root / 'src/lib/native-captures.json'
            manifest = json.loads(manifest_path.read_text())
            manifest['captures'][0]['bytes'] += 1
            manifest_path.write_text(json.dumps(manifest))
            with self.assertRaises(ValueError):
                self.run_main(root, source, '--verify', magick=self.fake_magick())
            calls = iter([b'a', b'b'])
            def differing(cmd, **kwargs):
                return next(calls)
            with self.assertRaises(ValueError):
                self.run_main(root, source, magick=differing)
            (source / f'{self.mod.NAMES[0]}.png').unlink()
            with self.assertRaises(ValueError):
                self.run_main(root, source, magick=self.fake_magick())


class WatchCaptureTests(unittest.TestCase):
    def run_script(self, root, source, *extra):
        argv = ['prepare-watch-captures.py', '--source', str(source), *extra]
        out = io.StringIO()
        spec = importlib.util.spec_from_file_location('prepare_watch_captures', TOOLS / 'prepare-watch-captures.py')
        module = importlib.util.module_from_spec(spec)
        real_file = str(root / 'Tools' / 'prepare-watch-captures.py')
        module.__dict__['__file__'] = real_file
        with patch.object(sys, 'argv', argv), contextlib.redirect_stdout(out):
            code = compile((TOOLS / 'prepare-watch-captures.py').read_text(), real_file, 'exec')
            exec(code, module.__dict__)
        return json.loads(out.getvalue())

    def test_copy_and_verify(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / 'site'
            (root / 'src/lib').mkdir(parents=True)
            (root / 'Tools').mkdir()
            source = Path(tmp) / 'src'
            source.mkdir()
            data = png(368, 448)
            for filename in ['25841F69-45BC-4010-A1FF-C0D7D8B64942.png', '49E589CD-EAEA-4547-9358-901858745AC8.png',
                             '1D80807F-A78A-4236-9191-C715D384502B.png', 'EE2DAA4F-4824-4BA9-BF67-53CDF11CB006.png',
                             '242E3D7F-553F-4237-BA42-DDF1B4C954F6.png']:
                (source / filename).write_bytes(data)
            first = self.run_script(root, source)
            self.assertEqual(first['native_captures'], 5)
            # Running again reuses identical existing copies, then verify matches the manifest.
            self.run_script(root, source)
            self.assertTrue(self.run_script(root, source, '--verify')['all_source_and_public_png_bytes_identical'])
            target = next((root / 'public/images/watch').iterdir())
            target.write_bytes(b'different')
            with self.assertRaises(AssertionError):
                self.run_script(root, source)


if __name__ == '__main__':
    unittest.main()
