import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'

// This calls a real server. It never intercepts responses or imports app logic.
const origin = process.env.HASHFLEET_TEST_ORIGIN ?? 'http://127.0.0.1:4175'
assert.equal(origin, 'http://127.0.0.1:4175', 'This acceptance tool is restricted to the isolated local static host')
const root = path.resolve('dist')
const observations = []
const expectedHeaders = {
  'x-content-type-options': 'nosniff',
  'referrer-policy': 'strict-origin-when-cross-origin',
  'x-frame-options': 'DENY',
  'permissions-policy': 'camera=(), microphone=(), geolocation=()',
  'content-security-policy': fs.readFileSync(path.join(root, '.htaccess'), 'utf8').match(/Header always set Content-Security-Policy "([^"]+)"/)[1],
}

function walk(directory, prefix = '') {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap(entry => {
    assert(!entry.isSymbolicLink(), `Unexpected build symlink: ${entry.name}`)
    const relative = prefix + entry.name
    return entry.isDirectory() ? walk(path.join(directory, entry.name), `${relative}/`) : [relative]
  })
}

async function request(route, { status = 200, method = 'GET', file, type } = {}) {
  const response = await fetch(`${origin}${route}`, { method, redirect: 'manual', signal: AbortSignal.timeout(10000) })
  assert.equal(response.status, status, `${method} ${route} status`)
  for (const [header, expected] of Object.entries(expectedHeaders)) {
    assert.equal(response.headers.get(header), expected, `${method} ${route} header ${header}`)
  }
  const contentType = response.headers.get('content-type')
  if (type) assert(type.test(contentType), `${method} ${route} MIME type: ${contentType}`)
  const body = Buffer.from(await response.arrayBuffer())
  if (file) assert(body.equals(fs.readFileSync(path.join(root, file))), `Served bytes differ: ${file}`)
  observations.push({ method, route, status: response.status, contentType, bytes: body.length, exactFileMatch: file ?? null, securityHeaders: 'all five matched actual response' })
}

await request('/', { file: 'index.html', type: /^text\/html\b/ })
await request('/', { method: 'HEAD', type: /^text\/html\b/ })
for (const file of walk(root).filter(file => file !== '.htaccess')) {
  let type
  if (file.endsWith('.js')) type = /javascript/
  else if (file.endsWith('.css')) type = /^text\/css\b/
  else if (file.endsWith('.png')) type = /^image\/png\b/
  else if (file.endsWith('.xml')) type = /xml/
  await request(`/${file}`, { file, type })
}
for (const route of ['/assets/', '/images/', '/.htaccess']) {
  await request(route, { status: 403 })
}
for (const route of ['/.env', '/.env.local', '/.git/config', '/src/App.tsx', '/package.json', '/missing-hashfleet-page', '/api/no-backend-read-only']) {
  await request(route, { status: 404 })
}
await request('/__hashfleet_acceptance_no_backend', { status: 404, method: 'POST' })
console.log(JSON.stringify({ status: 'passed', checkedAt: new Date().toISOString(), origin, responseInterception: false, observations }, null, 2))
