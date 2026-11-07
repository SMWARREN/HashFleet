#!/usr/bin/env python3
"""Create a seamless transparent Hash Fleet startup loop from the approved still.

The fan rotor turns inside its fixed frame while the amber status strip breathes.
This deterministic local path preserves the supplied artwork and needs no model,
API key, or rented compute.
"""

from __future__ import annotations

import argparse
from math import cos, pi
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageFilter

DEFAULT_SIZE = 640
DEFAULT_FRAME_COUNT = 48
DEFAULT_FRAME_DURATION_MS = 42
DEFAULT_ROTOR_CENTER = (652, 660)
DEFAULT_ROTOR_INNER_RADIUS = 128
DEFAULT_ROTOR_OUTER_RADIUS = 264
DEFAULT_LED_REGION = (500, 245, 760, 290)


def _annulus_mask(
    image_size: tuple[int, int],
    center: tuple[int, int],
    inner_radius: int,
    outer_radius: int,
    feather: float = 1.0,
) -> Image.Image:
    """Select the fan blades while leaving its hub and square housing still."""
    if inner_radius <= 0 or outer_radius <= inner_radius:
        raise ValueError("Rotor radii must satisfy 0 < inner < outer")

    cx, cy = center
    outer = Image.new("L", image_size, 0)
    ImageDraw.Draw(outer).ellipse(
        (cx - outer_radius, cy - outer_radius, cx + outer_radius, cy + outer_radius),
        fill=255,
    )
    inner = Image.new("L", image_size, 255)
    ImageDraw.Draw(inner).ellipse(
        (cx - inner_radius, cy - inner_radius, cx + inner_radius, cy + inner_radius),
        fill=0,
    )
    mask = ImageChops.multiply(outer, inner)
    return mask.filter(ImageFilter.GaussianBlur(feather)) if feather > 0 else mask


def _led_mask(image: Image.Image, region: tuple[int, int, int, int]) -> Image.Image:
    """Find the bright amber status strip without changing the enclosure."""
    left, top, right, bottom = region
    if left < 0 or top < 0 or right > image.width or bottom > image.height:
        raise ValueError("LED search region must fit inside the source image")

    mask = Image.new("L", image.size, 0)
    source_pixels = image.load()
    mask_pixels = mask.load()
    for y in range(top, bottom):
        for x in range(left, right):
            red, green, blue, alpha = source_pixels[x, y]
            is_amber = red > 190 and green > 90 and blue < 110 and red > green * 1.25
            if alpha > 50 and is_amber:
                mask_pixels[x, y] = min(255, round((red - 120) * 1.9))

    if mask.getbbox() is None:
        raise ValueError("No amber status strip found in the configured LED region")
    return mask.filter(ImageFilter.GaussianBlur(0.45))


def render_frames(
    source: Image.Image,
    *,
    size: int = DEFAULT_SIZE,
    frame_count: int = DEFAULT_FRAME_COUNT,
    rotor_center: tuple[int, int] = DEFAULT_ROTOR_CENTER,
    rotor_inner_radius: int = DEFAULT_ROTOR_INNER_RADIUS,
    rotor_outer_radius: int = DEFAULT_ROTOR_OUTER_RADIUS,
    led_region: tuple[int, int, int, int] = DEFAULT_LED_REGION,
) -> list[Image.Image]:
    """Return full-canvas RGBA frames whose motion closes at one full turn."""
    if size <= 0 or frame_count < 4:
        raise ValueError("Size must be positive; use at least four frames")
    if source.mode != "RGBA":
        source = source.convert("RGBA")

    rotor_mask = _annulus_mask(
        source.size, rotor_center, rotor_inner_radius, rotor_outer_radius
    )
    led_mask = _led_mask(source, led_region)
    led_highlight_mask = led_mask.point(lambda value: round(value * 0.55))
    glow_mask = led_mask.filter(ImageFilter.GaussianBlur(14))
    frames: list[Image.Image] = []

    for index in range(frame_count):
        phase = 2 * pi * index / frame_count
        # Pillow uses positive angles for counter-clockwise rotation, so the
        # negative angle gives the fan its clockwise power-up direction.
        rotated_source = source.rotate(
            -360 * index / frame_count,
            resample=Image.Resampling.BICUBIC,
            center=rotor_center,
        )
        frame = source.copy()
        frame.paste(rotated_source, (0, 0), rotor_mask)

        pulse = 0.5 - 0.5 * cos(phase)
        brighter = ImageEnhance.Brightness(frame).enhance(1.0 + 0.14 * pulse)
        frame.paste(brighter, (0, 0), led_highlight_mask)

        bloom = Image.new("RGBA", source.size, (255, 154, 24, 0))
        bloom.putalpha(glow_mask.point(lambda value, pulse=pulse: round(value * (0.02 + 0.16 * pulse))))
        frame = Image.alpha_composite(frame, bloom)
        if frame.size != (size, size):
            frame = frame.resize((size, size), Image.Resampling.LANCZOS)
        frames.append(frame)

    return frames


