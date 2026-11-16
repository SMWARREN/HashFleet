#!/usr/bin/env node
/** Exercise real local responses in isolated Chrome, with fail-closed request guards. */
import assert from 'node:assert/strict'
import { execFile } from 'node:child_process'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { promisify } from 'node:util'
import { parsePlaywrightResult } from './playwright-result.mjs'
import {
  downloadBrowserConfig, installDownloadNetworkIsolation, startDownloadDenyProxy,
  validateDownloadResult, withDownloadCleanup,
} from './download-network.mjs'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const origin = process.argv[2] ?? 'http://127.0.0.1:4173'
assert(['http://127.0.0.1:4173', 'http://127.0.0.1:4174'].includes(origin), 'Only the documented loopback development or built preview is allowed')
const wrapper = path.join(os.homedir(), '.jcode/skills/playwright/scripts/playwright_cli.sh')
assert(fs.existsSync(wrapper), 'The installed Jcode Playwright CLI skill is required')
const stamp = new Date().toISOString().replaceAll(/[^0-9TZ]/g, '')
// A fresh session cannot silently reuse a previously created, unguarded context.
const session = `download-${new URL(origin).port}-${stamp}-${process.pid}`
const relative = `output/playwright/download-dialog-${stamp}-${new URL(origin).port}`
const directory = path.join(root, relative)
fs.mkdirSync(directory, { recursive: true })
const configPath = path.join(directory, 'cli.config.json')
const execute = promisify(execFile)
async function cli(name, args) {
  let output
  try {
    // Asynchronous execution lets the deny-only listener reject redirect hops.
    output = await execute(wrapper, ['--session', session, '--config', configPath, ...args], {
      cwd: root, encoding: 'utf8', timeout: 180000, maxBuffer: 8 * 1024 * 1024,
    })
  } catch (error) {
    output = error
    throw new Error(`${name} CLI failed. See ${relative}/${name}.log`, { cause: error })
  } finally {
    fs.writeFileSync(path.join(directory, `${name}.log`), `${output?.stdout ?? ''}${output?.stderr ?? ''}`)
  }
  assert(!/^### Error\b/m.test(output.stdout), `${name} failed. See ${relative}/${name}.log\n${output.stdout}`)
  return output.stdout
}
const denyProxy = await startDownloadDenyProxy()
let result
await withDownloadCleanup(async () => {
  fs.writeFileSync(configPath, JSON.stringify(downloadBrowserConfig(origin, denyProxy.server), null, 2) + '\n')
  await cli('open', ['open', 'about:blank', '--browser', 'chrome'])
  let code = fs.readFileSync(path.join(root, 'Tools/download-acceptance.js'), 'utf8')
  for (const [placeholder, value] of [
    ['__DOWNLOAD_ORIGIN__', JSON.stringify(origin)],
    ['__DOWNLOAD_NETWORK_INSTALL__', installDownloadNetworkIsolation.toString()],
  ]) {
    assert(code.split(placeholder).length === 2, `Exactly one ${placeholder} injection is required`)
    code = code.replace(placeholder, () => value)
  }
  await cli('acceptance', ['run-code', code])
  result = parsePlaywrightResult(await cli('result', ['eval', 'window.__hashfleetDownloadAcceptance']))
  validateDownloadResult(result, origin, denyProxy.counters.deniedConnections)
}, async () => {
  // Keep the deny proxy bound while requesting closure of this Chrome session.
  await withDownloadCleanup(
    () => cli('close', ['close']),
    () => withDownloadCleanup(
      () => denyProxy.close(),
      async () => fs.writeFileSync(path.join(directory, 'network-isolation.json'), JSON.stringify(denyProxy.counters, null, 2) + '\n'),
    ),
  )
})
// Include late traffic up to browser closure, not just the page's final check.
if (result?.requestIsolation) {
  Object.assign(result.requestIsolation, {
    serviceWorkers: 'block', isolatedContext: true,
    redirectGuard: 'context-proxy-deny-sink',
    proxyDeniedConnections: denyProxy.counters.deniedConnections,
  })
}
fs.writeFileSync(path.join(directory, 'result.json'), JSON.stringify(result, null, 2) + '\n')
validateDownloadResult(result, origin, denyProxy.counters.deniedConnections)
console.log(JSON.stringify({ ...result, artifacts: relative }, null, 2))
