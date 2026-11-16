import assert from 'node:assert/strict'
import net from 'node:net'

const origins = ['http://127.0.0.1:4173', 'http://127.0.0.1:4174']
// Chromium uses the last --disable-features switch. Retain the installed
// Playwright 1.66.0-alpha-1794252756000 defaults instead of replacing them.
// Revalidate these and the strict proxy counter when upgrading the CLI.
const disabledFeatures = [
  'AvoidUnnecessaryBeforeUnloadCheckSync', 'DestroyProfileOnBrowserClose',
  'HttpsUpgrades', 'HttpsFirstBalancedModeAutoEnable', 'LensOverlay', 'MediaRouter',
  'PaintHolding', 'ThirdPartyStoragePartitioning', 'AvoidCorsURLLoaderRestartOnRedirect',
  'TcpPortRandomizationWin', 'OptimizationHints', 'NetworkTimeServiceQuerying',
  'AimEnabled', 'PreconnectToSearch', 'msForceBrowserSignIn',
  'msEdgeUpdateLaunchServicesPreferredVersion', 'AutofillServerCommunication',
]

export function downloadBrowserConfig(origin, proxyServer) {
  assert(origins.includes(origin), 'Only an exact documented loopback origin is allowed')
  assert(/^http:\/\/127\.0\.0\.1:[1-9][0-9]*$/.test(proxyServer), 'A local deny proxy is required')
  return {
    browser: {
      browserName: 'chromium',
      isolated: true,
      // Chrome autofill queries bypass page request events. Disable them only
      // in this fresh test browser, never in the operator's normal profile.
      launchOptions: { channel: 'chrome', args: [`--disable-features=${disabledFeatures.join(',')}`] },
      contextOptions: {
        serviceWorkers: 'block',
        proxy: {
          server: proxyServer,
          // Chromium normally bypasses proxies for *all* loopback addresses.
          // Subtract that implicit rule before adding these exact exceptions.
          bypass: `<-loopback>,${origin},${origin.replace('http:', 'ws:')}`,
        },
      },
    },
  }
}

// No HTTP response, CONNECT tunnel, DNS lookup or outbound socket is created.
// Off-origin redirect hops can bypass Playwright route handlers, but not this
// context proxy. The selected origin alone bypasses it and stays unmodified.
export function rejectProxySocket(socket, counters) {
  counters.deniedConnections++
  socket.destroy()
}

export async function startDownloadDenyProxy() {
  const counters = { deniedConnections: 0 }
  const server = net.createServer(socket => rejectProxySocket(socket, counters))
  await new Promise((resolve, reject) => {
    server.once('error', reject)
    server.listen(0, '127.0.0.1', resolve)
  })
  return {
    server: `http://127.0.0.1:${server.address().port}`,
    counters,
    close: () => new Promise((resolve, reject) => server.close(error => error ? reject(error) : resolve())),
  }
}

// Serialized into the CLI's single async-page expression. Keep self-contained.
export async function installDownloadNetworkIsolation(page, origin) {
  if (!['http://127.0.0.1:4173', 'http://127.0.0.1:4174'].includes(origin)) throw new Error('Unsupported acceptance origin')
  const context = page.context()
  if (page.url() !== 'about:blank' || context.pages().some(item => item.url() !== 'about:blank')) throw new Error('Install isolation before the first website navigation')
  if (typeof context.route !== 'function' || typeof context.routeWebSocket !== 'function') throw new Error('HTTP and WebSocket routing support is required')
  const blockedRequests = []
  const allowedWebSocketOrigin = origin.replace('http:', 'ws:')
  function allowed(url, websocket = false) {
    try {
      const target = new URL(url)
      return !target.username && !target.password && target.origin === (websocket ? allowedWebSocketOrigin : origin)
    } catch {
      return false
    }
  }
  // Observe context-wide requests as well: redirect hops are not routed again.
  context.on('request', request => {
    if (!allowed(request.url())) blockedRequests.push({ kind: 'http', url: request.url() })
  })
  await context.route('**/*', async route => {
    if (allowed(route.request().url())) await route.continue()
    else await route.abort('blockedbyclient')
  })
  await context.routeWebSocket('**/*', async socket => {
    if (allowed(socket.url(), true)) socket.connectToServer()
    else {
      blockedRequests.push({ kind: 'websocket', url: socket.url() })
      await socket.close({ code: 1008, reason: 'Acceptance origin is not authorized' })
    }
  })
  return {
    requestInterception: true,
    responseInterception: false,
    responseMocking: false,
    allowedOrigin: origin,
    allowedWebSocketOrigin,
    installedBeforeNavigation: true,
    blockedRequests,
  }
}

export function validateDownloadResult(result, origin, deniedConnections) {
  assert(result?.status === 'passed' && result.origin === origin && Number.isInteger(result.checks) && result.checks >= 185, 'Real browser acceptance did not pass all 185 checks')
  assert(result.responseInterception === false && result.responseMocking === false, 'Responses must remain real and unmodified')
  const isolation = result.requestIsolation
  assert(isolation?.requestInterception === true && isolation.allowedOrigin === origin &&
    isolation.allowedWebSocketOrigin === origin.replace('http:', 'ws:') && isolation.installedBeforeNavigation === true,
  'Missing exact-origin request isolation receipt')
  assert(Array.isArray(isolation.blockedRequests) && isolation.blockedRequests.length === 0 && deniedConnections === 0,
    'Off-origin traffic was attempted during acceptance')
}

// Preserve the acceptance error, even when browser/sink cleanup also fails.
export async function withDownloadCleanup(work, cleanup, reportCleanup = console.error) {
  let failed = false
  try {
    return await work()
  } catch (error) {
    failed = true
    throw error
  } finally {
    try {
      await cleanup()
    } catch (error) {
      if (!failed) throw error
      try {
        reportCleanup(`Cleanup also failed: ${error?.message ?? String(error)}`)
      } catch {
        // Even a failed diagnostic must not replace the original failure.
      }
    }
  }
}
