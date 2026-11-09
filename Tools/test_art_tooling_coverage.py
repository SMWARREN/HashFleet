"""Behavior coverage for the fleet art loop generators.

`generate_fleet_art_loops.py` animates bundled fleet illustrations into seamless
transparent WebP loops; `generate_hash_fleet_brand_loop.py` produces the startup
brand loop from the approved still. These tests drive the real pure functions on
synthetic in-memory artwork so nothing touches the shipped assets, and every
assertion checks a concrete rendered product (frame geometry, seam smoothness,
mask coverage, WebP roundtrip, error paths). No model, API key, or network.
"""

from __future__ import annotations

import math
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageStat

if __package__:
    from .generate_hash_fleet_brand_loop import (
        _annulus_mask,
        _led_mask as brand_led_mask,
        render_frames as brand_render_frames,
        save_loop as brand_save_loop,
    )
    from .generate_fleet_art_loops import (
        SPECS,
        ArtSpec,
        Rotor,
        _ellipse_annulus,
        _led_mask,
        _rotate_rotor,
        _static_glow_mask,
        render_frames,
        save_loop,
    )
else:
    from generate_hash_fleet_brand_loop import (
        _annulus_mask,
        _led_mask as brand_led_mask,
        render_frames as brand_render_frames,
        save_loop as brand_save_loop,
    )
    from generate_fleet_art_loops import (
        SPECS,
        ArtSpec,
        Rotor,
        _ellipse_annulus,
        _led_mask,
        _rotate_rotor,
        _static_glow_mask,
        render_frames,
        save_loop,
    )

TOOLS_DIR = Path(__file__).resolve().parent


def _mean_rgb_difference(first: Image.Image, second: Image.Image) -> float:
    means = ImageStat.Stat(
        ImageChops.difference(first.convert("RGB"), second.convert("RGB"))
    ).mean
    return sum(means[:3]) / 3


class FleetArtSyntheticSource:
    """Draws stand-in artwork that matches each spec's rotor and LED geometry."""

    @staticmethod
    def cluster_source() -> Image.Image:
        size = (1000, 600)
        image = Image.new("RGBA", size, (0, 0, 0, 0))
        draw = ImageDraw.Draw(image)
        rotors = (
            Rotor((171, 365), 60, 104, x_scale=0.92, phase=0.17),
            Rotor((510, 366), 72, 148, phase=0.0),
            Rotor((846, 368), 60, 100, x_scale=0.92, phase=0.41),
        )
        for rotor in rotors:
            cx, cy = rotor.center
            rx_out = rotor.outer_radius * rotor.x_scale
            draw.ellipse(
                (cx - rx_out, cy - rotor.outer_radius,
                 cx + rx_out, cy + rotor.outer_radius),
                fill=(40, 42, 45, 255),
            )
            rx_in = rotor.inner_radius * rotor.x_scale
            draw.ellipse(
                (cx - rx_in, cy - rotor.inner_radius,
                 cx + rx_in, cy + rotor.inner_radius),
                fill=(24, 26, 28, 255),
            )
            for angle in range(0, 360, 30):
                radians = math.radians(angle)
                draw.line(
                    (
                        cx + rotor.outer_radius * rotor.x_scale * math.cos(radians),
                        cy + rotor.outer_radius * math.sin(radians),
                        cx + rotor.inner_radius * rotor.x_scale * math.cos(radians),
                        cy + rotor.inner_radius * math.sin(radians),
                    ),
                    fill=(120, 124, 128, 255),
                    width=10,
                )
        for left, top, right, bottom in SPECS["FleetClusterArt"].led_regions:
            draw.rectangle(
                (left + 10, top + 10, right - 10, bottom - 10),
                fill=(252, 188, 32, 255),
            )
        return image

    @staticmethod
    def cooling_source() -> Image.Image:
        size = (512, 512)
        image = Image.new("RGBA", size, (0, 0, 0, 0))
        draw = ImageDraw.Draw(image)
        rotor = SPECS["MinerCoolingArt"].rotors[0]
        cx, cy = rotor.center
        draw.ellipse(
            (cx - rotor.outer_radius, cy - rotor.outer_radius,
             cx + rotor.outer_radius, cy + rotor.outer_radius),
            fill=(40, 42, 45, 255),
        )
        draw.ellipse(
            (cx - rotor.inner_radius, cy - rotor.inner_radius,
             cx + rotor.inner_radius, cy + rotor.inner_radius),
            fill=(24, 26, 28, 255),
        )
        for angle in range(0, 360, 30):
            radians = math.radians(angle)
            draw.line(
                (cx + rotor.outer_radius * math.cos(radians),
                 cy + rotor.outer_radius * math.sin(radians),
                 cx + rotor.inner_radius * math.cos(radians),
                 cy + rotor.inner_radius * math.sin(radians)),
                fill=(120, 124, 128, 255),
                width=12,
            )
        # Warm amber airflow streaks over the blades: must stay static while blades turn.
        draw.line((cx - 140, cy + 40, cx + 140, cy - 60), fill=(255, 170, 60, 255), width=10)
        left, top, right, bottom = SPECS["MinerCoolingArt"].led_regions[0]
        draw.rectangle((left + 10, top + 10, right - 10, bottom - 10), fill=(252, 188, 32, 255))
        return image

    @staticmethod
    def brand_source() -> Image.Image:
        image = Image.new("RGBA", (400, 400), (0, 0, 0, 0))
        draw = ImageDraw.Draw(image)
        draw.ellipse((60, 60, 340, 340), fill=(32, 32, 34, 255))
        draw.ellipse((100, 100, 300, 300), fill=(48, 48, 50, 255), outline=(243, 157, 22, 255), width=3)
        draw.rectangle((150, 20, 250, 45), fill=(252, 188, 32, 255))
        return image


