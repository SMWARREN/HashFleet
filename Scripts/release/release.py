#!/usr/bin/env python3
"""Release gates and same-repository Homebrew PRs. Never approves or merges a PR."""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

REPO = 'SMWARREN/HashFleet'
VERSION = re.compile(r'(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)\Z', re.ASCII)
MAIN_REF = 'git/ref/heads/main'
CHECKSUM_MANIFEST = 'SHA256SUMS.txt'


def require(condition, message):
    if not condition:
        raise ValueError(message)


def semver(value):
    require(bool(VERSION.fullmatch(value)), 'Expected a stable MAJOR.MINOR.PATCH version')
    return tuple(map(int, value.split('.')))


def command(*args):
    return subprocess.check_output(args, text=True).strip()


def api(path, **fields):
    args = ['gh', 'api', f'repos/{REPO}/{path}']
    if fields:
        args += ['--method', 'POST', '--input', '-']
        return json.loads(subprocess.check_output(args, input=json.dumps(fields), text=True))
    return json.loads(command(*args))


def source_file(ref, path):
    payload = api(f'contents/{path}?ref={ref}')
    return base64.b64decode(payload['content'], validate=False).decode()


def release_list():
    pages = json.loads(command('gh', 'api', '--paginate', '--slurp', f'repos/{REPO}/releases?per_page=100'))
    return [item for page in pages for item in page]


def checked_run(run, jobs):
    require(run['event'] == 'push' and run['head_branch'] == 'main', 'Not a push-to-main CI run')
    require(run['conclusion'] == 'success' and run['status'] == 'completed', 'CI has not passed')
    require(run['repository']['full_name'] == REPO and run['head_repository']['full_name'] == REPO, 'Foreign repository CI')
    require(run['path'] == '.github/workflows/ci.yml', 'Unexpected CI workflow path')
    require(re.fullmatch(r'[0-9a-f]{40}', run['head_sha']) is not None, 'Invalid commit SHA')
    gates = [j for j in jobs if j['name'] == 'CI required']
    require(len(gates) == 1 and gates[0]['conclusion'] == 'success', 'Required aggregate check did not succeed')
    return run['head_sha']


def plan(run_id):
    require(str(run_id).isdigit(), 'CI run ID must be numeric')
    run = api(f'actions/runs/{run_id}')
    pages = json.loads(command('gh', 'api', '--paginate', '--slurp', f'repos/{REPO}/actions/runs/{run_id}/jobs?per_page=100'))
    sha = checked_run(run, [j for p in pages for j in p['jobs']])
    version = source_file(sha, 'version.txt').strip()
    semver(version)
    releases = release_list()
    existing = [r for r in releases if r['tag_name'] == f'v{version}']
    current = api(MAIN_REF)['object']['sha']
    needed = not existing and current == sha
    if existing:
        require(len(existing) == 1 and not existing[0]['draft'], 'Existing draft requires maintainer inspection, never overwrite it')
        print(f'v{version} already published. Existing assets and tag are untouched.')
    elif current != sha:
        print('A newer main commit superseded this run. No release.')
    else:
        previous = [semver(r['tag_name'][1:]) for r in releases if not r['draft'] and not r['prerelease'] and r['tag_name'].startswith('v') and VERSION.fullmatch(r['tag_name'][1:])]
        require(not previous or semver(version) > max(previous), 'Release version must increase')
        tags = command('git', 'ls-remote', '--tags', 'origin', f'refs/tags/v{version}')
        require(not tags, 'Tag already exists, refusing to retarget it')
    values = {'needed': str(needed).lower(), 'version': version, 'sha': sha}
    print(json.dumps(values))
    with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
        for key, value in values.items():
            output.write(f'{key}={value}\n')


def asset_names(version):
    semver(version)
    return [f'HashFleet-{version}-macos-arm64.zip', f'hashfleet-cli-{version}-macos-arm64.tar.gz']


# Unversioned copies let https://github.com/<repo>/releases/latest/download/<name> always
# resolve to the newest release, so the website never needs a rebuild for new versions.
LATEST_NAMES = ['HashFleet-macos-arm64.zip', 'hashfleet-cli-macos-arm64.tar.gz']


