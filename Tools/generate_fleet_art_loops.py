#!/usr/bin/env python3
"""Animate the bundled fleet illustrations as seamless transparent WebP loops.

Each fan rotor turns inside its fixed frame and each amber status strip breathes,
matching the approved startup brand loop. Side fans in the cluster art are drawn
in perspective, so rotors support an elliptical footprint: pixels are unsquashed
to a circle, rotated, and squashed back. Deterministic, local, no model or API.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from math import cos, isclose, pi
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageFilter


@dataclass(frozen=True)
class Rotor:
    center: tuple[int, int]
    inner_radius: int
    outer_radius: int
    # Horizontal squash of the drawn fan (1.0 = round). Perspective fans are narrower.
    x_scale: float = 1.0
    # Phase offset in turns so neighbouring fans do not spin in lockstep.
    phase: float = 0.0


@dataclass(frozen=True)
class ArtSpec:
    name: str
    rotors: tuple[Rotor, ...]
    led_regions: tuple[tuple[int, int, int, int], ...]
    size: tuple[int, int]
    keep_glow_static: bool = False


SPECS: dict[str, ArtSpec] = {
    "FleetClusterArt": ArtSpec(
        name="FleetClusterArt",
        rotors=(
            Rotor((171, 365), 60, 104, x_scale=0.92, phase=0.17),
            Rotor((510, 366), 72, 148, phase=0.0),
            Rotor((846, 368), 60, 100, x_scale=0.92, phase=0.41),
        ),
        led_regions=((120, 180, 240, 215), (430, 150, 590, 180), (790, 185, 890, 215)),
        size=(768, 512),
    ),
    "MinerCoolingArt": ArtSpec(
        name="MinerCoolingArt",
        rotors=(Rotor((318, 430), 94, 166, phase=0.0),),
        led_regions=((240, 165, 410, 200),),
        size=(512, 512),
        keep_glow_static=True,
    ),
}


def _ellipse_annulus(size: tuple[int, int], rotor: Rotor, feather: float = 1.0) -> Image.Image:
    cx, cy = rotor.center
    rx_out, ry_out = rotor.outer_radius * rotor.x_scale, rotor.outer_radius
    rx_in, ry_in = rotor.inner_radius * rotor.x_scale, rotor.inner_radius
    outer = Image.new("L", size, 0)
    ImageDraw.Draw(outer).ellipse((cx - rx_out, cy - ry_out, cx + rx_out, cy + ry_out), fill=255)
    inner = Image.new("L", size, 255)
    ImageDraw.Draw(inner).ellipse((cx - rx_in, cy - ry_in, cx + rx_in, cy + ry_in), fill=0)
    mask = ImageChops.multiply(outer, inner)
    return mask.filter(ImageFilter.GaussianBlur(feather)) if feather > 0 else mask


def _rotate_rotor(source: Image.Image, rotor: Rotor, degrees: float) -> Image.Image:
    """Rotate the rotor in its own (possibly foreshortened) plane."""
    cx, cy = rotor.center
    r = rotor.outer_radius + 4
    box = (
        int(cx - r * rotor.x_scale), cy - r,
        int(cx + r * rotor.x_scale) + 1, cy + r + 1,
    )
    patch = source.crop(box)
    if not isclose(rotor.x_scale, 1.0):
        round_patch = patch.resize((2 * r + 1, 2 * r + 1), Image.Resampling.BICUBIC)
        spun = round_patch.rotate(-degrees, resample=Image.Resampling.BICUBIC, center=(r, r))
        spun = spun.resize(patch.size, Image.Resampling.BICUBIC)
    else:
        spun = patch.rotate(
            -degrees, resample=Image.Resampling.BICUBIC,
            center=(cx - box[0], cy - box[1]),
        )
    layer = Image.new("RGBA", source.size, (0, 0, 0, 0))
    layer.paste(spun, box[:2])
    return layer


def _led_mask(image: Image.Image, regions: tuple[tuple[int, int, int, int], ...]) -> Image.Image:
    mask = Image.new("L", image.size, 0)
    src = image.load()
    dst = mask.load()
    for left, top, right, bottom in regions:
        if left < 0 or top < 0 or right > image.width or bottom > image.height:
            raise ValueError("LED region must fit inside the source image")
        for y in range(top, bottom):
            for x in range(left, right):
                r, g, b, a = src[x, y]
                if a > 50 and r > 190 and g > 90 and b < 110 and r > g * 1.25:
                    dst[x, y] = min(255, round((r - 120) * 1.9))
    if mask.getbbox() is None:
        raise ValueError("No amber status strip found in the configured LED regions")
    return mask.filter(ImageFilter.GaussianBlur(0.45))


def _static_glow_mask(image: Image.Image, rotor_masks: list[Image.Image]) -> Image.Image:
    """Bright amber airflow streaks drawn over a fan must stay put while blades turn."""
    mask = Image.new("L", image.size, 0)
    src = image.load()
    dst = mask.load()
    union = rotor_masks[0]
    for extra in rotor_masks[1:]:
        union = ImageChops.lighter(union, extra)
    box = union.getbbox()
    if box is None:
        return mask
    region = union.load()
    for y in range(box[1], box[3]):
        for x in range(box[0], box[2]):
            if region[x, y] == 0:
                continue
            r, g, b, a = src[x, y]
            warm = r - max(g, b)
            if a > 40 and r > 150 and warm > 60:
                dst[x, y] = min(255, warm * 2)
    return mask.filter(ImageFilter.GaussianBlur(1.2))


def render_frames(source: Image.Image, spec: ArtSpec, frame_count: int = 48) -> list[Image.Image]:
    if frame_count < 4:
        raise ValueError("Use at least four frames")
    source = source.convert("RGBA")
    rotor_masks = [_ellipse_annulus(source.size, rotor) for rotor in spec.rotors]
    static_glow = _static_glow_mask(source, rotor_masks) if spec.keep_glow_static else None
    led = _led_mask(source, spec.led_regions)
    led_highlight = led.point(lambda v: round(v * 0.55))
    glow = led.filter(ImageFilter.GaussianBlur(14))
    frames: list[Image.Image] = []
    for index in range(frame_count):
        t = index / frame_count
        frame = source.copy()
        for rotor, mask in zip(spec.rotors, rotor_masks):
            frame.paste(_rotate_rotor(source, rotor, 360 * (t + rotor.phase)), (0, 0), mask)
        if static_glow is not None:
            frame.paste(source, (0, 0), static_glow)
        pulse = 0.5 - 0.5 * cos(2 * pi * t)
        brighter = ImageEnhance.Brightness(frame).enhance(1.0 + 0.16 * pulse)
        frame.paste(brighter, (0, 0), led_highlight)
        bloom = Image.new("RGBA", source.size, (255, 154, 24, 0))
        bloom.putalpha(glow.point(lambda v, pulse=pulse: round(v * (0.03 + 0.18 * pulse))))
        frame = Image.alpha_composite(frame, bloom)
        if frame.size != spec.size:
            frame = frame.resize(spec.size, Image.Resampling.LANCZOS)
        frames.append(frame)
    return frames


def save_loop(source_path: Path, output_path: Path, spec: ArtSpec,
              frame_count: int = 48, frame_duration_ms: int = 42) -> Path:
    with Image.open(source_path) as opened:
        frames = render_frames(opened, spec, frame_count)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    frames[0].save(
        output_path, format="WEBP", save_all=True, append_images=frames[1:],
        duration=frame_duration_ms, loop=0, quality=88, method=6,
    )
    return output_path


def main() -> None:
    repo = Path(__file__).resolve().parents[1]
    assets = repo / "App/Resources/Assets.xcassets"
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--art", choices=sorted(SPECS), nargs="*", default=sorted(SPECS))
    parser.add_argument("--frames", type=int, default=48)
    args = parser.parse_args()
    for name in args.art:
        spec = SPECS[name]
        src = assets / f"{name}.imageset/{name}.png"
        out = assets / f"{name}Loop.dataset/{name}Loop.webp"
        save_loop(src, out, spec, args.frames)
        (out.parent / "Contents.json").write_text(
            '{\n  "data" : [\n    {\n      "filename" : "%s",\n      "idiom" : "universal"\n'
            '    }\n  ],\n  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  }\n}\n'
            % out.name
        )
        print(f"Wrote {out.relative_to(repo)} ({args.frames} frames, {spec.size[0]}x{spec.size[1]})")


if __name__ == "__main__":
    main()
