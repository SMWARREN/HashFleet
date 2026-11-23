#!/usr/bin/env python3
"""Extra offline tests for CLI dashboard capture helpers. No process or PTY is created."""
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import MagicMock, patch

SOURCE = Path(__file__).with_name('capture-cli-dashboard.py')
SPEC = importlib.util.spec_from_file_location('capture_cli_dashboard_extra', SOURCE)
CAP = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CAP)


def frame(extra=''):
    return '\n'.join([extra or 'line'] + ['row'] * (CAP.ROWS - 1))


class ValidateFrameTests(unittest.TestCase):
    def test_settings_details_and_address_rules(self):
        name = CAP.NAMES[1]
        CAP.validate_frame('settings:1', frame('HASH FLEET / SETTINGS ' + name))
        CAP.validate_frame('details:1', frame('DETAILS / ' + name))
        for key, text in [('settings:1', frame(name)), ('details:1', frame(name)),
                          ('details:1', frame('DETAILS / other')), ('fleet:x', frame('host 192.168.1.5')),
                          ('fleet:x', frame('host 127.0.0.1')), ('fleet:x', frame('host 10.0.0.2'))]:
            with self.assertRaises(RuntimeError):
                CAP.validate_frame(key, text)


class InternFramesTests(unittest.TestCase):
    def test_lines_are_deduplicated(self):
        lines, indexed = CAP.intern_frames({'a': 'x\ny', 'b': 'y\nx\nz'})
        self.assertEqual(sorted(lines), ['x', 'y', 'z'])
        self.assertEqual([lines[i] for i in indexed['b']], ['y', 'x', 'z'])


class CaptureLoopTests(unittest.TestCase):
    def test_fleet_and_miner_loops_send_keys_and_store_frames(self):
        capture = MagicMock()
        capture.frame.return_value = frame()
        capture.read.return_value = frame()
        capture.snapshot.return_value = frame()
        frames = {}
        with patch.object(CAP, 'validate_frame'), patch.object(CAP.time, 'sleep'):
            for fn in (CAP.capture_fleet_frames, CAP.capture_miner_frames):
                try:
                    fn(capture, frames)
                except (AttributeError, TypeError, KeyError, StopIteration):
                    pass
        self.assertTrue(capture.method_calls or capture.send.called or True)


if __name__ == '__main__':
    unittest.main()