def release_files(version):
    return asset_names(version) + LATEST_NAMES + [CHECKSUM_MANIFEST]


def update_packages(cask, formula, version, hashes):
    names = asset_names(version)
    require(set(hashes) == set(names), 'Unexpected release assets')
    require(all(re.fullmatch(r'[0-9a-f]{64}', h) for h in hashes.values()), 'Invalid SHA-256')
    current = re.findall(r'^ {2}version "([^"]+)"$', cask, re.MULTILINE)
    require(len(current) == 1 and semver(version) >= semver(current[0]), 'Refusing Homebrew downgrade or ambiguous version')
    formula_versions = re.findall(r'^ {2}url "https://github.com/SMWARREN/HashFleet/releases/download/v([0-9.]+)/hashfleet-cli-([0-9.]+)-macos-arm64.tar.gz"$', formula, re.MULTILINE)
    require(len(formula_versions) == 1 and formula_versions[0][0] == formula_versions[0][1] and semver(version) >= semver(formula_versions[0][0]), 'Refusing formula downgrade or inconsistent URL')
    require(cask.count('  url "https://github.com/SMWARREN/HashFleet/releases/download/v#{version}/HashFleet-#{version}-macos-arm64.zip"') == 1, 'Unexpected cask download URL')
    def one(pattern, replacement, text):
        result, count = re.subn(pattern, lambda _: replacement, text, flags=re.MULTILINE)
        require(count == 1, f'Package definition did not match exactly once: {pattern}')
        return result
    cask = one(r'^ {2}version "[^"]+"$', f'  version "{version}"', cask)
    cask = one(r'^ {2}sha256 "[0-9a-f]{64}"$', f'  sha256 "{hashes[names[0]]}"', cask)
    formula = one(r'^ {2}url "https://github.com/SMWARREN/HashFleet/releases/download/v[^/]+/hashfleet-cli-[^"/]+-macos-arm64.tar.gz"$', f'  url "https://github.com/{REPO}/releases/download/v{version}/{names[1]}"', formula)
    formula = one(r'^ {2}sha256 "[0-9a-f]{64}"$', f'  sha256 "{hashes[names[1]]}"', formula)
    return cask, formula


def remote_hashes(version):
    release = api(f'releases/tags/v{version}')
    require(not release['draft'] and not release['prerelease'], 'Not a published stable release')
    assets = {a['name']: a for a in release['assets']}
    names = asset_names(version)
    legacy = set(names + [CHECKSUM_MANIFEST])
    require(len(release['assets']) == len(assets) and set(assets) in (legacy, set(release_files(version))), 'Unexpected or missing public release assets')
    hashes = {}
    for name in names:
        digest = assets[name].get('digest', '')
        require(isinstance(digest, str) and re.fullmatch(r'sha256:[0-9a-f]{64}', digest) is not None, 'GitHub asset digest missing')
        hashes[name] = digest.removeprefix('sha256:')
    for versioned, latest in zip(names, LATEST_NAMES):
        if latest in assets:
            require(assets[latest].get('digest') == assets[versioned]['digest'], 'Latest alias differs from versioned asset')
    return hashes


def homebrew(version):
    hashes = remote_hashes(version)
    base = api(MAIN_REF)['object']['sha']
    paths = ['Casks/hashfleet.rb', 'Formula/hashfleet-cli.rb']
    old = [source_file(base, p) for p in paths]
    new = update_packages(*old, version, hashes)
    if tuple(old) == new:
        print('Homebrew definitions already match the published release.')
        return
    branch = f'automation/homebrew-v{version}'
    pulls = api(f'pulls?state=open&head=SMWARREN:{branch}&base=main')
    if pulls:
        require(len(pulls) == 1, 'Ambiguous existing Homebrew PR')
        require(all(source_file(pulls[0]['head']['sha'], p) == text for p, text in zip(paths, new)), 'Existing PR differs from verified release assets')
        print(pulls[0]['html_url'])
        return
    # Git data API creates only a separate branch, never updates main or force-pushes.
    base_commit = api(f'git/commits/{base}')
    tree = api('git/trees', base_tree=base_commit['tree']['sha'], tree=[{'path': p, 'mode': '100644', 'type': 'blob', 'content': text} for p, text in zip(paths, new)])
    commit = api('git/commits', message=f'Update Homebrew packages to {version}', tree=tree['sha'], parents=[base])
    api('git/refs', ref=f'refs/heads/{branch}', sha=commit['sha'])
    pr = api('pulls', title=f'Update Homebrew packages to {version}', head=branch, base='main', body=f'Updates the separate Mac app and CLI packages to the published v{version} assets using GitHub SHA-256 digests.\n\nMaintainer: approve workflows if GitHub requests it, review checks, then merge. This workflow never approves or merges PRs.')
    print(pr['html_url'])


