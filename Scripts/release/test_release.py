#!/usr/bin/env python3
"""Offline release policy tests. No GitHub calls, signing, builds or publication."""
import copy
import re
from pathlib import Path
import unittest
from unittest.mock import patch
import release as r

ROOT = Path(__file__).resolve().parents[2]


class ReleaseContracts(unittest.TestCase):
    def setUp(self):
        self.fence = patch.object(r.subprocess, 'check_output', side_effect=AssertionError('Network/native commands forbidden in contract tests'))
        self.fence.start()
        self.addCleanup(self.fence.stop)
        self.run = {'event': 'push', 'head_branch': 'main', 'status': 'completed', 'conclusion': 'success', 'repository': {'full_name': r.REPO}, 'head_repository': {'full_name': r.REPO}, 'path': '.github/workflows/ci.yml', 'head_sha': 'a' * 40}
        self.jobs = [{'name': 'CI required', 'conclusion': 'success'}]
        self.cask = (ROOT / 'Casks/hashfleet.rb').read_text()
        self.formula = (ROOT / 'Formula/hashfleet-cli.rb').read_text()
        # Normalize only fixture versions so later real releases do not turn these
        # policy tests into accidental downgrade attempts.
        self.cask = re.sub(r'^  version "[^"]+"$', '  version "0.1.0"', self.cask, flags=re.MULTILINE)
        self.formula = re.sub(r'/v[0-9.]+/hashfleet-cli-[0-9.]+-macos-arm64', '/v0.1.0/hashfleet-cli-0.1.0-macos-arm64', self.formula)
        self.hashes = dict(zip(r.asset_names('0.2.0'), ['1' * 64, '2' * 64]))

    def test_trusted_run(self):
        self.assertEqual(r.checked_run(self.run, self.jobs), 'a' * 40)

    def test_reject_untrusted_run_fields(self):
        changes = {'event': 'pull_request', 'head_branch': 'feature', 'status': 'in_progress', 'conclusion': 'failure', 'path': '.github/workflows/other.yml', 'head_sha': 'bad', 'repository': {'full_name': 'other/repo'}, 'head_repository': {'full_name': 'attacker/HashFleet'}}
        for key, value in changes.items():
            with self.subTest(key=key), self.assertRaises(ValueError):
                r.checked_run(dict(self.run, **{key: value}), self.jobs)

    def test_required_check_cannot_be_skipped(self):
        for result in ('skipped', 'failure', 'cancelled', None):
            with self.subTest(result=result), self.assertRaises(ValueError):
                r.checked_run(self.run, [{'name': 'CI required', 'conclusion': result}])

    def test_missing_or_duplicate_required_check(self):
        for jobs in ([], self.jobs + self.jobs):
            with self.assertRaises(ValueError):
                r.checked_run(self.run, jobs)

    def test_semver_rejects_injection_and_nonstable_versions(self):
        for version in ('v0.2.0', '0.2', '0.2.0-beta', '01.2.0', '0.2.0\n', '../../a', '1.2.3;echo BAD'):
            with self.subTest(version=version), self.assertRaises(ValueError):
                r.semver(version)

    def test_versions_order_numerically(self):
        self.assertGreater(r.semver('0.10.0'), r.semver('0.9.9'))

    def test_package_update_preserves_other_content(self):
        cask, formula = r.update_packages(self.cask, self.formula, '0.2.0', self.hashes)
        self.assertIn('  version "0.2.0"', cask)
        self.assertIn('  sha256 "' + '1' * 64 + '"', cask)
        self.assertIn('/v0.2.0/hashfleet-cli-0.2.0-macos-arm64.tar.gz', formula)
        self.assertIn('  sha256 "' + '2' * 64 + '"', formula)
        self.assertEqual(cask.count('\n'), self.cask.count('\n'))
        self.assertEqual(formula.count('\n'), self.formula.count('\n'))
        self.assertIn('app "Hash Fleet.app"', cask)
        self.assertIn('libexec.install "hashfleet", "GRDB_GRDB.bundle"', formula)

    def test_package_update_is_idempotent(self):
        updated = r.update_packages(self.cask, self.formula, '0.2.0', self.hashes)
        self.assertEqual(updated, r.update_packages(*updated, '0.2.0', self.hashes))

    def test_no_downgrade(self):
        updated = r.update_packages(self.cask, self.formula, '0.2.0', self.hashes)
        with self.assertRaises(ValueError):
            r.update_packages(*updated, '0.1.0', dict(zip(r.asset_names('0.1.0'), ['1' * 64, '2' * 64])))

    def test_changed_template_and_duplicate_fields_rejected(self):
        for cask, formula in ((self.cask.replace('SMWARREN/HashFleet', 'other/repo'), self.formula), (self.cask + '\n  version "0.1.0"\n', self.formula), (self.cask, self.formula.replace('SMWARREN/HashFleet', 'other/repo'))):
            with self.assertRaises(ValueError):
                r.update_packages(cask, formula, '0.2.0', self.hashes)

    def test_formula_cannot_downgrade_independently(self):
        for formula in (self.formula.replace('0.1.0', '0.3.0'), self.formula.replace('/v0.1.0/', '/v0.3.0/')):
            with self.assertRaises(ValueError):
                r.update_packages(self.cask, formula, '0.2.0', self.hashes)

    def test_invalid_or_extra_hashes_rejected(self):
        for hashes in ({}, dict(self.hashes, extra='a' * 64), dict.fromkeys(self.hashes, 'not-a-hash')):
            with self.assertRaises(ValueError):
                r.update_packages(self.cask, self.formula, '0.2.0', hashes)

    def test_remote_release_digest_required(self):
        names = r.asset_names('0.2.0')
        release = {'draft': False, 'prerelease': False, 'assets': [{'name': n, 'digest': 'sha256:' + self.hashes[n]} for n in names] + [{'name': 'SHA256SUMS.txt', 'digest': 'sha256:' + '3' * 64}]}
        with patch.object(r, 'api', return_value=release):
            self.assertEqual(r.remote_hashes('0.2.0'), self.hashes)
        broken = copy.deepcopy(release)
        broken['assets'][0]['digest'] = None
        with patch.object(r, 'api', return_value=broken), self.assertRaises(ValueError):
            r.remote_hashes('0.2.0')

    def test_draft_not_used_for_homebrew(self):
        with patch.object(r, 'api', return_value={'draft': True, 'prerelease': False}), self.assertRaises(ValueError):
            r.remote_hashes('0.2.0')


if __name__ == '__main__':
    unittest.main(verbosity=2)
