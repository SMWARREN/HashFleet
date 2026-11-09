async (page) => {
  const currentOrigin = new URL(page.url()).origin
  const localOrigins = ['http://127.0.0.1:4174', 'http://127.0.0.1:4175']
  const publicOrigin = 'https://hashfleet.app'
  const allowedOrigins = [...localOrigins, publicOrigin]
  if (!allowedOrigins.includes(currentOrigin)) {
    throw new Error(`Unsupported acceptance origin ${currentOrigin}. Open the intended test URL first.`)
  }

  const origin = currentOrigin
  const isPublicHost = origin === publicOrigin
  const csp = "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; connect-src 'self'; object-src 'none'; base-uri 'self'; frame-ancestors 'none'; form-action 'self'"
  const checks = []
  const errors = []
  const failedRequests = []
  const requests = []
  const check = (value, label) => {
    if (!value) throw new Error(`Acceptance failed: ${label}`)
    checks.push(label)
  }
  const textIncludes = async (locator, text, label) => check((await locator.innerText()).includes(text), label)
  const focused = async (locator) => locator.evaluate(element => document.activeElement === element)

  page.on('pageerror', error => errors.push(error.message))
  page.on('console', message => { if (message.type() === 'error') errors.push(message.text()) })
  page.on('request', request => requests.push({ url: request.url(), method: request.method() }))
  page.on('requestfailed', request => failedRequests.push(`${request.url()}: ${request.failure()?.errorText ?? 'failed'}`))

  if (!isPublicHost) {
    await page.route(`${origin}/`, async route => {
      const response = await route.fetch()
      await route.fulfill({
        response,
        headers: { ...response.headers(), 'content-security-policy': csp },
      })
    })
  }

  await page.emulateMedia({ reducedMotion: 'reduce' })
  await page.setViewportSize({ width: 1440, height: 1000 })
  const navigationResponse = await page.goto(origin)
  check(navigationResponse?.status() === 200, 'Website entry point returns the production homepage')
  if (isPublicHost) check(navigationResponse?.headers()['content-security-policy'] === csp, 'Public host serves the required CSP')

  await page.getByRole('heading', { level: 1 }).waitFor()
  if (!isPublicHost) check((await page.locator('html').getAttribute('data-theme')) === 'dark', 'Local production preview defaults to dark theme')
  check(await page.title() === 'Hash Fleet | Your hash. Your hardware.', 'Hash Fleet page title')
  check(await page.locator('h1').count() === 1, 'One primary heading')
  check(await page.getByRole('link', { name: 'Hash Fleet home' }).count() === 2, 'Hash Fleet wordmark appears in header and footer')
  check(await page.locator('img[src="/images/brand.png"]').count() >= 1, 'Hash Fleet brand asset is rendered')
  const artwork = page.locator('img[alt*="miner artwork"]')
  check(await artwork.count() === 1, 'Fleet status artwork has an accessible description')
  await artwork.scrollIntoViewIfNeeded()
  await artwork.evaluate(image => image.decode?.())
  check(await page.locator('img').evaluateAll(images => images.every(image => image.complete && image.naturalWidth > 0)), 'Rendered image assets load successfully')
  check(await page.locator('[role="tab"]').count() === 3, 'Three platform tabs')
  check(await page.locator('[role="tabpanel"]:visible').count() === 1, 'Only the selected platform panel is visible')
  check(await page.evaluate(() => [...document.querySelectorAll('[aria-controls]')].every(element => document.getElementById(element.getAttribute('aria-controls')))), 'Every tab controls an existing panel')
  await page.screenshot({ path: 'output/playwright/public-parity-landing.png', fullPage: false })

  const headerDownload = page.locator('.header-actions').getByRole('button', { name: 'Get Hash Fleet' })
  await headerDownload.click()
  await page.getByRole('dialog').waitFor()
  const downloadDialog = page.getByRole('dialog')
  check(await downloadDialog.getByText('Preview above · public build soon', { exact: true }).count() === 1 && await downloadDialog.getByText('Coming soon', { exact: true }).count() === 1, 'Unavailable releases are honestly labeled')
  check(await focused(page.getByRole('button', { name: 'Close dialog' })), 'Dialog starts with focus inside')
  await page.keyboard.press('Escape')
  await page.getByRole('dialog').waitFor({ state: 'detached' })
  check(await focused(headerDownload), 'Escape restores dialog invoker focus')

  const macTab = page.getByRole('tab', { name: 'Mac app', exact: true })
  const phoneTab = page.getByRole('tab', { name: 'iPhone app', exact: true })
  const terminalTab = page.getByRole('tab', { name: 'Terminal', exact: true })
  await page.getByRole('button', { name: 'Take it for a spin' }).click()
  await page.locator('#tab-mac[aria-selected="true"]').waitFor()
  check(await focused(macTab), 'Mac CTA transfers focus to its demo tab')
  await macTab.focus()
  await macTab.press('ArrowRight')
  await page.locator('#tab-iphone[aria-selected="true"]').waitFor()
  check(await focused(phoneTab), 'ArrowRight selects and focuses the next tab')
  await phoneTab.press('End')
  await page.locator('#tab-terminal[aria-selected="true"]').waitFor()
  check(await focused(terminalTab), 'End selects the last tab')
  await terminalTab.press('Home')
  await page.locator('#tab-mac[aria-selected="true"]').waitFor()
  check(await focused(macTab), 'Home selects the first tab')

  const mac = page.locator('#panel-mac')
  check(await mac.locator('.miner-row').count() === 3, 'Mac preview contains the three native demo miners')
  await textIncludes(mac.locator('.app-summary'), '3.02', 'Mac preview shows native 3.02 TH/s total')
  await textIncludes(mac.locator('.app-summary'), '51 W', 'Mac preview shows native 51 W total')
  await textIncludes(mac, 'Workshop Gamma', 'Mac preview shows Workshop Gamma')
  await textIncludes(mac, 'Office Gamma', 'Mac preview shows Office Gamma')
  await textIncludes(mac, 'Little Supra', 'Mac preview shows Little Supra')
  check((await mac.innerText()).includes('No CPU host') && !(await mac.innerText()).includes('22.10'), 'Mac preview keeps ASIC-only totals separate from stale fleet values')
  await mac.getByRole('button', { name: '24h', exact: true }).click()
  check(await mac.getByRole('img', { name: /Illustrative 24h/ }).count() === 1, 'Mac chart range changes the labeled illustration')
  await mac.getByRole('button', { name: 'Inspect Workshop Gamma', exact: true }).click()
  check(await focused(mac.getByRole('button', { name: 'Back to fleet' })), 'Mac miner detail starts with a focused back control')
  await textIncludes(mac, 'gamma-demo.invalid', 'Mac miner detail shows the reserved demo host')
  await mac.getByRole('button', { name: 'Back to fleet' }).click()
  check(await focused(mac.getByRole('button', { name: 'Inspect Workshop Gamma', exact: true })), 'Mac miner detail returns focus to its trigger')

  await mac.getByRole('button', { name: /My miners/ }).click()
  const search = mac.getByRole('searchbox', { name: 'Search sample miners' })
  await search.fill('Office')
  check(await mac.locator('.miner-row').count() === 1, 'Mac search filters to one native sample')
  await search.fill('no-matching-sample')
  await textIncludes(mac.locator('.empty-state'), 'No sample miners match', 'Mac empty search state explains the result')
  await search.fill('')
  check(await mac.locator('.miner-row').count() === 3, 'Clearing Mac search restores all native samples')

  await mac.getByRole('button', { name: 'Energy', exact: true }).click()
  const fullSlider = mac.getByRole('slider', { name: /Electricity rate/ })
  check(await fullSlider.evaluate(element => element.labels[0]?.control === element), 'Energy label targets its own slider')
  await fullSlider.focus()
  await fullSlider.press('End')
  await textIncludes(mac.locator('.energy-result'), '$0.61', 'Energy slider updates the daily estimate')
  await fullSlider.press('Home')
  await textIncludes(mac.locator('.energy-result'), '$0.01', 'Energy slider handles the lowest rate')
  await mac.getByRole('button', { name: 'Overview', exact: true }).click()

  await phoneTab.click()
  const phone = page.locator('#panel-iphone')
  check(await phone.locator('.phone-miner').count() === 3, 'iPhone preview contains the three native demo miners')
  check(await phone.getByText('3.02 TH/s', { exact: true }).count() >= 1, 'iPhone preview shows native 3.02 TH/s total')
  check(await phone.getByText('51 W', { exact: true }).count() >= 1, 'iPhone preview shows native 51 W total')
  check(await phone.getByText('16.8 J/TH', { exact: true }).count() === 1, 'iPhone preview shows native 16.8 J/TH efficiency')
  check(await phone.getByText('TOTAL POWER', { exact: true }).count() === 1 && await phone.getByText('EFFICIENCY', { exact: true }).count() === 1, 'iPhone metrics use the native labels')
  check(await phone.locator('.phone-hash-card .hash-chart').count() === 0, 'iPhone hash card does not invent a native chart')
  const phoneTabLabels = (await phone.locator('.phone-tab-bar button').allTextContents()).map(label => label.trim())
  check(JSON.stringify(phoneTabLabels) === JSON.stringify(['Fleet', 'Settings', 'About']), 'iPhone navigation is exactly Fleet, Settings, About')
  await phone.getByRole('button', { name: 'Inspect Workshop Gamma on iPhone', exact: true }).click()
  check(await focused(phone.getByRole('button', { name: 'Back to fleet' })), 'iPhone miner detail starts with a focused back control')
  await phone.getByRole('button', { name: 'Back to fleet' }).click()
  check(await focused(phone.getByRole('button', { name: 'Inspect Workshop Gamma on iPhone', exact: true })), 'iPhone miner detail returns focus to its trigger')
  const expandedHeight = (await phone.locator('.phone-miner').first().boundingBox())?.height ?? 0
  await phone.getByRole('button', { name: 'Settings', exact: true }).click()
  await textIncludes(phone.locator('.phone-settings-page'), 'Widgets', 'iPhone Settings exposes the native widget section')
  await phone.getByRole('checkbox', { name: 'Compact miner cards' }).check()
  await phone.getByRole('button', { name: 'Fleet', exact: true }).click()
  check(await phone.locator('.compact-cards').count() === 1, 'iPhone preference changes card layout')
  check(((await phone.locator('.phone-miner').first().boundingBox())?.height ?? expandedHeight) < expandedHeight, 'Compact iPhone cards become shorter')
  await phone.getByRole('button', { name: 'Settings', exact: true }).click()
  await phone.getByRole('button', { name: /Restart device/ }).click()
  check(await phone.getByText('POST /api/system/restart', { exact: true }).count() === 1, 'Restart review shows the native endpoint')
  check(await phone.getByText('gamma-demo.invalid', { exact: true }).count() === 1, 'Restart review uses the reserved demo target')
  await textIncludes(phone, 'Unverified on this firmware', 'Restart review warns about firmware capability')
  await textIncludes(phone, 'Requests are never retried as a different endpoint.', 'Restart review explains endpoint safety')
  await textIncludes(phone, 'writes are locked and explorer requests never contact a device', 'Demo restart remains read-only')
  await phone.getByRole('button', { name: 'Back to fleet' }).click()

  await terminalTab.click()
  const terminal = page.locator('#panel-terminal')
  const command = terminal.getByRole('textbox', { name: 'Terminal command' })
  const lastResult = () => terminal.locator('.terminal-demo__result').last()
  await command.fill('hashfleet status --json')
  await command.press('Enter')
  const snapshot = JSON.parse(await lastResult().innerText())
  check(snapshot.miners.length === 3, 'Terminal JSON contains the three native demo miners')
  check(snapshot.miners.every(miner => miner.device.kind === 'espMiner'), 'Terminal JSON contains ASIC-only sample kinds')
  check(snapshot.miners.every(miner => /\.invalid$/.test(miner.device.address)), 'Terminal JSON contains reserved fictional hosts')
  await command.fill('hashfleet status gamma-demo.invalid office-demo.invalid')
  await command.press('Enter')
  await textIncludes(lastResult(), '2/2 online', 'Terminal explicit host filtering uses native fixture hosts')
  await command.fill('hashfleet status cpu-demo.invalid')
  await command.press('Enter')
  await textIncludes(lastResult(), 'Nothing was executed', 'Terminal rejects unknown hosts without execution')
  await command.fill('hashfleet status; echo unsafe')
  await command.press('Enter')
  await textIncludes(lastResult(), 'Nothing was executed', 'Terminal rejects shell syntax without execution')
  await terminal.getByRole('button', { name: 'hashfleet --help', exact: true }).click()
  await textIncludes(lastResult(), 'Browser demo utilities only', 'Terminal help distinguishes browser utilities')
  await terminal.getByRole('button', { name: 'Clear panel, browser demo utility' }).click()
  check(await terminal.locator('.terminal-demo__entry').count() === 0, 'Terminal clear utility empties only the panel')
  await terminal.getByRole('button', { name: 'hashfleet status', exact: true }).click()
  await textIncludes(lastResult(), '3/3 online', 'Terminal remains usable after clear')

  for (const details of await page.locator('.faq-list details').all()) {
    await details.locator('summary').click()
    check(await details.getAttribute('open') !== null, 'FAQ opens with its native disclosure control')
    await details.locator('summary').click()
  }
  const privacyButton = page.getByRole('button', { name: 'Privacy', exact: true })
  await privacyButton.click()
  await textIncludes(page.getByRole('dialog'), 'fictional readings', 'Privacy explains demo data honestly')
  await page.getByRole('button', { name: 'Close dialog' }).click()
  await page.getByRole('dialog').waitFor({ state: 'detached' })
  check(await focused(privacyButton), 'Privacy dialog restores footer focus')

  await page.getByRole('button', { name: 'Switch to light theme' }).click()
  check(await page.evaluate(() => document.documentElement.dataset.theme) === 'light', 'Light theme remains an explicit opt-in')
  await page.getByRole('button', { name: 'Switch to dark theme' }).click()
  check(await page.evaluate(() => document.documentElement.dataset.theme) === 'dark', 'Dark theme can be restored')

  for (const width of [1440, 1024, 768, 375, 320]) {
    await page.setViewportSize({ width, height: width < 640 ? 812 : 1000 })
    for (const [tab, name] of [[macTab, 'Mac'], [phoneTab, 'iPhone'], [terminalTab, 'Terminal']]) {
      await tab.click()
      const dimensions = await page.evaluate(() => ({ viewport: window.innerWidth, page: document.documentElement.scrollWidth }))
      check(dimensions.page <= dimensions.viewport, `${name} at ${width}px has no page-wide horizontal overflow`)
    }
    if (width === 375) {
      await page.evaluate(() => window.scrollTo(0, 0))
      await page.screenshot({ path: 'output/playwright/public-parity-mobile-375.png', fullPage: false })
    }
  }

  const menuButton = page.getByRole('button', { name: 'Open navigation' })
  await menuButton.click()
  check(await page.getByRole('button', { name: 'Close navigation' }).getAttribute('aria-expanded') === 'true', 'Mobile menu opens')
  await page.getByRole('navigation', { name: 'Main navigation', exact: true }).getByRole('link', { name: 'Features' }).click()
  check(await page.getByRole('button', { name: 'Open navigation' }).getAttribute('aria-expanded') === 'false', 'Mobile navigation closes after selection')
  check(await page.evaluate(() => {
    const ids = [...document.querySelectorAll('[id]')].map(element => element.id)
    return new Set(ids).size === ids.length
  }), 'All rendered IDs are unique')
  check((await page.context().cookies(origin)).length === 0, 'Website does not set cookies')
  check(failedRequests.length === 0, `No failed asset requests: ${failedRequests.join(', ')}`)
  check(requests.every(request => request.url.startsWith(`${origin}/`) && request.method === 'GET'), 'Preview only requests same-origin GET assets')
  check(requests.every(request => !/192\.168\.|10\.\d+\.\d+\.|stratum\.|solo\.ckpool/.test(request.url)), 'Preview makes no live-fleet or pool requests')
  check(errors.length === 0, `No browser or CSP errors: ${errors.join(', ')}`)

  await page.setViewportSize({ width: 1440, height: 1000 })
  await macTab.click()
  await page.evaluate(() => window.scrollTo(0, 0))
  await page.screenshot({ path: 'output/playwright/public-parity-final.png', fullPage: false })
  return await page.evaluate(result => {
    window.__hashfleetAcceptance = result
    return result
  }, {
    status: 'passed',
    origin,
    cspSource: isPublicHost ? 'server-response' : 'injected-preview-test',
    checks: checks.length,
    cases: checks,
    requests: [...new Set(requests.map(request => `${request.method} ${request.url}`))],
    browserErrors: errors,
    failedRequests,
  })
}