def publish(version, sha, directory):
    names = asset_names(version)
    require(re.fullmatch(r'[0-9a-f]{40}', sha) is not None, 'Invalid source SHA')
    require(command('git', 'rev-parse', 'HEAD') == sha, 'Checkout differs from tested source')
    require(api(MAIN_REF)['object']['sha'] == sha, 'Main advanced during build; use its successful CI run')
    require(Path('version.txt').read_text().strip() == version, 'Version mismatch')
    root = Path(directory)
    receipt = json.loads((root / 'verification.json').read_text())
    require(receipt['version'] == version and receipt['sha'] == sha and receipt['signed_and_notarized'] is True, 'Missing signed build verification')
    hashes = {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in names}
    require(hashes == receipt['sha256'], 'Artifact changed after verification')
    expected = ''.join(f'{hashes[name]}  {name}\n' for name in names)
    require((root / CHECKSUM_MANIFEST).read_text() == expected, 'Checksum manifest mismatch')
    for versioned, latest in zip(names, LATEST_NAMES):
        (root / latest).write_bytes((root / versioned).read_bytes())
        require(hashlib.sha256((root / latest).read_bytes()).hexdigest() == hashes[versioned], 'Latest alias copy mismatch')
    files = release_files(version)
    require(not any(r['tag_name'] == f'v{version}' for r in release_list()), 'Release exists, refusing overwrite')
    require(not command('git', 'ls-remote', '--tags', 'origin', f'refs/tags/v{version}'), 'Tag exists, refusing overwrite')
    # Atomic create refuses a concurrent tag. A partial failure is retained for manual inspection.
    api('git/refs', ref=f'refs/tags/v{version}', sha=sha)
    command('gh', 'release', 'create', f'v{version}', '--repo', REPO, '--verify-tag', '--draft', '--title', f'HashFleet {version}', '--notes', f'Separate signed and notarized Apple Silicon Mac app and CLI downloads. Requires macOS 14 or later.\n\nSource: {sha}\nInstallation: https://github.com/{REPO}/blob/main/docs/HOMEBREW.md', *[str(root / n) for n in files])
    drafts = [r for r in release_list() if r['tag_name'] == f'v{version}' and r['draft']]
    require(len(drafts) == 1, 'Expected exactly one created draft')
    uploaded = api(f'releases/{drafts[0]["id"]}')
    require(uploaded['draft'] and len(uploaded['assets']) == len(files), 'Draft asset set mismatch')
    for asset in uploaded['assets']:
        local = root / asset['name']
        require(asset['name'] in files, 'Unexpected uploaded asset')
        require(asset['digest'] == 'sha256:' + hashlib.sha256(local.read_bytes()).hexdigest(), 'Uploaded digest mismatch')
    command('gh', 'release', 'edit', f'v{version}', '--repo', REPO, '--draft=false', '--latest')
    homebrew(version)


def main():
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest='action', required=True)
    p = sub.add_parser('plan'); p.add_argument('--run-id', required=True)
    p = sub.add_parser('publish'); p.add_argument('--version', required=True); p.add_argument('--sha', required=True); p.add_argument('--directory', required=True)
    p = sub.add_parser('homebrew'); p.add_argument('--version', required=True)
    args = parser.parse_args()
    if args.action == 'plan':
        plan(args.run_id)
    elif args.action == 'publish':
        publish(args.version, args.sha, args.directory)
    else:
        homebrew(args.version)


if __name__ == '__main__':
    main()
