#!/usr/bin/env node
import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { parsePlaywrightResult } from './playwright-result.mjs'
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const origin = process.argv[2] ?? 'http://127.0.0.1:4175'
assert(['http://127.0.0.1:4175', 'https://hashfleet.app'].includes(origin), 'Use the isolated Apache fixture or verified product site')
const wrapper = path.join(os.homedir(), '.jcode/skills/playwright/scripts/playwright_cli.sh')
assert(fs.existsSync(wrapper), 'The installed Playwright CLI skill is required')
const session = origin === 'https://hashfleet.app' ? 'react-entry-public' : 'react-entry-local'
const stamp = new Date().toISOString().replaceAll(/[^0-9TZ]/g, '')
const relative = `output/playwright/${stamp}-${session}`
const directory = path.join(root, relative)
fs.mkdirSync(directory, { recursive: true })
function cli(name, args) {
  const result = spawnSync(wrapper, ['--session', session, ...args], { cwd: root, encoding: 'utf8', timeout: 180000, maxBuffer: 4 * 1024 * 1024 })
  fs.writeFileSync(path.join(directory, name + '.log'), `${result.stdout ?? ''}${result.stderr ?? ''}`)
  assert(!result.error && result.status === 0, `${name} failed: ${relative}/${name}.log`)
  return result.stdout
}
cli('open', ['open', origin])
cli('acceptance', ['run-code', fs.readFileSync(path.join(root, 'Tools/route-acceptance.js'), 'utf8')])
const output = cli('result', ['eval', 'window.__hashfleetRouteAcceptance'])
const result = parsePlaywrightResult(output)
assert(result !== undefined, `Missing actual browser result: ${relative}`)
fs.writeFileSync(path.join(directory, 'result.json'), JSON.stringify(result, null, 2) + '\n')
assert(result?.status === 'passed' && result.origin === origin && result.responseInterception === false && result.checks >= 100, `Route acceptance failed: ${relative}`)
console.log(JSON.stringify({ ...result, artifacts: relative }, null, 2))
