#!/usr/bin/env node
/** Exercise the real local download UI in isolated Chrome using the installed Playwright CLI. */
import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { parsePlaywrightResult } from './playwright-result.mjs'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const origin = process.argv[2] ?? 'http://127.0.0.1:4173'
assert(['http://127.0.0.1:4173', 'http://127.0.0.1:4174'].includes(origin), 'Only the documented loopback development or built preview is allowed')
const wrapper = path.join(os.homedir(), '.jcode/skills/playwright/scripts/playwright_cli.sh')
assert(fs.existsSync(wrapper), 'The installed Jcode Playwright CLI skill is required')
const session = `download-dialog-acceptance-${new URL(origin).port}`
const stamp = new Date().toISOString().replaceAll(/[^0-9TZ]/g, '')
const relative = `output/playwright/download-dialog-${stamp}-${new URL(origin).port}`
const directory = path.join(root, relative)
fs.mkdirSync(directory, { recursive: true })
function cli(name, args) {
  const output = spawnSync(wrapper, ['--session', session, ...args], {
    cwd: root, encoding: 'utf8', timeout: 180000, maxBuffer: 8 * 1024 * 1024,
  })
  fs.writeFileSync(path.join(directory, `${name}.log`), `${output.stdout ?? ''}${output.stderr ?? ''}`)
  assert(!output.error && output.status === 0, `${name} CLI failed. See ${relative}/${name}.log`)
  return output.stdout
}
try {
  cli('open', ['open', origin, '--browser', 'chrome'])
  cli('settle-open', ['run-code', "async (page) => { await page.waitForLoadState('networkidle') }"])
  cli('acceptance', ['run-code', fs.readFileSync(path.join(root, 'Tools/download-acceptance.js'), 'utf8')])
  const result = parsePlaywrightResult(cli('result', ['eval', 'window.__hashfleetDownloadAcceptance']))
  fs.writeFileSync(path.join(directory, 'result.json'), JSON.stringify(result, null, 2) + '\n')
  assert(result?.status === 'passed' && result.origin === origin && result.responseInterception === false && result.checks >= 180, `Real browser acceptance failed. See ${relative}`)
  console.log(JSON.stringify({ ...result, artifacts: relative }, null, 2))
} finally {
  cli('close', ['close'])
}
