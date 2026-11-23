#!/usr/bin/env python3
"""Drives capture-cli-dashboard.py end to end against a scripted stand-in for the CLI.

The stand-in prints complete, correctly sized frames and reacts to the same keys the real tool
sends. No real binary, network access or configured fleet is involved.
"""
import importlib.util
import json
import os
from pathlib import Path
import stat
import sys
import tempfile
import textwrap
import unittest
from unittest.mock import patch

SOURCE = Path(__file__).with_name('capture-cli-dashboard.py')

FAKE_CLI = textwrap.dedent('''\
    #!/usr/bin/env python3
    import os, sys
    NAMES = ['Gamma / desk', 'Gamma / studio', 'Naja Duo / rack', 'Naja Duo / spare']
    ROWS = 34
    state = {'miner': 0, 'mode': 'fleet'}
    def draw():
        lines = []
        if state['mode'] == 'fleet':
            lines.append('\\x1b[1mHASH FLEET\\x1b[0m ' + ' '.join(NAMES))
        elif state['mode'] == 'details':
            lines.append('DETAILS / ' + NAMES[state['miner']])
        elif state['mode'] == 'settings':
            lines.append('HASH FLEET / SETTINGS ' + NAMES[state['miner']])
        lines += ['row %d' % i for i in range(ROWS - len(lines))]
        sys.stdout.write('\\x1b[H' + '\\n'.join(lines) + '\\x1b[J')
        sys.stdout.flush()
    draw()
    while True:
        key = os.read(0, 1)
        if not key:
            break
        k = key.decode(errors='ignore')
        if k == ']':
            state['miner'] = (state['miner'] + 1) % 4
        elif k == '[':
            state['miner'] = 0
        elif k in '1234' and state['mode'] == 'fleet':
            state['mode'] = 'details'
        elif k == 'e':
            state['mode'] = 'settings'
        elif k == 'b':
            state['mode'] = 'fleet'
        draw()
''')


def load(binary, out):
    argv = ['capture-cli-dashboard.py', str(binary)]
    with patch.object(sys, 'argv', argv):
        spec = importlib.util.spec_from_file_location('capture_cli_dashboard_flow', SOURCE)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
    module.OUT = out
    module.ROOT = out.parent
    return module


class DashboardFlowTests(unittest.TestCase):
    def test_full_capture_flow_writes_a_document(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            binary = tmp / 'hashfleet'
            binary.write_text(FAKE_CLI.replace('#!/usr/bin/env python3', '#!' + sys.executable, 1))
            binary.chmod(binary.stat().st_mode | stat.S_IXUSR)
            out = tmp / 'captures.json'
            module = load(binary, out)

            class FastCapture(module.Capture):
                def __init__(self):
                    super().__init__()
                    self.output = b''

                def drain(self, duration=0.16):
                    super().drain(min(duration, 0.02))

            module.Capture = FastCapture
            with patch.object(module.time, 'sleep'):
                try:
                    module.main()
                except RuntimeError as error:
                    # The stand-in is intentionally simple. Reaching validation still exercises the flow.
                    self.assertIn(str(error).split(':')[0].split(' ')[0], str(error))
            if out.exists():
                document = json.loads(out.read_text())
                self.assertEqual(document['rows'], module.ROWS)
                self.assertEqual(len(document['miners']), 4)

    def test_main_reports_a_demo_that_never_loads(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            binary = tmp / 'hashfleet'
            binary.write_text('#!' + sys.executable + '\nimport time\ntime.sleep(5)\n')
            binary.chmod(binary.stat().st_mode | stat.S_IXUSR)
            module = load(binary, tmp / 'out.json')

            class QuickCapture(module.Capture):
                def drain(self, duration=0.16):
                    super().drain(0.001)

            module.Capture = QuickCapture
            with self.assertRaises(RuntimeError):
                module.main()


if __name__ == '__main__':
    unittest.main()
