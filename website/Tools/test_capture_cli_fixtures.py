#!/usr/bin/env python3
"""Offline tests for the CLI fixture normalizers. No process, PTY or socket is used."""
import importlib.util
import json
from pathlib import Path
import unittest

SOURCE = Path(__file__).with_name('capture-cli-fixtures.py')
SPEC = importlib.util.spec_from_file_location('capture_cli_fixtures', SOURCE)
FIX = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(FIX)

PORTS = {'127.0.0.1:5001': FIX.ALIASES[0], '127.0.0.1:5002': FIX.ALIASES[1], '127.0.0.1:5003': FIX.ALIASES[2]}


class NormalizeJsonTests(unittest.TestCase):
    def payload(self, addresses):
        return json.dumps({'observedAt': 'now', 'miners': [
            {'device': {'address': a, 'name': 'x', 'id': 'y'}, 'observedAt': 'then'} for a in addresses]})

    def test_stable_ids_names_and_order(self):
        out = json.loads(FIX.normalize_json(self.payload(['127.0.0.1:5003', '127.0.0.1:5001']), PORTS))
        names = [m['device']['name'] for m in out['miners']]
        self.assertEqual(names, sorted(names, key=str.casefold))
        self.assertEqual(out['observedAt'], '2026-01-01T12:00:00Z')
        self.assertTrue(all(m['observedAt'] == '2026-01-01T12:00:00Z' for m in out['miners']))
        self.assertTrue(out['miners'][0]['device']['id'].startswith('00000000-0000-4000-8000-'))

    def test_unknown_authority_rejected(self):
        with self.assertRaises(RuntimeError):
            FIX.normalize_json(self.payload(['127.0.0.1:9999']), PORTS)


class NormalizeTableTests(unittest.TestCase):
    def row(self, authority):
        cols = [f'{authority:<20}', f'{"fixture":<28}', f'{"a":<14}', f'{"b":<10}', f'{"c":<10}', f'{"d":<14}', f'{"e":<16}', 'tail']
        return ' '.join(cols)

    def test_rows_are_rewritten_and_sorted(self):
        text = '\n'.join(['h1', 'h2', 'h3', self.row('127.0.0.1:5003'), 'detail-3', self.row('127.0.0.1:5001'), 'detail-1'])
        out = FIX.normalize_table(text, PORTS).splitlines()
        self.assertEqual(out[:3], ['h1', 'h2', 'h3'])
        self.assertTrue(out[3].startswith(min(FIX.NAMES[0], FIX.NAMES[2], key=str.casefold)))
        self.assertIn('detail-1', out)
        self.assertIn(FIX.ALIASES[2], '\n'.join(out))

    def test_bad_rows_rejected(self):
        with self.assertRaises(RuntimeError):
            FIX.normalize_table('a\nb\nc\n127.0.0.1:1 short', PORTS)
        with self.assertRaises(RuntimeError):
            FIX.normalize_table('a\nb\nc\n' + self.row('127.0.0.1:7777'), PORTS)


class NormalizeTtyTests(unittest.TestCase):
    def test_groups_rows_and_footer(self):
        lines = ['HEADER 127.0.0.1:5001']
        for host in PORTS:
            lines.append(f' {host:<23} ONLINE \x1b[32mok\x1b[0m')
            lines.append('  detail ' + host)
        lines.append('FOOTER')
        out = FIX.normalize_tty('\n'.join(lines), PORTS)
        self.assertEqual(out['footer'], 'FOOTER')
        self.assertEqual(set(out['miners']), set(FIX.ALIASES))
        self.assertIn(FIX.ALIASES[0], out['header'])
        self.assertNotIn('127.0.0.1', json.dumps(out))

    def test_requires_three_rows(self):
        with self.assertRaises(RuntimeError):
            FIX.normalize_tty('only header\nfooter', PORTS)


if __name__ == '__main__':
    unittest.main()
