// Real-browser acceptance for the original Watch captures and bounded website tour.
async (page) => {
  const manifest = __WATCH_MANIFEST__
  const origin = new URL(page.url()).origin
  const publicHost = origin === 'https://hashfleet.app'
  if (!['http://127.0.0.1:4174', 'https://hashfleet.app'].includes(origin)) throw new Error('Unexpected test origin')
  const csp = "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; connect-src 'self'; object-src 'none'; base-uri 'self'; frame-ancestors 'none'; form-action 'self'"
  const checks = [], errors = [], failedRequests = [], requests = []
  const check = (condition, label) => { if (!condition) throw new Error(`Watch acceptance failed: ${label}`); checks.push(label) }
  const focused = locator => locator.evaluate(element => element === document.activeElement)
  page.on('pageerror', error => errors.push(error.message))
  page.on('console', message => { if (message.type() === 'error') errors.push(message.text()) })
  page.on('requestfailed', request => failedRequests.push(`${request.url()}: ${request.failure()?.errorText}`))
  page.on('request', request => requests.push({ url: request.url(), method: request.method() }))
  if (!publicHost) await page.route(`${origin}/`, async route => {
    const response = await route.fetch()
    await route.fulfill({ response, headers: { ...response.headers(), 'content-security-policy': csp } })
  })
  const panel = page.locator('#panel-watch')
  const tab = page.getByRole('tab', { name: 'Apple Watch', exact: true })
  const current = () => panel.locator('[data-watch-capture]').getAttribute('data-watch-capture')
  const decode = async () => {
    await page.waitForFunction(() => {
      const image = document.querySelector('#panel-watch [data-watch-capture]')
      return image?.complete && image.naturalWidth > 0
    })
    return panel.locator('[data-watch-capture]').evaluate(async image => { await image.decode(); return [image.naturalWidth, image.naturalHeight] })
  }
  try {
    await page.emulateMedia({ reducedMotion: 'reduce' })
    await page.setViewportSize({ width: 1440, height: 1000 })
    const response = await page.goto(origin, { waitUntil: 'networkidle' })
    check(response.status() === 200, 'Homepage returns 200')
    if (publicHost) check(response.headers()['content-security-policy'] === csp, 'Public CSP is unchanged and restrictive')
    await page.locator('h1').waitFor()
    check(JSON.stringify(await page.getByRole('tab').allTextContents()) === JSON.stringify(['Mac app', 'iPhone app', 'Apple Watch', 'Terminal']), 'Four correctly ordered product tabs')
    check(await panel.getAttribute('aria-labelledby') === 'tab-watch' && await tab.getAttribute('aria-controls') === 'panel-watch', 'Watch tab and panel are accessibly connected')
    check(await page.locator('.hero-watch img').getAttribute('src') === manifest.captures[0].src, 'Hero uses the original Watch fleet screenshot')
    check(await page.locator('.hero-watch img').evaluate(async image => { await image.decode(); return image.naturalWidth === 368 && image.naturalHeight === 448 }), 'Hero Watch capture decodes at its original resolution')
    await page.screenshot({ path: 'output/playwright/watch-landing-desktop-dark.png' })
    await page.getByRole('button', { name: 'Explore the captured Apple Watch screens', exact: true }).click()
    check(await tab.getAttribute('aria-selected') === 'true' && await focused(tab), 'Hero Watch opens and focuses the new Watch product tab')
    check(await page.locator('[role="tabpanel"]:visible').count() === 1 && await panel.isVisible(), 'Only the chosen Watch panel is visible')
    check(await current() === 'watch-fleet', 'Watch tour starts with the native fleet capture')
    check(await panel.getByRole('button', { name: 'Back', exact: true }).isDisabled(), 'History is empty initially')
    check(await panel.locator('[data-watch-step]').count() === 5, 'All five genuine screen choices are available')
    check((await panel.innerText()).includes('No network scan, miner connection or settings change happens here.'), 'Browser operation boundaries are visible')
    check((await panel.innerText()).includes('Captured times and readings do not update.'), 'Original timestamps and data are not misrepresented as live')
    check(await panel.locator('input, select, [role="switch"], iframe, canvas').count() === 0, 'Captured setup is not an invented live app or network input')

    const assets = await page.evaluate(async captures => Promise.all(captures.map(async capture => {
      const response = await fetch(capture.src, { cache: 'no-store' })
      const bytes = await response.arrayBuffer()
      const hash = [...new Uint8Array(await crypto.subtle.digest('SHA-256', bytes))].map(value => value.toString(16).padStart(2, '0')).join('')
      return { id: capture.id, status: response.status, mime: response.headers.get('content-type'), bytes: bytes.byteLength, hash }
    })), manifest.captures)
    for (const asset of assets) {
      const expected = manifest.captures.find(capture => capture.id === asset.id)
      check(asset.status === 200 && asset.mime?.startsWith('image/png') && asset.bytes === expected.bytes && asset.hash === expected.sha256 && asset.hash === expected.sourceSha256, `${asset.id}: served PNG is byte-identical to its original native attachment`)
    }

    for (const capture of manifest.captures) {
      const choice = panel.locator(`[data-watch-step="${capture.id}"]`)
      await choice.click()
      check(await current() === capture.id, `${capture.id}: step button chooses the right original image`)
      check(JSON.stringify(await decode()) === '[368,448]', `${capture.id}: full native dimensions decode`)
      check(await choice.getAttribute('aria-current') === 'step' && await panel.locator('[aria-current="step"]').count() === 1, `${capture.id}: exactly one step has the current marker`)
      await panel.locator('summary').click()
      check(await panel.locator('.native-transcript').getAttribute('open') !== null && (await panel.locator('.native-transcript p').innerText()).length > 80, `${capture.id}: accessible transcript is available`)
      await panel.locator('summary').click()
    }
    check(await panel.getByRole('button', { name: 'Next screen', exact: true }).isDisabled(), 'Next is disabled at the final captured screen')
    await panel.getByRole('button', { name: 'Back', exact: true }).click()
    check(await current() === 'watch-discovery', 'Back follows the real tour history')
    await panel.getByRole('button', { name: 'Reset tour', exact: true }).click()
    check(await current() === 'watch-fleet' && await panel.getByRole('button', { name: 'Back', exact: true }).isDisabled(), 'Reset restores fleet and clears history')
    await panel.getByRole('button', { name: 'Next screen', exact: true }).click()
    check(await current() === 'watch-miner', 'Next advances from fleet to miner detail')
    await panel.locator('[data-watch-target="watch-fleet"]').click()
    await page.waitForFunction(() => document.activeElement?.matches('#panel-watch h4'))
    check(await current() === 'watch-fleet', 'Captured back-button hotspot returns to fleet and focuses its updated heading')
    await panel.locator('[data-watch-step="watch-discovery"]').click()
    await decode()
    await panel.locator('[data-watch-target="watch-add"]').click()
    await page.waitForFunction(() => document.activeElement?.matches('#panel-watch h4'))
    check(await current() === 'watch-add', 'Captured Add miner hotspot opens the actual captured local-address screen')
    await decode()
    await panel.locator('[data-watch-target="watch-discovery"]').click()
    check(await current() === 'watch-discovery', 'Captured manual-setup back hotspot returns to captured local setup')
    await panel.getByRole('button', { name: 'Reset tour', exact: true }).click()
    await tab.focus()
    await page.keyboard.press('ArrowLeft')
    check(await focused(page.getByRole('tab', { name: 'iPhone app', exact: true })), 'Left arrow reaches the adjacent iPhone tab')
    await page.keyboard.press('ArrowRight')
    check(await focused(tab), 'Right arrow returns to Watch')
    await page.keyboard.press('ArrowRight')
    check(await focused(page.getByRole('tab', { name: 'Terminal', exact: true })), 'Right arrow reaches the adjacent Terminal tab')
    await page.keyboard.press('Home')
    check(await focused(page.getByRole('tab', { name: 'Mac app', exact: true })), 'Home still reaches Mac')
    await page.keyboard.press('End')
    check(await focused(page.getByRole('tab', { name: 'Terminal', exact: true })), 'End still reaches Terminal')
    await tab.click()
    await panel.locator('[data-watch-step="watch-status"]').focus()
    await page.keyboard.press('Enter')
    check(await current() === 'watch-status', 'Step choices work using the keyboard alone')

    for (const theme of ['dark', 'light']) {
      const currentTheme = await page.evaluate(() => document.documentElement.dataset.theme)
      if (currentTheme !== theme) await page.getByRole('button', { name: `Switch to ${theme} theme`, exact: true }).click()
      check(await page.evaluate(() => document.documentElement.dataset.theme) === theme, `${theme}: real theme button works`)
      for (const width of [320, 390, 768, 1024, 1440]) {
        await page.setViewportSize({ width, height: width <= 390 ? 844 : 1000 })
        await panel.getByRole('button', { name: 'Reset tour', exact: true }).click()
        await decode()
        check(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), `${width}px ${theme}: page has no horizontal overflow`)
        const layout = await panel.evaluate(panel => {
          const inside = node => { const rect = node.getBoundingClientRect(); return rect.width > 0 && rect.left >= -1 && rect.right <= window.innerWidth + 1 }
          return [...panel.querySelectorAll('[data-watch-step], .watch-tour-controls button, .watch-case')].every(inside)
        })
        check(layout, `${width}px ${theme}: Watch frame and all controls remain within the viewport`)
        check(await panel.locator('[data-watch-step], .watch-tour-controls button').evaluateAll(buttons => buttons.every(button => button.getBoundingClientRect().height >= 44)), `${width}px ${theme}: Watch navigation targets are at least 44px high`)
        check(await page.getByRole('tab').evaluateAll(tabs => tabs.every(tab => tab.getBoundingClientRect().width >= 44)), `${width}px ${theme}: four platform tabs remain usable`)
        await panel.locator('[data-watch-step="watch-miner"]').click()
        await decode()
        check(await current() === 'watch-miner', `${width}px ${theme}: tour remains interactive after resizing`)
        if ([390, 768, 1440].includes(width)) await panel.locator('[data-watch-tour]').screenshot({ path: `output/playwright/watch-tour-${width}-${theme}.png` })
        if ([320, 390, 1440].includes(width)) {
          await page.locator('.hero-scene').scrollIntoViewIfNeeded()
          await page.locator('.hero-scene').screenshot({ path: `output/playwright/watch-hero-${width}-${theme}.png` })
        }
      }
    }
    check(await page.locator('.hero-watch').evaluate(element => getComputedStyle(element).transitionDuration === '0s'), 'Reduced-motion preference disables Watch hover animation')
    await page.setViewportSize({ width: 1440, height: 1000 })
    await page.locator('.header-actions').getByRole('button', { name: 'Get Hash Fleet', exact: true }).click()
    const dialog = page.getByRole('dialog')
    check(await dialog.getByText('Hash Fleet for Apple Watch', { exact: true }).count() === 1 && await dialog.getByText('Included with the iOS app', { exact: true }).count() === 1, 'Get-app dialog includes the Watch without inventing a released download link')
    await page.keyboard.press('Escape')
    await page.waitForLoadState('networkidle')
    await page.reload({ waitUntil: 'networkidle' })
    await tab.click()
    check(await current() === 'watch-fleet' && await panel.getByRole('button', { name: 'Back', exact: true }).isDisabled(), 'Reload does not persist tour choices or history')
    check(await page.evaluate(() => localStorage.length === 0 && sessionStorage.length === 0 && document.cookie === ''), 'Watch demo creates no storage or cookies')
    check(requests.every(request => new URL(request.url).origin === origin && request.method === 'GET' && !new URL(request.url).pathname.startsWith('/api/')), 'The tour requests only same-origin static GET resources, never a device or backend API')
    check(errors.length === 0, 'No browser runtime or console errors')
    check(failedRequests.length === 0, 'No failed requests in actual normal operation')

    // Separate, explicitly intercepted failure fixture. All public normal-operation checks above are real responses.
    const failurePage = await page.context().newPage()
    let imageFailureRecovery = false
    try {
      const path = manifest.captures.find(capture => capture.id === 'watch-add').src
      await failurePage.route(`${origin}${path}`, route => route.fulfill({ status: 200, contentType: 'image/png', body: 'deliberately-invalid-image-fixture' }))
      await failurePage.goto(origin, { waitUntil: 'networkidle' })
      await failurePage.getByRole('tab', { name: 'Apple Watch', exact: true }).click()
      await failurePage.locator('[data-watch-step="watch-add"]').click()
      await failurePage.getByRole('alert').filter({ hasText: 'This Watch capture could not be loaded.' }).waitFor()
      check(await failurePage.locator('#panel-watch [data-watch-target]').count() === 0, 'Failed image removes navigation hotspots instead of leaving misleading invisible targets')
      await failurePage.unroute(`${origin}${path}`)
      await failurePage.getByRole('button', { name: 'Reload capture', exact: true }).click()
      await failurePage.waitForFunction(() => { const image = document.querySelector('#panel-watch [data-watch-capture]'); return image?.complete && image.naturalWidth === 368 })
      imageFailureRecovery = await failurePage.locator('[data-watch-capture]').getAttribute('data-watch-capture') === 'watch-add'
      check(imageFailureRecovery, 'Reload capture recovers the actual original image after a bounded simulated image failure')
    } finally { await failurePage.close() }
    const result = { status: 'passed', origin, checks: checks.length, labels: checks, nativeCaptures: assets.length, assets, browserErrors: errors, failedRequests, normalOperationResponseInterception: !publicHost, isolatedFailureFixture: true, imageFailureRecovery, noDeviceOrStoreChanges: true }
    await page.evaluate(result => { window.__hashfleetWatchAcceptance = result }, result)
  } catch (error) {
    await page.evaluate(result => { window.__hashfleetWatchAcceptance = result }, { status: 'failed', origin, checks: checks.length, labels: checks, browserErrors: errors, failedRequests, error: String(error) })
    throw error
  }
}
