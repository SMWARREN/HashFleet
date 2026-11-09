import tempfile
import unittest
from pathlib import Path

from PIL import Image, ImageDraw

from Tools.import_3dicon_webp import import_webp, inspect_webp


class Import3DIconWebPTests(unittest.TestCase):
    @staticmethod
    def write_animation(path, *, loop=0, transparent=True, motion=True):
        frames = []
        for index in range(2):
            image = Image.new(
                "RGBA",
                (32, 32),
                (0, 0, 0, 0) if transparent else (10, 10, 10, 255),
            )
            draw = ImageDraw.Draw(image)
            x = 5 if index == 0 or not motion else 13
            draw.ellipse((x, 8, x + 12, 20), fill=(247, 150, 20, 255))
            frames.append(image)
        frames[0].save(
            path,
            format="WEBP",
            save_all=True,
            append_images=frames[1:],
            duration=[50, 50],
            loop=loop,
            lossless=True,
        )

    def test_current_bundled_loop_meets_the_import_contract(self):
        asset = (
            Path(__file__).resolve().parents[1]
            / "App/Resources/Assets.xcassets/HashFleetBrandLoop.dataset/HashFleetBrandLoop.webp"
        )
        info = inspect_webp(asset)
        self.assertEqual((info.width, info.height), (640, 640))
        self.assertEqual(info.frames, 48)
        self.assertEqual(info.loop, 0)
        self.assertTrue(info.has_alpha)
        self.assertTrue(info.has_motion)
        self.assertGreater(info.duration_ms, 0)

    def test_validates_and_copies_candidate(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            candidate = root / "3dicon.webp"
            output = root / "HashFleetBrandLoop.webp"
            self.write_animation(candidate)

            info = import_webp(candidate, output)

            self.assertEqual(output.read_bytes(), candidate.read_bytes())
            self.assertTrue(info.has_alpha)
            self.assertTrue(info.has_motion)

    def test_existing_asset_requires_explicit_replace_and_stays_intact(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            candidate = root / "candidate.webp"
            output = root / "current.webp"
            self.write_animation(candidate)
            output.write_bytes(b"existing asset")

            with self.assertRaisesRegex(FileExistsError, "--replace"):
                import_webp(candidate, output)

            self.assertEqual(output.read_bytes(), b"existing asset")

    def test_explicit_replace_installs_valid_candidate(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            candidate = root / "candidate.webp"
            output = root / "current.webp"
            self.write_animation(candidate)
            output.write_bytes(b"existing asset")

            import_webp(candidate, output, replace=True)

            self.assertEqual(output.read_bytes(), candidate.read_bytes())

    def test_rejects_finite_loop(self):
        with tempfile.TemporaryDirectory() as directory:
            candidate = Path(directory) / "finite.webp"
            self.write_animation(candidate, loop=2)
            with self.assertRaisesRegex(ValueError, "loop=0"):
                inspect_webp(candidate)

    def test_rejects_opaque_animation(self):
        with tempfile.TemporaryDirectory() as directory:
            candidate = Path(directory) / "opaque.webp"
            self.write_animation(candidate, transparent=False)
            with self.assertRaisesRegex(ValueError, "transparency"):
                inspect_webp(candidate)

    def test_rejects_static_image(self):
        with tempfile.TemporaryDirectory() as directory:
            candidate = Path(directory) / "still.webp"
            Image.new("RGBA", (32, 32), (0, 0, 0, 0)).save(candidate, format="WEBP")
            with self.assertRaisesRegex(ValueError, "two frames"):
                inspect_webp(candidate)


if __name__ == "__main__":
    unittest.main()