def save_loop(
    source_path: Path,
    output_path: Path,
    *,
    size: int = DEFAULT_SIZE,
    frame_count: int = DEFAULT_FRAME_COUNT,
    frame_duration_ms: int = DEFAULT_FRAME_DURATION_MS,
    rotor_center: tuple[int, int] = DEFAULT_ROTOR_CENTER,
    rotor_inner_radius: int = DEFAULT_ROTOR_INNER_RADIUS,
    rotor_outer_radius: int = DEFAULT_ROTOR_OUTER_RADIUS,
    led_region: tuple[int, int, int, int] = DEFAULT_LED_REGION,
) -> Path:
    """Encode the full-color RGBA loop as a lossless animated WebP."""
    if frame_duration_ms <= 0:
        raise ValueError("Frame duration must be positive")
    with Image.open(source_path) as opened:
        source = opened.convert("RGBA")
    frames = render_frames(
        source,
        size=size,
        frame_count=frame_count,
        rotor_center=rotor_center,
        rotor_inner_radius=rotor_inner_radius,
        rotor_outer_radius=rotor_outer_radius,
        led_region=led_region,
    )
    output_path.parent.mkdir(parents=True, exist_ok=True)
    frames[0].save(
        output_path,
        format="WEBP",
        save_all=True,
        append_images=frames[1:],
        duration=frame_duration_ms,
        loop=0,
        lossless=True,
        method=6,
    )
    return output_path


def main() -> None:
    repo_root = Path(__file__).resolve().parents[1]
    default_source = (
        repo_root
        / "App/Resources/Assets.xcassets/HashFleetLaunch.imageset/"
        "LaunchMinerTransparentDark.png"
    )
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=default_source)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--size", type=int, default=DEFAULT_SIZE)
    parser.add_argument("--frames", type=int, default=DEFAULT_FRAME_COUNT)
    parser.add_argument("--frame-duration-ms", type=int, default=DEFAULT_FRAME_DURATION_MS)
    parser.add_argument(
        "--rotor-center",
        nargs=2,
        type=int,
        metavar=("X", "Y"),
        default=DEFAULT_ROTOR_CENTER,
        help="Source-image coordinates of the fan center",
    )
    parser.add_argument(
        "--rotor-inner-radius",
        type=int,
        default=DEFAULT_ROTOR_INNER_RADIUS,
        help="Keep the fan hub inside this stationary inner radius",
    )
    parser.add_argument(
        "--rotor-outer-radius",
        type=int,
        default=DEFAULT_ROTOR_OUTER_RADIUS,
        help="Rotate fan pixels inside this outer radius",
    )
    parser.add_argument(
        "--led-region",
        nargs=4,
        type=int,
        metavar=("LEFT", "TOP", "RIGHT", "BOTTOM"),
        default=DEFAULT_LED_REGION,
        help="Search rectangle for the amber status strip",
    )
    args = parser.parse_args()

    output = save_loop(
        args.source,
        args.output,
        size=args.size,
        frame_count=args.frames,
        frame_duration_ms=args.frame_duration_ms,
        rotor_center=tuple(args.rotor_center),
        rotor_inner_radius=args.rotor_inner_radius,
        rotor_outer_radius=args.rotor_outer_radius,
        led_region=tuple(args.led_region),
    )
    print(
        f"Wrote {output} ({args.frames} frames, {args.size}px, "
        f"{args.frame_duration_ms}ms/frame, lossless RGBA WebP)"
    )
    print("This local deterministic renderer uses no model, API, or cloud compute.")


if __name__ == "__main__":
    main()