class FleetArtLoopGeometryTests(unittest.TestCase):
    def test_specs_cover_both_bundled_artworks_with_rotors_and_led_regions(self):
        for name in ("FleetClusterArt", "MinerCoolingArt"):
            spec = SPECS[name]
            self.assertTrue(spec.rotors, f"{name} must configure rotors")
            self.assertTrue(spec.led_regions, f"{name} must configure LED regions")
            for rotor in spec.rotors:
                self.assertGreater(rotor.outer_radius, rotor.inner_radius)
                self.assertGreater(rotor.x_scale, 0)

    def test_fleet_cluster_spec_draws_at_768_by_512(self):
        self.assertEqual(SPECS["FleetClusterArt"].size, (768, 512))

    def test_annulus_mask_covers_ring_and_excludes_hub(self):
        source = FleetArtSyntheticSource.cluster_source()
        rotor = Rotor((500, 300), 60, 100)
        mask = _ellipse_annulus(source.size, rotor)
        self.assertEqual(mask.size, source.size)
        center = mask.getpixel(rotor.center)
        ring = mask.getpixel((rotor.center[0], rotor.center[1] - 80))
        outside = mask.getpixel((rotor.center[0], rotor.center[1] - 130))
        self.assertLess(center, 40, "The hub must stay out of the mask")
        self.assertGreater(ring, 200, "The blade ring must be inside the mask")
        self.assertLess(outside, 40, "Beyond the outer radius stays out of the mask")

    def test_annulus_mask_feathering_zero_returns_a_crisp_ring(self):
        # feather=0 skips the Gaussian blur and returns the raw multiply mask.
        crisp = _ellipse_annulus((100, 100), Rotor((50, 50), 20, 40), feather=0)
        self.assertEqual(crisp.getpixel((50, 15)), 255, "No blur: the ring is fully selected")
        self.assertEqual(crisp.getpixel((50, 50)), 0, "The hub hole stays fully unselected")

    def test_rotate_rotor_moves_blades_when_sampled_inside_the_annulus(self):
        source = FleetArtSyntheticSource.cooling_source()
        rotor = SPECS["MinerCoolingArt"].rotors[0]
        mask = _ellipse_annulus(source.size, rotor)
        rest = source.copy()
        turned = source.copy()
        turned.paste(_rotate_rotor(source, rotor, 17.0), (0, 0), mask)
        self.assertEqual(rest.size, source.size)
        self.assertEqual(turned.size, source.size)

        difference = ImageChops.difference(rest.convert("RGB"), turned.convert("RGB")).convert("L")
        inside_ring = ImageChops.multiply(difference, mask)
        self.assertIsNotNone(inside_ring.getbbox(), "A 17-degree rotation moves blade pixels in the annulus")

    def test_rotate_rotor_supports_foreshortened_side_fans(self):
        source = FleetArtSyntheticSource.cluster_source()
        side_rotor = SPECS["FleetClusterArt"].rotors[0]
        self.assertNotEqual(side_rotor.x_scale, 1.0)
        spun = _rotate_rotor(source, side_rotor, 45.0)
        self.assertEqual(spun.size, source.size)
        self.assertGreater(spun.getbbox(), (0, 0, 0, 0), "The perspective rotor must render")

    def test_led_mask_rejects_regions_outside_the_image(self):
        image = Image.new("RGBA", (100, 100), (0, 0, 0, 0))
        with self.assertRaises(ValueError):
            _led_mask(image, ((110, 0, 130, 10),))

    def test_led_mask_requires_an_amber_strip_in_the_region(self):
        image = Image.new("RGBA", (100, 100), (255, 255, 255, 255))
        with self.assertRaises(ValueError):
            _led_mask(image, ((10, 10, 90, 90),))

    def test_led_mask_marks_only_bright_amber_pixels(self):
        size = (100, 100)
        image = Image.new("RGBA", size, (0, 0, 0, 0))
        draw = ImageDraw.Draw(image)
        draw.rectangle((10, 10, 20, 20), fill=(252, 188, 32, 255))   # amber strip
        draw.rectangle((30, 10, 40, 20), fill=(60, 60, 60, 255))      # neutral gray
        draw.rectangle((50, 10, 60, 20), fill=(252, 188, 120, 255))  # too pale
        mask = _led_mask(image, ((0, 0, 100, 100),))
        self.assertGreater(mask.getpixel((15, 15)), 100, "Amber strip is selected")
        self.assertEqual(mask.getpixel((35, 15)), 0, "Gray pixels are ignored")
        self.assertLess(mask.getpixel((55, 15)), 100, "Pale orange is not bright enough")

    def test_static_glow_mask_keeps_only_warm_streaks_inside_rotors(self):
        source = FleetArtSyntheticSource.cooling_source()
        spec = SPECS["MinerCoolingArt"]
        rotor_masks = [_ellipse_annulus(source.size, rotor) for rotor in spec.rotors]
        glow = _static_glow_mask(source, rotor_masks)
        box = glow.getbbox()
        self.assertIsNotNone(box, "The amber streak must be captured")
        cx, cy = spec.rotors[0].center
        self.assertTrue(box[0] <= cx <= box[2] and box[1] <= cy <= box[3],
                        "The glow sits over the spinning rotor area")

    def test_static_glow_mask_unions_multiple_rotors_and_skips_empty_unions(self):
        source = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
        draw = ImageDraw.Draw(source)
        draw.ellipse((152, 264, 484, 596), fill=(40, 42, 45, 255))
        draw.line((100, 100, 200, 200), fill=(255, 170, 60, 255), width=8)
        main_rotor = _ellipse_annulus(source.size, Rotor((318, 430), 94, 166))
        side_rotor = _ellipse_annulus(source.size, Rotor((150, 120), 40, 90))
        unioned = _static_glow_mask(source, [main_rotor, side_rotor])
        self.assertIsNotNone(unioned.getbbox(), "A streak over any rotor is captured")

        # A mask union with no pixel coverage has no bbox: the glow stays empty and
        # the function must return the blank mask without scanning the source.
        empty = _ellipse_annulus(source.size, Rotor((10, 10), 5, 8))
        blank = _static_glow_mask(source, [empty, _ellipse_annulus(source.size, Rotor((12, 12), 5, 8))])
        self.assertIsNone(blank.getbbox())


