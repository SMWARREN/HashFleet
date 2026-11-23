#!/usr/bin/env python3
"""Additional offline release tests. subprocess, gh and the network are always mocked."""
import hashlib
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import release as r

SHA = 'a' * 40
HASH = 'b' * 64
CASK = '  version "1.0.0"\n  sha256 "' + 'c' * 64 + '"\n  url "https://github.com/SMWARREN/HashFleet/releases/download/v#{version}/HashFleet-#{version}-macos-arm64.zip"\n'
FORMULA = '  url "https://github.com/SMWARREN/HashFleet/releases/download/v1.0.0/hashfleet-cli-1.0.0-macos-arm64.tar.gz"\n  sha256 "' + 'd' * 64 + '"\n'


def good_run():
    return {'event': 'push', 'head_branch': 'main', 'conclusion': 'success', 'status': 'completed',
            'repository': {'full_name': r.REPO}, 'head_repository': {'full_name': r.REPO},
            'path': '.github/workflows/ci.yml', 'head_sha': SHA}


class HelperTests(unittest.TestCase):
    def test_require_semver_and_names(self):
        r.require(True, 'x')
        with self.assertRaises(ValueError):
            r.require(False, 'boom')
        self.assertEqual(r.semver('1.2.3'), (1, 2, 3))
        for bad in ('1.2', '01.2.3', 'v1.2.3', '1.2.3-rc1'):
            with self.assertRaises(ValueError):
                r.semver(bad)
        self.assertEqual(len(r.release_files('1.2.3')), 5)
        self.assertIn('HashFleet-1.2.3-macos-arm64.zip', r.asset_names('1.2.3'))

    def test_command_and_api_wrappers(self):
        with patch.object(r.subprocess, 'check_output', return_value=' out \n') as run:
            self.assertEqual(r.command('x'), 'out')
        with patch.object(r, 'command', return_value='{"a": 1}'):
            self.assertEqual(r.api('things'), {'a': 1})
        with patch.object(r.subprocess, 'check_output', return_value='{"ok": true}') as run:
            self.assertEqual(r.api('git/refs', ref='x'), {'ok': True})
            self.assertIn('--method', run.call_args.args[0])
        import base64
        with patch.object(r, 'api', return_value={'content': base64.b64encode(b'hi').decode()}):
            self.assertEqual(r.source_file('main', 'f'), 'hi')
        with patch.object(r, 'command', return_value=json.dumps([[{'tag_name': 'v1'}], [{'tag_name': 'v2'}]])):
            self.assertEqual([x['tag_name'] for x in r.release_list()], ['v1', 'v2'])


class CheckedRunTests(unittest.TestCase):
    def test_accepts_good_run(self):
        self.assertEqual(r.checked_run(good_run(), [{'name': 'CI required', 'conclusion': 'success'}]), SHA)

    def test_rejects_each_bad_field(self):
        gate = [{'name': 'CI required', 'conclusion': 'success'}]
        for key, value in [('event', 'pull_request'), ('head_branch', 'dev'), ('conclusion', 'failure'),
                           ('path', 'x.yml'), ('head_sha', 'zz'), ('repository', {'full_name': 'o/x'})]:
            run = good_run()
            run[key] = value
            with self.assertRaises(ValueError, msg=key):
                r.checked_run(run, gate)
        for jobs in ([], [{'name': 'CI required', 'conclusion': 'failure'}]):
            run = good_run()
            with self.assertRaises(ValueError):
                r.checked_run(run, jobs)


class UpdatePackagesTests(unittest.TestCase):
    def hashes(self):
        return {n: HASH for n in r.asset_names('1.0.1')}

    def test_updates_both_definitions(self):
        cask, formula = r.update_packages(CASK, FORMULA, '1.0.1', self.hashes())
        self.assertIn('version "1.0.1"', cask)
        self.assertIn(HASH, cask)
        self.assertIn('v1.0.1/hashfleet-cli-1.0.1-macos-arm64.tar.gz', formula)

    def test_rejects_bad_inputs(self):
        with self.assertRaises(ValueError):
            r.update_packages(CASK, FORMULA, '1.0.1', {'x': HASH})
        bad_hashes = {n: 'nothex' for n in r.asset_names('1.0.1')}
        with self.assertRaises(ValueError):
            r.update_packages(CASK, FORMULA, '1.0.1', bad_hashes)
        old_hashes = {n: HASH for n in r.asset_names('0.9.0')}
        with self.assertRaises(ValueError):
            r.update_packages(CASK, FORMULA, '0.9.0', old_hashes)
        hashes = self.hashes()
        odd_version = CASK.replace('version "1.0.0"', 'version "x"')
        with self.assertRaises(ValueError):
            r.update_packages(odd_version, FORMULA, '1.0.1', hashes)
        odd_url = CASK.replace('#{version}/HashFleet', 'zzz/HashFleet')
        with self.assertRaises(ValueError):
            r.update_packages(odd_url, FORMULA, '1.0.1', hashes)


