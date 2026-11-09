#!/usr/bin/env python3
"""Validate and stage an animated WebP in Hash Fleet's bundled data set.

This is the handoff between 3dicon's output and the app. It never calls a
generation API. Replacing the current splash loop requires the explicit
``--replace`` flag so a generated candidate cannot silently overwrite artwork.
"""

from __future__ import annotations

import argparse
import os
import shutil
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageChops


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT = (
    REPO_ROOT
    / "App/Resources/Assets.xcassets/HashFleetBrandLoop.dataset/HashFleetBrandLoop.webp"
)


@dataclass(frozen=True)
class WebPInfo:
    width: int
    height: int
    frames: int
    loop: int
    duration_ms: int
    has_alpha: bool
    has_motion: bool


def inspect_webp(path: Path) -> WebPInfo:
    """Reject invalid, static, opaque, or non-looping candidates before import."""
    try:
        image = Image.open(path)
    except OSError as error:
        raise ValueError(f"cannot read image: {error}") from error

    with image:
        if image.format != "WEBP":
            raise ValueError("input must be an animated WebP")
        frames = getattr(image, "n_frames", 1)
        if frames < 2:
            raise ValueError("WebP must contain at least two frames")
        loop = image.info.get("loop")
        if loop != 0:
            raise ValueError("WebP must declare an infinite loop (loop=0)")

        first_frame: Image.Image | None = None
        all_frames_have_alpha = True
        has_motion = False
        total_duration = 0
        for index in range(frames):
            image.seek(index)
            frame = image.convert("RGBA")
            alpha = frame.getchannel("A")
            low, high = alpha.getextrema()
            all_frames_have_alpha &= low < 255 and high > 0
            total_duration += max(0, int(image.info.get("duration", 0)))

            if index == 0:
                first_frame = frame.copy()
            elif first_frame is not None and not has_motion:
                delta = ImageChops.difference(
                    first_frame.convert("RGB"), frame.convert("RGB")
                )
                has_motion = delta.getbbox() is not None

        if not all_frames_have_alpha:
            raise ValueError("every WebP frame must retain real transparency")
        if not has_motion:
            raise ValueError("WebP frames are identical; expected visible motion")
        if total_duration <= 0:
            raise ValueError("WebP frame timing is missing or zero")

        return WebPInfo(
            width=image.width,
            height=image.height,
            frames=frames,
            loop=loop,
            duration_ms=total_duration,
            has_alpha=all_frames_have_alpha,
            has_motion=has_motion,
        )


def import_webp(source: Path, output: Path, *, replace: bool = False) -> WebPInfo:
    """Validate and atomically copy a candidate, requiring explicit overwrite."""
    source = source.expanduser().resolve(strict=True)
    output = output.expanduser().resolve()
    info = inspect_webp(source)

    if source == output:
        return info
    if output.exists() and not replace:
        raise FileExistsError(
            f"{output} already exists; inspect the candidate, then pass --replace to overwrite"
        )

    output.parent.mkdir(parents=True, exist_ok=True)
    temp_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            prefix=f".{output.name}.", suffix=".tmp", dir=output.parent, delete=False
        ) as temp:
            temp_path = Path(temp.name)
        shutil.copyfile(source, temp_path)
        os.replace(temp_path, output)
    finally:
        if temp_path is not None:
            temp_path.unlink(missing_ok=True)
    return info


def describe(path: Path, info: WebPInfo) -> str:
    return (
        f"{path}: {info.width}x{info.height}, {info.frames} frames, "
        f"{info.duration_ms}ms total, loop={info.loop}, alpha=yes, motion=yes"
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("candidate", type=Path, help="3dicon animated WebP candidate")
    parser.add_argument(
        "--output",
        type=Path,
        default=DEFAULT_OUTPUT,
        help=f"destination Data Set asset (default: {DEFAULT_OUTPUT})",
    )
    parser.add_argument(
        "--dry-run", action="store_true", help="validate and print metadata without copying"
    )
    parser.add_argument(
        "--replace", action="store_true", help="explicitly replace an existing output asset"
    )
    args = parser.parse_args(argv)

    try:
        candidate = args.candidate.expanduser().resolve(strict=True)
        info = inspect_webp(candidate) if args.dry_run else import_webp(
            candidate, args.output, replace=args.replace
        )
    except (OSError, ValueError) as error:
        print(f"Cannot import 3dicon WebP: {error}", file=sys.stderr)
        return 2

    destination = candidate if args.dry_run else args.output.expanduser().resolve()
    print(describe(destination, info))
    if args.dry_run:
        print("Dry run only. No files changed.")
    elif destination == candidate:
        print("Candidate already is the destination. No copy needed.")
    else:
        print("Validated and imported into the Hash Fleet asset Data Set.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
