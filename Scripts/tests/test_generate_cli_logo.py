#!/usr/bin/env python3
"""Offline test for Scripts/generate-cli-logo.py. Runs it against a temporary tree."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

try:
    from PIL import Image
except ImportError:  # pragma: no cover - Pillow is installed in CI
    Image = None

SOURCE = Path(__file__).resolve().parents[1] / 'generate-cli-logo.py'


@unittest.skipIf(Image is None, 'Pillow is required')
class GenerateCliLogoTests(unittest.TestCase):
    def test_generates_swift_pixel_tables(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'Scripts').mkdir()
            (root / 'MacMenuBar/Resources').mkdir(parents=True)
            (root / 'Sources/hashfleet').mkdir(parents=True)
            image = Image.new('RGBA', (48, 60), (0, 0, 0, 0))
            for x in range(8, 40):
                for y in range(10, 50):
                    image.putpixel((x, y), (200, 120 + x, 40 + y, 255))
            image.save(root / 'MacMenuBar/Resources/HashFleetStatusIcon.png')
            script = root / 'Scripts' / 'generate-cli-logo.py'
            spec = importlib.util.spec_from_file_location('generate_cli_logo', SOURCE)
            module = importlib.util.module_from_spec(spec)
            code = compile(SOURCE.read_text(), str(script), 'exec')
            module.__dict__['__file__'] = str(script)
            exec(code, module.__dict__)
            text = (root / 'Sources/hashfleet/DashboardLogo.swift').read_text()
            for marker in ('enum DashboardLogo', 'static let small', 'static let medium', 'static let large', 'Source SHA-256'):
                self.assertIn(marker, text)
            self.assertEqual(text.count('static let colors'), 1)


if __name__ == '__main__':
    unittest.main()
