// Offline only: no browser, server listener, sockets, DNS or subprocesses.
import assert from 'node:assert/strict'
import fs from 'node:fs'
import test from 'node:test'
import vm from 'node:vm'
import {
  downloadBrowserConfig, installDownloadNetworkIsolation, rejectProxySocket,
  validateDownloadResult, withDownloadCleanup,
} from './download-network.mjs'

const origin = 'http://127.0.0.1:4173'
function fakePage(url = 'about:blank') {
  const handlers = {}
  const context = {
    pages: () => [page],
    on: (name, callback) => { handlers[name] = callback },
    route: async (pattern, callback) => { assert.equal(pattern, '**/*'); handlers.http = callback },
    routeWebSocket: async (pattern, callback) => { assert.equal(pattern, '**/*'); handlers.ws = callback },
  }
  const page = { url: () => url, context: () => context }
  return { page, context, handlers }
}

for (const port of [4173, 4174]) {
  test(`isolated ${port} config blocks service workers and all implicit loopback bypasses`, () => {
    const config = downloadBrowserConfig(`http://127.0.0.1:${port}`, 'http://127.0.0.1:54321')
    assert.equal(config.browser.isolated, true)
    assert.equal(config.browser.contextOptions.serviceWorkers, 'block')
    assert.deepEqual(config.browser.contextOptions.proxy, {
      server: 'http://127.0.0.1:54321',
      bypass: `<-loopback>,http://127.0.0.1:${port},ws://127.0.0.1:${port}`,
    })
    assert.equal(config.browser.launchOptions.channel, 'chrome')
  })
}

test('rejects unapproved origins and non-loopback proxy configuration', () => {
  for (const invalid of ['http://localhost:4173', `${origin}/`, 'http://127.0.0.1:4175', 'https://127.0.0.1:4173']) {
    assert.throws(() => downloadBrowserConfig(invalid, 'http://127.0.0.1:54321'))
  }
  for (const invalid of ['http://example.invalid:8080', 'direct://', 'http://127.0.0.1:0']) {
    assert.throws(() => downloadBrowserConfig(origin, invalid))
  }
})

test('deny sink destroys a connection without forwarding or emitting a response', () => {
  const calls = []
  const counters = { deniedConnections: 0 }
  rejectProxySocket({ destroy: () => calls.push('destroy') }, counters)
  assert.deepEqual(calls, ['destroy'])
  assert.equal(counters.deniedConnections, 1)
})

test('requires blank pages and supported APIs before any navigation', async () => {
  const navigated = fakePage(origin)
  await assert.rejects(installDownloadNetworkIsolation(navigated.page, origin), /first website navigation/)
  assert.deepEqual(navigated.handlers, {})
  const popup = fakePage()
  popup.context.pages = () => [popup.page, { url: () => origin }]
  await assert.rejects(installDownloadNetworkIsolation(popup.page, origin), /first website navigation/)
  const unsupported = fakePage()
  delete unsupported.context.routeWebSocket
  await assert.rejects(installDownloadNetworkIsolation(unsupported.page, origin), /routing support/)
  assert.deepEqual(unsupported.handlers, {})
})

test('routes allow only the exact selected HTTP origin and continue unmodified', async () => {
  const { page, handlers } = fakePage()
  await installDownloadNetworkIsolation(page, origin)
  for (const url of [`${origin}/`, `${origin}/assets/app.js?version=1`, `${origin}/redirect`]) {
    const actions = []
    await handlers.http({
      request: () => ({ url: () => url }),
      continue: async (...args) => actions.push(['continue', ...args]),
      abort: async () => actions.push(['abort']),
    })
    assert.deepEqual(actions, [['continue']], url)
  }
})

test('HTTP routes block changed port, scheme, hostname, credentials and malformed URLs', async () => {
  const { page, handlers } = fakePage()
  await installDownloadNetworkIsolation(page, origin)
  for (const url of [
    'http://127.0.0.1:4174/', 'http://127.0.0.1:54321/', 'http://localhost:4173/',
    'https://127.0.0.1:4173/', 'http://127.0.0.2:4173/', 'https://example.invalid/',
    'http://127.0.0.1.example.invalid:4173/', 'http://user:pass@127.0.0.1:4173/', 'not a URL',
  ]) {
    const actions = []
    await handlers.http({
      request: () => ({ url: () => url }),
      continue: async () => actions.push('continue'),
      abort: async code => actions.push(code),
    })
    assert.deepEqual(actions, ['blockedbyclient'], url)
  }
})

