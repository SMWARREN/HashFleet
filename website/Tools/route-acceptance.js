// Actual Apache/production responses only. No response interception or injected CSP.
async (page) => {
  const origin = new URL(page.url()).origin
  if (!['http://127.0.0.1:4175', 'https://hashfleet.app'].includes(origin)) throw new Error('Unsupported route acceptance origin')
  const checks = []
  const errors = []
  const failedRequests = []
  const requests = []
  const headers = {
    'x-content-type-options': 'nosniff',
    'x-frame-options': 'DENY',
    'referrer-policy': 'no-referrer',
    'permissions-policy': 'camera=(), microphone=(), geolocation=()',
    'content-security-policy': "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; connect-src 'self'; object-src 'none'; base-uri 'self'; frame-ancestors 'none'; form-action 'self'",
  }
  const check = (value, label) => { if (!value) throw new Error(`Route acceptance: ${label}`); checks.push(label) }
  page.on('pageerror', error => errors.push(error.message))
  page.on('requestfailed', request => failedRequests.push(request.url()))
  page.on('request', request => requests.push({ url: request.url(), method: request.method() }))
  async function visit(route, status) {
    const response = await page.goto(origin + route)
    check(response?.status() === status, `${route} retains HTTP ${status}`)
    check(response.request().redirectedFrom() === null, `${route} is internal, not an external redirect`)
    check(new URL(page.url()).pathname === route, `${route} remains in the address bar`)
    for (const [name, value] of Object.entries(headers)) check(response.headers()[name] === value, `${route} ${name}`)
    await page.getByRole('heading', { level: 1 }).waitFor()
    check(await page.locator('h1').count() === 1, `${route} has one main heading`)
  }
  try {
    await page.emulateMedia({ reducedMotion: 'reduce' })
    await page.setViewportSize({ width: 1440, height: 1000 })
    for (const [route, platform] of [['/demo', 'mac'], ['/demo/mac', 'mac'], ['/demo/iphone', 'iphone'], ['/demo/terminal', 'terminal']]) {
      await visit(route, 200)
      check(await page.locator(`#tab-${platform}`).getAttribute('aria-selected') === 'true', `${route} selects the URL's preview`)
      check(await page.locator('[role="tabpanel"]:visible').getAttribute('id') === `panel-${platform}`, `${route} shows only that preview`)
      await page.waitForFunction(() => document.querySelector('#demo').getBoundingClientRect().top < 120)
      check(await page.locator('[data-route-unavailable]').count() === 0, `${route} is not an error page`)
    }
    for (const [route, status] of [['/.env.local', 403], ['/.git/config', 403], ['/.htaccess', 403], ['/missing-native-parity-page', 404], ['/demo/unknown', 404]]) {
      await visit(route, status)
      check(await page.locator('[data-route-unavailable]').count() === 1, `${route} renders the React unavailable view`)
      check(await page.locator('h1').innerText() === 'This page isn’t available.', `${route} does not masquerade as the homepage`)
      check(await page.title() === 'Page unavailable | Hash Fleet', `${route} gets a safe title`)
      check(await page.locator('meta[name="robots"]').getAttribute('content') === 'noindex', `${route} is not indexed`)
      check(await page.getByRole('link', { name: 'Back to Hash Fleet', exact: true }).getAttribute('href') === '/', `${route} offers a fixed same-origin recovery link`)
    }
    await page.setViewportSize({ width: 320, height: 780 })
    check(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), 'Unavailable view fits a 320px screen')
    await page.getByRole('link', { name: 'Back to Hash Fleet', exact: true }).focus()
    await page.keyboard.press('Enter')
    await page.waitForURL(origin + '/')
    check(await page.title() === 'Hash Fleet | Your hash. Your hardware.', 'Keyboard recovery returns to the original homepage')
    check(await page.locator('meta[name="robots"]').count() === 0, 'Error-page noindex does not persist on the homepage')
    check(await page.locator('#tab-mac').getAttribute('aria-selected') === 'true', 'Homepage keeps the original Mac default')
    check(requests.every(request => new URL(request.url).origin === origin && request.method === 'GET'), 'Only same-origin GET requests occurred')
    check(requests.every(request => !new URL(request.url).pathname.startsWith('/api/')), 'No actual service API was contacted')
    check(await page.evaluate(() => localStorage.length === 0 && sessionStorage.length === 0 && document.cookie === ''), 'No cookies or browser storage')
    check(errors.length === 0 && failedRequests.length === 0, 'No runtime errors or unexpected failed requests')
    await page.evaluate(result => { window.__hashfleetRouteAcceptance = result }, { status: 'passed', origin, checks: checks.length, responseInterception: false, browserErrors: errors, failedRequests })
  } catch (error) {
    await page.evaluate(result => { window.__hashfleetRouteAcceptance = result }, { status: 'failed', origin, checks: checks.length, error: String(error), browserErrors: errors, failedRequests })
    throw error
  }
}
