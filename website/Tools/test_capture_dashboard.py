#!/usr/bin/env python3
"""Offline dashboard capture validation tests. Never launch the CLI or open a PTY."""
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

SOURCE = Path(__file__).with_name('capture-cli-dashboard.py')
SPEC = importlib.util.spec_from_file_location('capture_cli_dashboard', SOURCE)
CAPTURE = importlib.util.module_from_spec(SPEC)
with patch('subprocess.Popen', side_effect=AssertionError('Native processes forbidden')):
    SPEC.loader.exec_module(CAPTURE)


class CaptureValidationTests(unittest.TestCase):
    def setUp(self):
        self.process_fence = patch('subprocess.Popen', side_effect=AssertionError('Native processes forbidden'))
        self.process_fence.start()
        self.addCleanup(self.process_fence.stop)
        self.pty_fence = patch.object(CAPTURE.pty, 'openpty', side_effect=AssertionError('PTY creation forbidden'))
        self.pty_fence.start()
        self.addCleanup(self.pty_fence.stop)

    def test_accepts_complete_fleet_frame_and_sgr_styles(self):
        complete = '\n'.join(['\x1b[1mHASH FLEET\x1b[0m'] + ['sample'] * (CAPTURE.ROWS - 1))
        self.assertIsNone(CAPTURE.validate_frame('fleet:name:0:0', complete))

    def test_rejects_short_and_long_frames(self):
        for count in (0, CAPTURE.ROWS - 1, CAPTURE.ROWS + 1):
            content = '\n'.join(['sample'] * count)
            with self.subTest(count=count), self.assertRaisesRegex(RuntimeError, 'Incomplete fleet'):
                CAPTURE.validate_frame('fleet:name:0:0', content)

    def test_accepts_details_and_settings_for_each_selected_miner(self):
        for miner, name in enumerate(CAPTURE.NAMES):
            for screen, header in [('details', 'DETAILS / Mining'), ('settings', 'HASH FLEET / SETTINGS')]:
                with self.subTest(screen=screen, miner=miner):
                    content = '\n'.join([header, name] + ['sample'] * (CAPTURE.ROWS - 2))
                    self.assertIsNone(CAPTURE.validate_frame(f'{screen}:{miner}:1', content))

    def test_rejects_missing_settings_heading(self):
        content = '\n'.join(['wrong heading', CAPTURE.NAMES[0]] + ['sample'] * (CAPTURE.ROWS - 2))
        with self.assertRaisesRegex(RuntimeError, 'Missing settings page'):
            CAPTURE.validate_frame('settings:0:1', content)

    def test_rejects_missing_details_heading(self):
        content = '\n'.join(['wrong heading', CAPTURE.NAMES[0]] + ['sample'] * (CAPTURE.ROWS - 2))
        with self.assertRaisesRegex(RuntimeError, 'Missing details page'):
            CAPTURE.validate_frame('details:0:1', content)

    def test_rejects_wrong_selected_miner(self):
        for screen, header in [('details', 'DETAILS / Mining'), ('settings', 'HASH FLEET / SETTINGS')]:
            content = '\n'.join([header, CAPTURE.NAMES[1]] + ['sample'] * (CAPTURE.ROWS - 2))
            with self.subTest(screen=screen), self.assertRaisesRegex(RuntimeError, 'Wrong selected miner'):
                CAPTURE.validate_frame(f'{screen}:0:1', content)

    def test_rejects_non_demo_addresses(self):
        for address in ('192.168.1.1', '127.0.0.1', '10.20.30.40'):
            content = '\n'.join(['HASH FLEET', address] + ['sample'] * (CAPTURE.ROWS - 2))
            with self.subTest(address=address), self.assertRaisesRegex(RuntimeError, 'Unexpected non-demo address'):
                CAPTURE.validate_frame('fleet:name:0:0', content)

    def test_empty_interning_has_no_lines_or_frames(self):
        self.assertEqual(CAPTURE.intern_frames({}), ([], {}))

    def test_interning_reuses_equal_lines_in_first_seen_order(self):
        lines, indexed = CAPTURE.intern_frames({'first': 'same\nother\nsame', 'second': 'other\nnew'})
        self.assertEqual(lines, ['same', 'other', 'new'])
        self.assertEqual(indexed, {'first': [0, 1, 0], 'second': [1, 2]})

    def test_interning_losslessly_round_trips_styles_spaces_unicode_and_empty_lines(self):
        frames = {'first': '\x1b[31m▀▄\x1b[0m  \n\nplain\r\n', 'second': '\n\x1b[31m▀▄\x1b[0m  ', 'empty': ''}
        lines, indexed = CAPTURE.intern_frames(frames)
        restored = {key: '\n'.join(lines[index] for index in ids) for key, ids in indexed.items()}
        self.assertEqual(restored, frames)
        self.assertEqual(len(lines), len(set(lines)))


if __name__ == '__main__':
    unittest.main(verbosity=2)