test('context-wide observer records redirect requests even when route handler is skipped', async () => {
  const { page, handlers } = fakePage()
  const receipt = await installDownloadNetworkIsolation(page, origin)
  handlers.request({ url: () => `${origin}/redirect` })
  const redirected = 'http://127.0.0.1:54321/redirected'
  handlers.request({ url: () => redirected })
  assert.deepEqual(receipt.blockedRequests, [{ kind: 'http', url: redirected }])
  // This is observation only. Browser-level redirect blocking needs real
  // counter verification of the configured deny proxy, not this stub test.
})

test('WebSockets connect unchanged only at selected ws origin, never off origin', async () => {
  const { page, handlers } = fakePage()
  const receipt = await installDownloadNetworkIsolation(page, origin)
  for (const [url, expected] of [
    ['ws://127.0.0.1:4173/?token=test', 'connect'],
    ['ws://127.0.0.1:4174/', 'close'],
    ['ws://127.0.0.1:54321/', 'close'],
    ['wss://127.0.0.1:4173/', 'close'],
    ['ws://localhost:4173/', 'close'],
    ['ws://example.invalid/', 'close'],
  ]) {
    const actions = []
    await handlers.ws({
      url: () => url,
      connectToServer: (...args) => { assert.deepEqual(args, []); actions.push('connect') },
      close: async options => { assert.equal(options.code, 1008); actions.push('close') },
    })
    assert.deepEqual(actions, [expected], url)
  }
  assert.equal(receipt.blockedRequests.length, 5)
})

test('serialized installer and full acceptance expression need no hidden module bindings', async () => {
  const installer = vm.runInNewContext(`(${installDownloadNetworkIsolation.toString()})`, { URL })
  const { page, handlers } = fakePage()
  const receipt = await installer(page, origin)
  assert.equal(receipt.allowedOrigin, origin)
  assert.equal(typeof handlers.http, 'function')
  const code = fs.readFileSync(new URL('./download-acceptance.js', import.meta.url), 'utf8')
    .replace('__DOWNLOAD_ORIGIN__', JSON.stringify(origin))
    .replace('__DOWNLOAD_NETWORK_INSTALL__', () => installDownloadNetworkIsolation.toString())
  const acceptance = vm.runInNewContext(`(${code})`, { URL })
  const instrumented = fakePage()
  const reached = new Error('first real browser operation after isolation')
  instrumented.page.on = () => {}
  instrumented.page.emulateMedia = async () => {
    assert.equal(typeof instrumented.handlers.http, 'function')
    assert.equal(typeof instrumented.handlers.ws, 'function')
    throw reached
  }
  await assert.rejects(acceptance(instrumented.page), error => error === reached)
})

function passingResult() {
  return {
    status: 'passed', origin, checks: 185, responseInterception: false, responseMocking: false,
    requestIsolation: {
      requestInterception: true, allowedOrigin: origin,
      allowedWebSocketOrigin: 'ws://127.0.0.1:4173', installedBeforeNavigation: true,
      blockedRequests: [],
    },
  }
}

test('validation requires all 185 checks and an honest request/response receipt', () => {
  validateDownloadResult(passingResult(), origin, 0)
  for (const overrides of [{ checks: 184 }, { checks: '185' }, { responseInterception: true }, { responseMocking: true }, { requestIsolation: undefined }, { status: 'failed' }]) {
    assert.throws(() => validateDownloadResult({ ...passingResult(), ...overrides }, origin, 0))
  }
  assert.throws(() => validateDownloadResult(passingResult(), origin, 1))
  const blocked = passingResult()
  blocked.requestIsolation.blockedRequests.push({ kind: 'http', url: 'http://127.0.0.1:54321/' })
  assert.throws(() => validateDownloadResult(blocked, origin, 0))
})

test('cleanup preserves the original acceptance failure, including non-Error throws', async () => {
  for (const original of [new Error('original acceptance failure'), undefined]) {
    const reports = []
    await assert.rejects(withDownloadCleanup(
      async () => { throw original },
      async () => { throw new Error('cleanup failure') },
      message => reports.push(message),
    ), error => error === original)
    assert.deepEqual(reports, ['Cleanup also failed: cleanup failure'])
  }
})

test('cleanup reporting failure cannot replace the original acceptance error', async () => {
  const original = new Error('acceptance failed')
  await assert.rejects(withDownloadCleanup(
    async () => { throw original },
    async () => { throw undefined },
    () => { throw new Error('reporter failed') },
  ), error => error === original)
})

test('cleanup failures fail an otherwise passing run and cleanup always runs', async () => {
  const cleanupError = new Error('close failed')
  await assert.rejects(withDownloadCleanup(async () => 'passed', async () => { throw cleanupError }), error => error === cleanupError)
  let cleaned = false
  assert.equal(await withDownloadCleanup(async () => 'result', async () => { cleaned = true }), 'result')
  assert.equal(cleaned, true)
})