class FleetArtLoopRenderTests(unittest.TestCase):
    def test_render_frames_returns_seamless_cycle_at_spec_size(self):
        source = FleetArtSyntheticSource.cluster_source()
        frames = render_frames(source, SPECS["FleetClusterArt"], 6)
        self.assertEqual(len(frames), 6)
        for frame in frames:
            self.assertEqual(frame.size, (768, 512))
            self.assertEqual(frame.mode, "RGBA")
        adjacent = _mean_rgb_difference(frames[0], frames[1])
        seam = _mean_rgb_difference(frames[-1], frames[0])
        self.assertGreater(adjacent, 0, "Motion between frames must be visible")
        self.assertGreaterEqual(seam / adjacent, 0.5)
        self.assertLessEqual(seam / adjacent, 1.5, "The loop must close smoothly")

    def test_render_frames_keeps_transparent_corners(self):
        source = FleetArtSyntheticSource.cooling_source()
        frames = render_frames(source, SPECS["MinerCoolingArt"], 4)
        for frame in frames:
            self.assertEqual(frame.getpixel((2, 2))[3], 0, "Corners stay transparent")

    def test_render_frames_rejects_too_few_frames(self):
        source = FleetArtSyntheticSource.cooling_source()
        with self.assertRaises(ValueError):
            render_frames(source, SPECS["MinerCoolingArt"], 3)

    def test_render_frames_resizes_sources_larger_than_spec(self):
        source = FleetArtSyntheticSource.cluster_source()  # 1000x600 > 768x512
        frames = render_frames(source, SPECS["FleetClusterArt"], 4)
        self.assertEqual(frames[0].size, SPECS["FleetClusterArt"].size)

    def test_save_loop_writes_an_endless_transparent_webp(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            source_path = root / "source.png"
            output_path = root / "nested" / "loop.webp"
            FleetArtSyntheticSource.cooling_source().save(source_path)
            returned = save_loop(source_path, output_path, SPECS["MinerCoolingArt"], 5)
            self.assertEqual(returned, output_path)
            self.assertTrue(output_path.exists())
            with Image.open(output_path) as webp:
                self.assertEqual(webp.format, "WEBP")
                self.assertEqual(webp.n_frames, 5)
                self.assertEqual(webp.size, (512, 512))
                self.assertEqual(webp.info.get("loop"), 0, "The loop is endless")


class BrandLoopCoverageTests(unittest.TestCase):
    def test_brand_render_frames_cycle_smoothly_and_resize(self):
        source = FleetArtSyntheticSource.brand_source()
        frames = brand_render_frames(
            source, size=64, frame_count=8,
            rotor_center=(200, 200), rotor_inner_radius=60, rotor_outer_radius=140,
            led_region=(140, 10, 260, 60),
        )
        self.assertEqual(len(frames), 8)
        self.assertEqual(frames[0].size, (64, 64))
        adjacent = _mean_rgb_difference(frames[0], frames[1])
        seam = _mean_rgb_difference(frames[-1], frames[0])
        self.assertGreater(adjacent, 0)
        self.assertGreaterEqual(seam / adjacent, 0.5)
        self.assertLessEqual(seam / adjacent, 1.5)

    def test_brand_render_frames_reject_invalid_arguments(self):
        source = FleetArtSyntheticSource.brand_source()
        with self.assertRaises(ValueError):
            brand_render_frames(source, size=0, frame_count=8)
        with self.assertRaises(ValueError):
            brand_render_frames(source, size=64, frame_count=2)

    def test_brand_render_frames_converts_non_rgba_sources(self):
        # A non-RGBA source (e.g. a flattened JPEG-style RGB still) must be converted
        # in memory before masking, and still produce the same RGBA frame output.
        rgb_source = Image.new("RGB", (400, 400), (20, 20, 20))
        draw = ImageDraw.Draw(rgb_source)
        draw.ellipse((60, 60, 340, 340), fill=(40, 42, 45))
        draw.rectangle((150, 20, 250, 45), fill=(252, 188, 32))
        frames = brand_render_frames(
            rgb_source, size=32, frame_count=4,
            rotor_center=(200, 200), rotor_inner_radius=60, rotor_outer_radius=140,
            led_region=(150, 20, 250, 45),
        )
        self.assertEqual(len(frames), 4)
        self.assertEqual(frames[0].mode, "RGBA")
        self.assertEqual(frames[0].size, (32, 32))

    def test_brand_annulus_mask_rejects_degenerate_radii(self):
        with self.assertRaises(ValueError):
            _annulus_mask((100, 100), (50, 50), inner_radius=20, outer_radius=10)

    def test_brand_led_mask_guards_reject_bad_regions(self):
        # The brand loop's own LED finder shares the fleet one's safety contract: a
        # region must fit inside the image and must actually contain an amber strip.
        out_of_bounds = Image.new("RGBA", (100, 100))
        no_amber = Image.new("RGBA", (100, 100), (255, 255, 255, 255))
        with self.assertRaises(ValueError):
            brand_led_mask(out_of_bounds, (110, 0, 130, 10))
        with self.assertRaises(ValueError):
            brand_led_mask(no_amber, (10, 10, 90, 90))
        amber = Image.new("RGBA", (100, 100), (0, 0, 0, 0))
        ImageDraw.Draw(amber).rectangle((20, 20, 80, 30), fill=(252, 188, 32, 255))
        mask = brand_led_mask(amber, (10, 10, 90, 40))
        self.assertGreater(mask.getbbox(), (0, 0, 0, 0), "The amber strip is selected")

    def test_brand_save_loop_converts_an_rgb_source_file(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            source_path = root / "flat.png"
            output_path = root / "loop.webp"
            rgb_source = Image.new("RGB", (400, 400), (20, 20, 20))
            draw = ImageDraw.Draw(rgb_source)
            draw.ellipse((60, 60, 340, 340), fill=(40, 42, 45))
            draw.rectangle((150, 20, 250, 45), fill=(252, 188, 32))
            rgb_source.save(source_path)
            returned = brand_save_loop(
                source_path, output_path, size=32, frame_count=4, frame_duration_ms=50,
                rotor_center=(200, 200), rotor_inner_radius=60, rotor_outer_radius=140,
                led_region=(150, 20, 250, 45),
            )
            self.assertTrue(returned.exists())
            with Image.open(returned) as webp:
                self.assertEqual(webp.n_frames, 4)

    def test_brand_save_loop_rejects_nonpositive_duration(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            source_path = root / "source.png"
            FleetArtSyntheticSource.brand_source().save(source_path)
            with self.assertRaises(ValueError):
                brand_save_loop(source_path, root / "out.webp", frame_duration_ms=0)

    def test_brand_cli_accepts_custom_geometry(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            source_path = root / "source.png"
            output_path = root / "loop.webp"
            FleetArtSyntheticSource.brand_source().save(source_path)
            subprocess.run(
                [
                    sys.executable,
                    str(TOOLS_DIR / "generate_hash_fleet_brand_loop.py"),
                    "--source", str(source_path),
                    "--output", str(output_path),
                    "--size", "48",
                    "--frames", "4",
                    "--frame-duration-ms", "50",
                    "--rotor-center", "200", "200",
                    "--rotor-inner-radius", "60",
                    "--rotor-outer-radius", "140",
                    "--led-region", "140", "10", "260", "60",
                ],
                check=True,
            )
            self.assertTrue(output_path.exists())
            with Image.open(output_path) as webp:
                self.assertEqual(webp.format, "WEBP")
                self.assertEqual(webp.n_frames, 4)
                self.assertEqual(webp.size, (48, 48))
                self.assertEqual(webp.info.get("loop"), 0, "The loop is endless")
            # Pillow's WebP decoder does not surface the ANMF duration, so verify the
            # requested 50 ms frame timing directly from the animation chunks. Per the
            # WebP container spec (RFC 9649) each ANMF frame header stores its duration
            # in the three bytes at offset 20 from the chunk tag.
            raw = output_path.read_bytes()
            durations = []
            cursor = raw.find(b"ANMF")
            while cursor != -1:
                field = raw[cursor + 20 : cursor + 23]
                if len(field) < 3:
                    break
                durations.append(field[0] | field[1] << 8 | field[2] << 16)
                cursor = raw.find(b"ANMF", cursor + 1)
            self.assertEqual(durations, [50, 50, 50, 50], "Per-frame WebP duration")


if __name__ == "__main__":
    unittest.main()
