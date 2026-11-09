#!/usr/bin/env node
import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const origin = process.argv[2] ?? 'http://127.0.0.1:4174'
assert(['http://127.0.0.1:4174', 'https://hashfleet.app'].includes(origin), 'Only the real product site or owned production preview is permitted')
const wrapper = path.join(os.homedir(), '.jcode/skills/playwright/scripts/playwright_cli.sh')
assert(fs.existsSync(wrapper), 'The installed Playwright skill wrapper is required')
const session = origin === 'https://hashfleet.app' ? 'watch-public' : 'watch-local'
const stamp = new Date().toISOString().replaceAll(/[^0-9TZ]/g, '')
const relative = `output/playwright/${stamp}-${session}`
const directory = path.join(root, relative)
fs.mkdirSync(directory, { recursive: true })

function cli(name, args) {
  const output = spawnSync(wrapper, ['--session', session, ...args], { cwd: root, encoding: 'utf8', timeout: 300000, maxBuffer: 8 * 1024 * 1024 })
  fs.writeFileSync(path.join(directory, `${name}.log`), `${output.stdout ?? ''}${output.stderr ?? ''}`)
  assert(!output.error && output.status === 0, `${name} CLI failed. See ${relative}/${name}.log`)
  return output.stdout
}

cli('open', ['open', origin])
cli('snapshot', ['snapshot'])
let code = fs.readFileSync(path.join(root, 'Tools/watch-acceptance.js'), 'utf8')
assert(code.split('__WATCH_MANIFEST__').length === 2, 'Exactly one original-image manifest is injected')
code = code.replace('__WATCH_MANIFEST__', fs.readFileSync(path.join(root, 'src/lib/watch-captures.json'), 'utf8'))
code = code.replaceAll('output/playwright/watch-', `${relative}/watch-`)
cli('acceptance', ['run-code', code])
const output = cli('result', ['eval', 'window.__hashfleetWatchAcceptance'])
const match = output.match(/### Result\s*\n([\s\S]*?)\n### Ran Playwright code/)
assert(match, `Missing actual browser result. See ${relative}/result.log`)
const result = JSON.parse(match[1].trim())
fs.writeFileSync(path.join(directory, 'result.json'), JSON.stringify(result, null, 2) + '\n')
assert(result?.status === 'passed' && result.origin === origin && result.nativeCaptures === 5 && result.imageFailureRecovery === true && result.browserErrors.length === 0 && result.failedRequests.length === 0, `Watch acceptance failed. See ${relative}/result.json`)
console.log(JSON.stringify({ status: result.status, origin, checks: result.checks, nativeCaptures: result.nativeCaptures, browserErrors: result.browserErrors, failedRequests: result.failedRequests, normalOperationResponseInterception: result.normalOperationResponseInterception, isolatedFailureFixture: result.isolatedFailureFixture, artifacts: relative }, null, 2))
