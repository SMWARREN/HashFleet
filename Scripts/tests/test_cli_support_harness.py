#!/usr/bin/env python3
"""Deterministic regression checks for fragmented PTY frame synchronization."""
import unittest

import test_cli_dashboard as dashboard
import test_cli_interactive_support as support


class FragmentedTerminal:
    def __init__(self, chunks=(), initial=b""):
        self.output = initial
        self.chunks = iter(chunks)
        self.reads = 0

    def drain(self, _seconds):
        self.reads += 1
        self.output += next(self.chunks, b"")


class SupportHarnessTests(unittest.TestCase):
    def waiter(self):
        return support.InteractiveSupportTests(
            "test_help_and_supported_dashboard_sizes_advertise_support"
        )

    def test_waits_for_footer_when_header_arrives_in_an_earlier_read(self):
        terminal = FragmentedTerminal([
            b"\x1b[HHASH FLEET / SUPPORT\r\n",
            b"content\r\nq quit\x1b[J",
        ])
        self.waiter().wait(terminal, "HASH FLEET / SUPPORT")
        self.assertEqual(terminal.reads, 2)
        self.assertIn(b"q quit\x1b[J", terminal.output)

    def test_older_terminator_cannot_complete_the_newest_partial_frame(self):
        terminal = FragmentedTerminal(
            [b"", b"content\r\nq quit\x1b[J"],
            initial=b"\x1b[Hdashboard q quit\x1b[J\x1b[HHASH FLEET / SUPPORT\r\n",
        )
        self.waiter().wait(terminal, "HASH FLEET / SUPPORT")
        self.assertEqual(terminal.reads, 2)

    def test_pretransition_frame_cannot_satisfy_the_requested_offset(self):
        terminal = FragmentedTerminal(
            initial=b"\x1b[HHASH FLEET / SUPPORT\r\nq quit\x1b[J"
        )
        waiter = self.waiter()
        offset = len(terminal.output)
        with self.assertRaisesRegex(AssertionError, "Missing public UI label"):
            waiter.wait(terminal, "HASH FLEET / SUPPORT", after=offset, timeout=0.01)

    def test_requested_label_must_belong_to_the_newest_complete_frame(self):
        terminal = FragmentedTerminal(
            initial=(b"\x1b[HHASH FLEET / SUPPORT\r\nq quit\x1b[J"
                     b"\x1b[Hdashboard q quit\x1b[J")
        )
        waiter = self.waiter()
        with self.assertRaisesRegex(AssertionError, "Missing public UI label"):
            waiter.wait(terminal, "HASH FLEET / SUPPORT", timeout=0.01)


class TerminalFrameHarnessTests(unittest.TestCase):
    def test_frame_waits_for_its_own_footer_and_complete_utf8(self):
        terminal = FragmentedTerminal(
            [b"\x86\x93/jk\r\n", b"q quit\x1b[J"], initial=b"\x1b[HAT A GLANCE\r\n\xe2"
        )
        frame = dashboard.Terminal.frame(terminal)
        self.assertEqual(terminal.reads, 2)
        self.assertEqual(frame, "AT A GLANCE\n\u2193/jk\nq quit")

    def test_frame_never_falls_back_to_a_stale_completed_screen(self):
        terminal = FragmentedTerminal(
            initial=b"\x1b[Hold q quit\x1b[J\x1b[Hnew incomplete"
        )
        with self.assertRaisesRegex(AssertionError, "Newest CLI frame is incomplete"):
            dashboard.Terminal.frame(terminal, timeout=0.01)

    def test_frame_rejects_an_unfinished_terminator(self):
        terminal = FragmentedTerminal([b"J"], initial=b"\x1b[Hq quit\x1b[")
        self.assertEqual(dashboard.Terminal.frame(terminal), "q quit")
        self.assertEqual(terminal.reads, 1)

    def test_snapshot_without_screen_controls_is_unchanged(self):
        terminal = FragmentedTerminal(initial=b"HASH FLEET\r\nSTATUS\r\n")
        self.assertEqual(dashboard.Terminal.frame(terminal), "HASH FLEET\nSTATUS\n")
        self.assertEqual(terminal.reads, 0)

    def test_parser_requires_a_frame_start_at_the_requested_offset(self):
        output = b"\x1b[Hq quit\x1b[J"
        self.assertIsNone(dashboard.newest_complete_frame(output, after=1))
        self.assertIsNone(dashboard.newest_complete_frame(output, after=len(output)))


if __name__ == "__main__":
    unittest.main(verbosity=2)