class RemoteHashesTests(unittest.TestCase):
    def release(self, extra=None, draft=False):
        names = r.asset_names('1.0.0')
        assets = [{'name': n, 'digest': 'sha256:' + HASH} for n in names] + [{'name': r.CHECKSUM_MANIFEST}]
        assets += extra or []
        return {'draft': draft, 'prerelease': False, 'assets': assets}

    def test_legacy_and_full_sets(self):
        with patch.object(r, 'api', return_value=self.release()):
            self.assertEqual(set(r.remote_hashes('1.0.0')), set(r.asset_names('1.0.0')))
        full = self.release([{'name': n, 'digest': 'sha256:' + HASH} for n in r.LATEST_NAMES])
        with patch.object(r, 'api', return_value=full):
            self.assertEqual(len(r.remote_hashes('1.0.0')), 2)

    def test_failures(self):
        with patch.object(r, 'api', return_value=self.release(draft=True)):
            with self.assertRaises(ValueError):
                r.remote_hashes('1.0.0')
        with patch.object(r, 'api', return_value=self.release([{'name': 'stray'}])):
            with self.assertRaises(ValueError):
                r.remote_hashes('1.0.0')
        broken = self.release()
        broken['assets'][0]['digest'] = 'bad'
        with patch.object(r, 'api', return_value=broken):
            with self.assertRaises(ValueError):
                r.remote_hashes('1.0.0')
        mismatch = self.release([{'name': r.LATEST_NAMES[0], 'digest': 'sha256:' + 'e' * 64},
                                 {'name': r.LATEST_NAMES[1], 'digest': 'sha256:' + HASH}])
        with patch.object(r, 'api', return_value=mismatch):
            with self.assertRaises(ValueError):
                r.remote_hashes('1.0.0')


class PlanTests(unittest.TestCase):
    def run_plan(self, releases, current=SHA, tags='', version='1.0.1'):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / 'out'
            def fake_api(path, **kw):
                if path.startswith('actions/runs'):
                    return good_run()
                return {'object': {'sha': current}}
            def fake_command(*args):
                return json.dumps([{'jobs': [{'name': 'CI required', 'conclusion': 'success'}]}]) if args[:2] == ('gh', 'api') else tags
            with patch.dict(os.environ, {'GITHUB_OUTPUT': str(out)}), \
                 patch.object(r, 'api', side_effect=fake_api), \
                 patch.object(r, 'command', side_effect=fake_command), \
                 patch.object(r, 'source_file', return_value=version + '\n'), \
                 patch.object(r, 'release_list', return_value=releases):
                r.plan('123')
            return out.read_text()

    def test_new_release_needed(self):
        text = self.run_plan([{'tag_name': 'v1.0.0', 'draft': False, 'prerelease': False}])
        self.assertIn('needed=true', text)

    def test_already_published_and_superseded(self):
        self.assertIn('needed=false', self.run_plan([{'tag_name': 'v1.0.1', 'draft': False, 'prerelease': False}]))
        self.assertIn('needed=false', self.run_plan([], current='f' * 40))

    def test_failures(self):
        with self.assertRaises(ValueError):
            self.run_plan([{'tag_name': 'v1.0.1', 'draft': True, 'prerelease': False}])
        with self.assertRaises(ValueError):
            self.run_plan([{'tag_name': 'v2.0.0', 'draft': False, 'prerelease': False}])
        with self.assertRaises(ValueError):
            r.plan('abc')


