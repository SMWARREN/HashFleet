#!/usr/bin/env node
import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const origin = process.argv[2] ?? 'http://127.0.0.1:4174'
assert(['http://127.0.0.1:4174', 'http://127.0.0.1:4175', 'https://hashfleet.app'].includes(origin))
const wrapper = path.join(os.homedir(), '.jcode/skills/playwright/scripts/playwright_cli.sh')
const session = origin === 'https://hashfleet.app' ? 'support-public' : 'support-local'
const stamp = new Date().toISOString().replaceAll(/[^0-9TZ]/g, '')
const relative = 'output/playwright/' + stamp + '-' + session
const directory = path.join(root, relative)
fs.mkdirSync(directory, { recursive: true })
function cli(name, args) {
  const result = spawnSync(wrapper, ['--session', session, ...args], { cwd: root, encoding: 'utf8', timeout: 180000, maxBuffer: 4 * 1024 * 1024 })
  fs.writeFileSync(path.join(directory, name + '.log'), (result.stdout ?? '') + (result.stderr ?? ''))
  assert(!result.error && result.status === 0, name + ' failed: ' + relative)
  return result.stdout
}
cli('open', ['open', origin])
cli('snapshot', ['snapshot'])
const code = fs.readFileSync(path.join(root, 'Tools/support-acceptance.js'), 'utf8').replaceAll('output/playwright/support-', relative + '/support-')
cli('acceptance', ['run-code', code])
const output = cli('result', ['eval', 'window.__hashfleetSupportAcceptance'])
const match = output.match(/### Result\s*\n([\s\S]*?)\n### Ran Playwright code/)
assert(match, 'Missing actual browser result: ' + relative)
const result = JSON.parse(match[1].trim())
fs.writeFileSync(path.join(directory, 'result.json'), JSON.stringify(result, null, 2) + '\n')
assert(result?.status === 'passed' && result.origin === origin && result.checks >= 60 && result.responseInterception === false && result.paymentAttempted === false, 'Support acceptance failed: ' + relative)
console.log(JSON.stringify({ ...result, artifacts: relative }, null, 2))
