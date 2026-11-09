#!/usr/bin/env python3
"""Prepare the Hash Fleet still and a ComfyUI Wan 2.2 FLF2V UI workflow.

This only prepares local files. It does not call a model API, start ComfyUI,
download model weights, or rent cloud compute.
"""

from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path
from typing import Any

from PIL import Image


BACKING_RGB = (158, 158, 158)
OBJECT_FILL = 0.68
REFERENCE_FILENAME = "HashFleetReference.png"

# Draft prompt for a first low-resolution pass. Keep the body motion specific
# to the fan, with the camera and enclosure anchored so the loop stays legible.
DEFAULT_MOTION_PROMPT = (
    "Front-facing, locked camera view of the supplied amber-gold mining device. "
    "The existing cooling fan rotor turns smoothly clockwise at a calm, steady "
    "speed. The narrow amber status strip gently brightens and dims, then returns "
    "to its starting brightness. Keep the metal enclosure, vents, screws, feet, "
    "background and camera fixed in place. The fan and status light end on the "
    "same phase as the opening frame to form a clean loop."
)

NEGATIVE_MOTION = (
    "camera movement, pan, zoom, perspective change, whole-device rotation, "
    "translation, drifting, altered enclosure, extra objects, extra text, "
    "watermarks, flicker, duplicate fan blades, deformed case"
)

# Node IDs and types in the official Comfy-Org FLF2V template. Validate each
# pair before editing so a changed upstream template fails closed.
REQUIRED_NODES = {
    78: "CLIPTextEncode",  # negative prompt
    80: "LoadImage",       # starting frame
    81: "WanFirstLastFrameToVideo",
    83: "SaveVideo",
    86: "CreateVideo",
    89: "LoadImage",       # ending frame
    90: "CLIPTextEncode",  # positive prompt
}


