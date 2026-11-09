#!/usr/bin/env node
/** Reproduce the native-capture acceptance using the installed, isolated Playwright CLI. */
import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { parsePlaywrightResult } from './playwright-result.mjs'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const origin = process.argv[2] ?? 'http://127.0.0.1:4174'
assert(['http://127.0.0.1:4174', 'http://127.0.0.1:4175', 'https://hashfleet.app'].includes(origin), 'Only the documented preview or actual product site is allowed')
const wrapper = path.join(os.homedir(), '.jcode/skills/playwright/scripts/playwright_cli.sh')
assert(fs.existsSync(wrapper), 'Install the Jcode Playwright skill first')
const session = origin === 'https://hashfleet.app' ? 'native-parity-public' : 'native-parity-local'
const stamp = new Date().toISOString().replaceAll(/[^0-9TZ]/g, '')
const relative = `output/playwright/native-parity-${stamp}-${session}`
const directory = path.join(root, relative)
fs.mkdirSync(directory, { recursive: true })

function cli(name, args) {
  const output = spawnSync(wrapper, ['--session', session, ...args], {
    cwd: root,
    encoding: 'utf8',
    timeout: 600000,
    maxBuffer: 8 * 1024 * 1024,
  })
  fs.writeFileSync(path.join(directory, `${name}.log`), `${output.stdout ?? ''}${output.stderr ?? ''}`)
  assert(!output.error && output.status === 0, `${name} CLI failed. See ${relative}/${name}.log`)
  return output.stdout
}

cli('open', ['open', origin])
// Finish the CLI's initial page load before observing a deliberate acceptance navigation.
// Otherwise that navigation can abort the first load's still-pending native images.
// All assertions, including zero failed requests during acceptance, remain strict.
cli('settle-open', ['run-code', "async (page) => { await page.waitForLoadState('networkidle') }"])
cli('snapshot', ['snapshot'])
let code = fs.readFileSync(path.join(root, 'Tools/native-parity-acceptance.js'), 'utf8')
for (const [placeholder, fixture] of [['__NATIVE_MANIFEST__', 'native-captures.json'], ['__CLI_CAPTURES__', 'cli-captures.json']]) {
  assert(code.split(placeholder).length === 2, `Exactly one ${placeholder} injection is required`)
  code = code.replace(placeholder, fs.readFileSync(path.join(root, 'src/lib', fixture), 'utf8'))
}
// Only the artifact location changes. All acceptance assertions run unchanged.
code = code.replaceAll('output/playwright/product-parity-', `${relative}/product-parity-`)
cli('acceptance', ['run-code', code])
const evaluated = cli('result', ['eval', 'window.__hashfleetNativeParity'])
let result
try { result = parsePlaywrightResult(evaluated) } catch { throw new Error(`Invalid browser result. See ${relative}/result.log`) }
assert(result !== undefined, `Missing browser result. See ${relative}/result.log`)
fs.writeFileSync(path.join(directory, 'result.json'), JSON.stringify(result, null, 2) + '\n')
assert(result?.status === 'passed' && result.origin === origin, `Browser acceptance failed. See ${relative}/result.json`)
console.log(JSON.stringify({ status: result.status, origin, checks: result.checks, nativeCaptures: result.nativeCaptures, browserErrors: result.browserErrors, failedRequests: result.failedRequests, artifacts: relative }, null, 2))
