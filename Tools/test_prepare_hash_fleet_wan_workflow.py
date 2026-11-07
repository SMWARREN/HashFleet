import json
import tempfile
import unittest
from pathlib import Path

from PIL import Image

from prepare_hash_fleet_wan_workflow import (
    BACKING_RGB,
    configure_workflow,
    make_reference_image,
)


def sample_workflow():
    node_specs = {
        78: ("CLIPTextEncode", ["existing negative"]),
        80: ("LoadImage", ["start.png", "image"]),
        81: ("WanFirstLastFrameToVideo", [640, 640, 81, 1]),
        83: ("SaveVideo", ["video/ComfyUI", "auto", "auto"]),
        86: ("CreateVideo", [16]),
        89: ("LoadImage", ["end.png", "image"]),
        90: ("CLIPTextEncode", ["old prompt"]),
    }
    return {
        "nodes": [
            {"id": node_id, "type": node_type, "mode": 0, "widgets_values": values}
            for node_id, (node_type, values) in node_specs.items()
        ],
        "links": [],
    }


class PrepareWanWorkflowTests(unittest.TestCase):
    def test_transparent_source_is_centered_over_neutral_backing(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            source = root / "source.png"
            output = root / "reference.png"
            image = Image.new("RGBA", (40, 20), (0, 0, 0, 0))
            image.paste((230, 120, 20, 255), (5, 3, 35, 17))
            image.save(source)

            make_reference_image(source, output, size=64, object_fill=0.5)

            result = Image.open(output).convert("RGB")
            self.assertEqual(result.size, (64, 64))
            self.assertEqual(result.getpixel((0, 0)), BACKING_RGB)
            self.assertEqual(result.getpixel((32, 32)), (230, 120, 20))

    def test_workflow_uses_same_reference_as_both_loop_endpoints(self):
        configured = configure_workflow(sample_workflow(), frames=49, fps=16)
        by_id = {node["id"]: node for node in configured["nodes"]}

        self.assertEqual(by_id[80]["widgets_values"][0], "HashFleetReference.png")
        self.assertEqual(by_id[89]["widgets_values"][0], "HashFleetReference.png")
        self.assertEqual(by_id[81]["widgets_values"], [640, 640, 49, 1])
        self.assertEqual(by_id[86]["widgets_values"][0], 16)
        self.assertEqual(by_id[83]["widgets_values"][0], "hash_fleet/wan22-flf2v")
        self.assertIn("cooling fan rotor", by_id[90]["widgets_values"][0])
        self.assertIn("existing negative", by_id[78]["widgets_values"][0])
        self.assertIn("camera movement", by_id[78]["widgets_values"][0])

    def test_rejects_non_loop_frame_counts_and_changed_template_nodes(self):
        invalid_frames_workflow = sample_workflow()
        with self.assertRaises(ValueError):
            configure_workflow(invalid_frames_workflow, frames=48)

        workflow = sample_workflow()
        workflow["nodes"][0]["type"] = "UnexpectedNode"
        with self.assertRaises(ValueError):
            configure_workflow(workflow)

    def test_configured_workflow_remains_valid_json(self):
        encoded = json.dumps(configure_workflow(sample_workflow()), ensure_ascii=False)
        self.assertEqual(json.loads(encoded)["links"], [])


if __name__ == "__main__":
    unittest.main()