class PublishTests(unittest.TestCase):
    def setup_dir(self, tmp, signed=True):
        root = Path(tmp)
        names = r.asset_names('1.0.0')
        hashes = {}
        for n in names:
            (root / n).write_bytes(n.encode())
            hashes[n] = hashlib.sha256(n.encode()).hexdigest()
        (root / r.CHECKSUM_MANIFEST).write_text(''.join(f'{hashes[n]}  {n}\n' for n in names))
        (root / 'verification.json').write_text(json.dumps({'version': '1.0.0', 'sha': SHA, 'signed_and_notarized': signed, 'sha256': hashes}))
        return root, hashes

    def test_precondition_failures(self):
        with tempfile.TemporaryDirectory() as tmp:
            root, _ = self.setup_dir(tmp)
            with self.assertRaises(ValueError):
                r.publish('1.0.0', 'short', root)
            with patch.object(r, 'command', return_value='0' * 40):
                with self.assertRaises(ValueError):
                    r.publish('1.0.0', SHA, root)
            with patch.object(r, 'command', return_value=SHA), patch.object(r, 'api', return_value={'object': {'sha': 'f' * 40}}):
                with self.assertRaises(ValueError):
                    r.publish('1.0.0', SHA, root)

    def test_publish_happy_path(self):
        with tempfile.TemporaryDirectory() as tmp:
            root, hashes = self.setup_dir(tmp)
            files = r.release_files('1.0.0')
            # Latest aliases are written during publish, so compute digests lazily.
            def fake_api(path, **kw):
                if path == r.MAIN_REF:
                    return {'object': {'sha': SHA}}
                if path.startswith('releases/'):
                    return {'draft': True, 'assets': [{'name': n, 'digest': 'sha256:' + hashlib.sha256((root / n).read_bytes()).hexdigest()} for n in files]}
                return {}
            calls = []
            def fake_command(*args):
                calls.append(args)
                return SHA if args[:2] == ('git', 'rev-parse') else ''
            listings = [[], [{'tag_name': 'v1.0.0', 'draft': True, 'id': 7}]]
            cwd = os.getcwd()
            os.chdir(tmp)
            try:
                Path('version.txt').write_text('1.0.0\n')
                with patch.object(r, 'api', side_effect=fake_api), patch.object(r, 'command', side_effect=fake_command), \
                     patch.object(r, 'release_list', side_effect=listings), patch.object(r, 'homebrew') as brew:
                    r.publish('1.0.0', SHA, root)
                    brew.assert_called_once_with('1.0.0')
            finally:
                os.chdir(cwd)
            self.assertTrue(any(c[:3] == ('gh', 'release', 'create') for c in calls))
            self.assertTrue(any(c[:3] == ('gh', 'release', 'edit') for c in calls))


class HomebrewTests(unittest.TestCase):
    def setUp(self):
        self.hashes = {n: HASH for n in r.asset_names('1.0.1')}

    def test_no_change_needed(self):
        new = r.update_packages(CASK, FORMULA, '1.0.1', self.hashes)
        with patch.object(r, 'remote_hashes', return_value=self.hashes), \
             patch.object(r, 'api', return_value={'object': {'sha': SHA}}), \
             patch.object(r, 'source_file', side_effect=list(new)):
            r.homebrew('1.0.1')

    def test_existing_pr_matches_or_differs(self):
        new = r.update_packages(CASK, FORMULA, '1.0.1', self.hashes)
        def fake_api(path, **kw):
            if path == r.MAIN_REF:
                return {'object': {'sha': SHA}}
            return [{'head': {'sha': 'p' * 40}, 'html_url': 'https://example.invalid/pr'}]
        with patch.object(r, 'remote_hashes', return_value=self.hashes), patch.object(r, 'api', side_effect=fake_api), \
             patch.object(r, 'source_file', side_effect=[CASK, FORMULA, *new]):
            r.homebrew('1.0.1')
        with patch.object(r, 'remote_hashes', return_value=self.hashes), patch.object(r, 'api', side_effect=fake_api), \
             patch.object(r, 'source_file', side_effect=[CASK, FORMULA, CASK, FORMULA]):
            with self.assertRaises(ValueError):
                r.homebrew('1.0.1')

    def test_creates_branch_and_pr(self):
        calls = []
        def fake_api(path, **kw):
            calls.append(path)
            if path == r.MAIN_REF:
                return {'object': {'sha': SHA}}
            if path.startswith('pulls?'):
                return []
            if path.startswith('git/commits/'):
                return {'tree': {'sha': 't'}}
            if path == 'pulls':
                return {'html_url': 'https://example.invalid/new'}
            return {'sha': 's'}
        with patch.object(r, 'remote_hashes', return_value=self.hashes), patch.object(r, 'api', side_effect=fake_api), \
             patch.object(r, 'source_file', side_effect=[CASK, FORMULA]):
            r.homebrew('1.0.1')
        self.assertIn('pulls', calls)
        self.assertIn('git/refs', calls)


if __name__ == '__main__':
    unittest.main()
