#!/usr/bin/env node
/** Read-only verification of the published website artifact, never miner or notification APIs. */
import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const website = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const dist = path.join(website, 'dist')
const origin = 'https://hashfleet.app'
const deployedRules = fs.readFileSync(path.join(website, '../Server/public/.htaccess'), 'utf8')
const headers = {
  'x-content-type-options': 'nosniff',
  'referrer-policy': 'no-referrer',
  'x-frame-options': 'DENY',
  'permissions-policy': 'camera=(), microphone=(), geolocation=()',
  'content-security-policy': deployedRules.match(/Header always set Content-Security-Policy "([^"]+)"/)[1],
}
const observations = []
const failures = []
function files(directory, prefix = '') {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap(entry => {
    assert(!entry.isSymbolicLink(), `Unexpected build symlink: ${entry.name}`)
    const relative = prefix + entry.name
    return entry.isDirectory() ? files(path.join(directory, entry.name), `${relative}/`) : [relative]
  })
}
function mime(file) {
  if (file.endsWith('.html')) return /text\/html/
  if (file.endsWith('.js')) return /javascript/
  if (file.endsWith('.css')) return /text\/css/
  if (file.endsWith('.webp')) return /image\/webp/
  if (file.endsWith('.png')) return /image\/png/
  if (file.endsWith('.woff2')) return /font\/woff2|application\/font-woff/
  if (file.endsWith('.xml')) return /xml/
  return null
}
async function request(route, file, expectedStatus = 200) {
  const response = await fetch(origin + route, { redirect: 'manual', cache: 'no-store', signal: AbortSignal.timeout(20000) })
  const before = failures.length
  const check = (value, label) => { if (!value) failures.push(label) }
  check(response.status === expectedStatus, `${route}: HTTP ${response.status}, expected ${expectedStatus}`)
  for (const [name, expected] of Object.entries(headers)) check(response.headers.get(name) === expected, `${route}: ${name} is ${JSON.stringify(response.headers.get(name))}, expected ${JSON.stringify(expected)}`)
  const bytes = Buffer.from(await response.arrayBuffer())
  if (file) {
    check(bytes.equals(fs.readFileSync(path.join(dist, file))), `${route}: bytes differ from the validated build`)
    const expectedType = mime(file)
    if (expectedType) check(expectedType.test(response.headers.get('content-type') ?? ''), `${route}: MIME type`)
    check(/no-store/.test(response.headers.get('cache-control') ?? ''), `${route}: private no-store hosting policy preserved`)
  }
  observations.push({ route, status: response.status, bytes: bytes.length, contentType: response.headers.get('content-type'), exactFileMatch: file ?? null, failures: failures.slice(before), securityHeaders: Object.fromEntries(Object.keys(headers).map(name => [name, response.headers.get(name)])) })
}
await request('/', 'index.html')
for (const file of files(dist).filter(file => file !== '.htaccess')) await request('/' + file, file)
for (const route of ['/.htaccess', '/.env.local']) await request(route, null, 403)
for (const route of ['/.git/config', '/src/App.tsx', '/package.json', '/hashfleet-private/config.php', '/missing-native-parity-page']) await request(route, null, 404)
for (const route of ['/assets/', '/images/native/']) await request(route, null, 403)
console.log(JSON.stringify({ status: failures.length ? 'failed' : 'passed', checkedAt: new Date().toISOString(), origin, responseInterception: false, requests: observations.length, failures, observations }, null, 2))
assert.equal(failures.length, 0, 'Strict public asset/header acceptance failed. All observations and original requirements are retained in the JSON result.')
