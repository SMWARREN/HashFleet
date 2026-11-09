#!/usr/bin/env node
import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { parsePlaywrightResult } from './playwright-result.mjs'
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const origin = process.argv[2] ?? 'http://127.0.0.1:4174'
assert(['http://127.0.0.1:4174', 'https://hashfleet.app'].includes(origin))
const wrapper = path.join(os.homedir(), '.jcode/skills/playwright/scripts/playwright_cli.sh')
const session = origin === 'https://hashfleet.app' ? 'contact-public' : 'contact-local'
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
const code = fs.readFileSync(path.join(root, 'Tools/public-contact-acceptance.js'), 'utf8').replaceAll('output/playwright/contact-', relative + '/contact-')
cli('acceptance', ['run-code', code])
const output = cli('result', ['eval', 'window.__hashfleetContactAcceptance'])
const result = parsePlaywrightResult(output)
assert(result !== undefined, 'Missing actual browser result: ' + relative)
fs.writeFileSync(path.join(directory, 'result.json'), JSON.stringify(result, null, 2) + '\n')
assert(result?.status === 'passed' && result.origin === origin && result.checks === 85 && result.responseInterception === false && result.noEmailOrPhoneLinkOpened === true, 'Public contact acceptance failed: ' + relative)
console.log(JSON.stringify({ ...result, artifacts: relative }, null, 2))
