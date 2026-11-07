import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageStat

if __package__:
    from .generate_hash_fleet_brand_loop import render_frames, save_loop
else:
    from generate_hash_fleet_brand_loop import render_frames, save_loop


class GenerateHashFleetBrandLoopTests(unittest.TestCase):
    @staticmethod
    def synthetic_source():
        image = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
        draw = ImageDraw.Draw(image)
        draw.rounded_rectangle((28, 7, 100, 31), radius=6, fill=(24, 22, 19, 255))
        draw.rounded_rectangle((45, 16, 83, 22), radius=2, fill=(252, 188, 32, 255))
        draw.ellipse((18, 22, 110, 114), fill=(32, 32, 34, 255))
        draw.polygon(((63, 47), (70, 29), (80, 39), (73, 56)), fill=(168, 169, 171, 255))
        draw.polygon(((61, 88), (54, 106), (44, 96), (52, 79)), fill=(132, 133, 135, 255))
        draw.ellipse((46, 50, 82, 86), fill=(48, 48, 50, 255), outline=(243, 157, 22, 255), width=3)
        return image

    def test_bundled_loop_has_stable_alpha_and_a_smooth_cycle_seam(self):
        asset = (
            Path(__file__).resolve().parents[1]
            / "App/Resources/Assets.xcassets/HashFleetBrandLoop.dataset/HashFleetBrandLoop.webp"
        )
        with Image.open(asset) as webp:
            self.assertEqual(webp.format, "WEBP")
            self.assertEqual(webp.n_frames, 48)
            self.assertEqual(webp.size, (640, 640))
            self.assertEqual(webp.info.get("loop"), 0)
            frames = []
            alpha_bounds = []
            for index in range(webp.n_frames):
                webp.seek(index)
                frame = webp.convert("RGBA").copy()
                frames.append(frame)
                alpha_bounds.append(frame.getchannel("A").getbbox())

        self.assertEqual(len(set(alpha_bounds)), 1)

        def mean_rgb_difference(first, second):
            means = ImageStat.Stat(
                ImageChops.difference(first.convert("RGB"), second.convert("RGB"))
            ).mean
            return sum(means[:3]) / 3

        adjacent_delta = mean_rgb_difference(frames[0], frames[1])
        seam_delta = mean_rgb_difference(frames[-1], frames[0])
        self.assertGreater(adjacent_delta, 0)
        self.assertGreaterEqual(seam_delta / adjacent_delta, 0.65)
        self.assertLessEqual(seam_delta / adjacent_delta, 1.45)

    def test_cli_accepts_custom_source_geometry(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            source_path = root / "source.png"
            output_path = root / "loop.webp"
            self.synthetic_source().save(source_path)
            script = Path(__file__).with_name("generate_hash_fleet_brand_loop.py")

            subprocess.run(
                [
                    sys.executable,
                    str(script),
                    "--source",
                    str(source_path),
                    "--output",
                    str(output_path),
                    "--size",
                    "64",
                    "--frames",
                    "8",
                    "--rotor-center",
                    "64",
                    "68",
                    "--rotor-inner-radius",
                    "19",
                    "--rotor-outer-radius",
                    "45",
                    "--led-region",
                    "40",
                    "10",
                    "88",
                    "26",
                ],
                check=True,
                capture_output=True,
                text=True,
            )

            with Image.open(output_path) as webp:
                self.assertEqual(webp.n_frames, 8)
                self.assertEqual(webp.size, (64, 64))

    def test_frames_rotate_the_blade_annulus_but_preserve_hub_and_alpha(self):
        source = self.synthetic_source()
        frames = render_frames(
            source,
            size=64,
            frame_count=8,
            rotor_center=(64, 68),
            rotor_inner_radius=19,
            rotor_outer_radius=45,
            led_region=(40, 10, 88, 26),
        )

        self.assertEqual(len(frames), 8)
        self.assertTrue(all(frame.size == (64, 64) for frame in frames))
        self.assertEqual(frames[0].getpixel((32, 34)), frames[4].getpixel((32, 34)))
        self.assertEqual(frames[0].getpixel((0, 0))[3], 0)
        difference = ImageChops.difference(
            frames[0].convert("RGB"), frames[1].convert("RGB")
        )
        self.assertIsNotNone(difference.getbbox())

    def test_webp_is_lossless_transparent_loop_with_expected_frame_timing(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            source_path = root / "source.png"
            output_path = root / "loop.webp"
            self.synthetic_source().save(source_path)

            save_loop(
                source_path,
                output_path,
                size=64,
                frame_count=8,
                frame_duration_ms=42,
                rotor_center=(64, 68),
                rotor_inner_radius=19,
                rotor_outer_radius=45,
                led_region=(40, 10, 88, 26),
            )

            with Image.open(output_path) as webp:
                self.assertEqual(webp.format, "WEBP")
                self.assertEqual(webp.n_frames, 8)
                self.assertEqual(webp.info.get("loop"), 0)
                webp.seek(0)
                self.assertEqual(webp.mode, "RGBA")
                self.assertEqual(webp.getpixel((0, 0))[3], 0)

    def test_rejects_invalid_frame_count_and_missing_status_light(self):
        source = self.synthetic_source()
        with self.assertRaises(ValueError):
            render_frames(source, size=64, frame_count=3)

        missing_led_source = Image.new("RGBA", (128, 128), (12, 12, 12, 255))
        with self.assertRaises(ValueError):
            render_frames(
                missing_led_source,
                size=64,
                frame_count=8,
                rotor_center=(64, 64),
                rotor_inner_radius=12,
                rotor_outer_radius=40,
                led_region=(40, 10, 88, 26),
            )


if __name__ == "__main__":
    unittest.main()