def make_reference_image(
    source_path: Path,
    output_path: Path,
    size: int = 640,
    object_fill: float = OBJECT_FILL,
) -> None:
    """Flatten transparent launch art onto 3dicon's neutral matting backing."""
    if size <= 0:
        raise ValueError("Image size must be positive")
    if not 0 < object_fill <= 1:
        raise ValueError("Object fill must be in the interval (0, 1]")

    source = Image.open(source_path).convert("RGBA")
    alpha_bounds = source.getchannel("A").getbbox()
    if alpha_bounds is None:
        raise ValueError(f"Source art has no visible pixels: {source_path}")

    subject = source.crop(alpha_bounds)
    scale = size * object_fill / max(subject.size)
    scaled_size = (
        max(1, round(subject.width * scale)),
        max(1, round(subject.height * scale)),
    )
    subject = subject.resize(scaled_size, Image.LANCZOS)

    canvas = Image.new("RGBA", (size, size), BACKING_RGB + (255,))
    canvas.alpha_composite(
        subject,
        ((size - subject.width) // 2, (size - subject.height) // 2),
    )
    output_path.parent.mkdir(parents=True, exist_ok=True)
    canvas.convert("RGB").save(output_path, format="PNG")


def _node_by_id(workflow: dict[str, Any], node_id: int, expected_type: str) -> dict[str, Any]:
    matches = [node for node in workflow.get("nodes", []) if node.get("id") == node_id]
    if len(matches) != 1:
        raise ValueError(f"Expected exactly one workflow node {node_id}, found {len(matches)}")
    node = matches[0]
    if node.get("type") != expected_type:
        raise ValueError(
            f"Workflow node {node_id} changed type: expected {expected_type}, "
            f"found {node.get('type')}"
        )
    if node.get("mode", 0) != 0:
        raise ValueError(f"Workflow node {node_id} is disabled")
    return node


def configure_workflow(
    workflow: dict[str, Any],
    image_filename: str = REFERENCE_FILENAME,
    size: int = 640,
    frames: int = 49,
    fps: int = 16,
    motion_prompt: str = DEFAULT_MOTION_PROMPT,
) -> dict[str, Any]:
    """Return a patched copy of the official ComfyUI UI-format workflow."""
    if size <= 0 or size % 16 != 0:
        raise ValueError("Wan width and height must be positive multiples of 16")
    if frames < 5 or (frames - 1) % 4 != 0:
        raise ValueError("Wan first/last-frame length must be 4n+1 and at least 5")
    if fps <= 0:
        raise ValueError("Video frame rate must be positive")
    if not image_filename or Path(image_filename).name != image_filename:
        raise ValueError("Image filename must be a simple name inside ComfyUI's input folder")

    configured = copy.deepcopy(workflow)
    nodes = {
        node_id: _node_by_id(configured, node_id, node_type)
        for node_id, node_type in REQUIRED_NODES.items()
    }

    for node_id in (80, 89):
        nodes[node_id]["widgets_values"] = [image_filename, "image"]

    nodes[81]["widgets_values"][:3] = [size, size, frames]
    nodes[86]["widgets_values"][0] = fps
    nodes[83]["widgets_values"][0] = "hash_fleet/wan22-flf2v"
    nodes[90]["widgets_values"][0] = motion_prompt

    negative_values = nodes[78]["widgets_values"]
    existing_negative = str(negative_values[0]).strip()
    negative_values[0] = f"{existing_negative}, {NEGATIVE_MOTION}" if existing_negative else NEGATIVE_MOTION
    return configured


def prepare(
    workflow_path: Path,
    source_path: Path,
    output_dir: Path,
    size: int = 640,
    frames: int = 49,
    fps: int = 16,
    motion_prompt: str = DEFAULT_MOTION_PROMPT,
) -> tuple[Path, Path]:
    workflow = json.loads(workflow_path.read_text(encoding="utf-8"))
    output_dir.mkdir(parents=True, exist_ok=True)

    reference_path = output_dir / REFERENCE_FILENAME
    make_reference_image(source_path, reference_path, size=size)

    configured = configure_workflow(
        workflow,
        image_filename=REFERENCE_FILENAME,
        size=size,
        frames=frames,
        fps=fps,
        motion_prompt=motion_prompt,
    )
    output_workflow = output_dir / "hash_fleet_wan22_flf2v.json"
    output_workflow.write_text(
        json.dumps(configured, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    return reference_path, output_workflow


def main() -> None:
    repo_root = Path(__file__).resolve().parents[1]
    default_source = (
        repo_root
        / "App/Resources/Assets.xcassets/HashFleetLaunch.imageset/"
        "LaunchMinerTransparentDark.png"
    )
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workflow", type=Path, required=True, help="Official FLF2V UI-format JSON")
    parser.add_argument("--source", type=Path, default=default_source, help="Transparent Hash Fleet PNG")
    parser.add_argument("--output-dir", type=Path, required=True, help="Scratch folder for image and patched JSON")
    parser.add_argument("--size", type=int, default=640, help="Square Wan render size, multiple of 16")
    parser.add_argument("--frames", type=int, default=49, help="Frame count, 4n+1, default 49")
    parser.add_argument("--fps", type=int, default=16, help="ComfyUI output frame rate")
    parser.add_argument("--motion", default=DEFAULT_MOTION_PROMPT, help="Physical motion prompt")
    args = parser.parse_args()

    reference, workflow = prepare(
        args.workflow,
        args.source,
        args.output_dir,
        size=args.size,
        frames=args.frames,
        fps=args.fps,
        motion_prompt=args.motion,
    )
    print(f"Prepared neutral-backed reference: {reference}")
    print(f"Prepared ComfyUI workflow: {workflow}")
    print(f"Upload {reference.name} to ComfyUI's input folder, then import the patched workflow.")
    print("No model was run and no API, cloud instance, or billing action was used.")


if __name__ == "__main__":
    main()
