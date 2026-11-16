// Real browser acceptance with request isolation, never mocked/fulfilled responses.
async (page) => {
  const origin = __DOWNLOAD_ORIGIN__
  const requestIsolation = await (__DOWNLOAD_NETWORK_INSTALL__)(page, origin)
  const checks = []
  const browserErrors = []
  const failedRequests = []
  const externalRequests = requestIsolation.blockedRequests
  page.on('pageerror', error => browserErrors.push(error.message))
  page.on('console', message => { if (message.type() === 'error') browserErrors.push(message.text()) })
  page.on('requestfailed', request => failedRequests.push({ url: request.url(), error: request.failure()?.errorText }))
  function check(condition, description) {
    if (!condition) throw new Error(description)
    checks.push(description)
  }
  let loads = 0
  async function openDownload() {
    const response = await page.goto(`${origin}/?download-acceptance=${++loads}#download`)
    check(response.status() === 200, 'Real local page returns HTTP 200')
    await page.locator('dialog[open] #dialog-title').waitFor()
    await page.waitForLoadState('networkidle')
    check(await page.locator('#dialog-title').textContent() === 'Download Hash Fleet', 'Download fragment opens the actual dialog')
  }
  await page.emulateMedia({ reducedMotion: 'reduce' })
  const sizes = [[1440, 1000], [768, 1024], [390, 844], [320, 740], [844, 390]]
  const layouts = []
  for (const [width, height] of sizes) {
    await page.setViewportSize({ width, height })
    await openDownload()
    const layout = await page.locator('dialog[open]').evaluate(dialog => {
      const bounds = dialog.getBoundingClientRect()
      return {
        viewport: [innerWidth, innerHeight],
        bounds: { x: bounds.x, y: bounds.y, width: bounds.width, height: bounds.height },
        pageOverflow: document.documentElement.scrollWidth > innerWidth,
        dialogOverflow: dialog.scrollWidth > dialog.clientWidth + 1,
        sectionOrder: [...dialog.querySelectorAll('section h3')].map(item => item.textContent),
      }
    })
    check(!layout.pageOverflow && !layout.dialogOverflow, `${width}x${height}: no horizontal page/dialog overflow`)
    check(layout.bounds.x >= 0 && layout.bounds.x + layout.bounds.width <= width + 1 && layout.bounds.y >= 0 && layout.bounds.y + layout.bounds.height <= height + 1, `${width}x${height}: dialog stays inside viewport`)
    check(JSON.stringify(layout.sectionOrder) === JSON.stringify(['App Store', 'Native Mac', 'Terminal CLI']), `${width}x${height}: compact App Store-first section order`)
    check(await page.locator('[data-download="mac-store"] a, [data-download="mac-store"] button').count() === 0, `${width}x${height}: pending Mac Store has no download action`)
    const pendingText = await page.locator('[data-download="mac-store"]').innerText()
    check(pendingText.includes('Awaiting approval') && pendingText.includes('not yet released'), `${width}x${height}: native Mac approval is explicit`)
    check((await page.locator('.download-options').innerText()).includes('Apple Watch included with the iOS app · watchOS 26.5+'), `${width}x${height}: Watch inclusion and compatibility are clear`)
    check(!/Designed for iPad|iPad version on Mac|unsigned/i.test(await page.locator('.download-options').innerText()), `${width}x${height}: no misleading native Mac or signing copy`)
    for (const selector of ['.dialog-close', '.download-options a']) {
      const controls = page.locator(selector)
      for (let index = 0; index < await controls.count(); index++) {
        const control = controls.nth(index)
        await control.scrollIntoViewIfNeeded()
        const bounds = await control.boundingBox()
        check(bounds && bounds.height >= 44 && bounds.width >= 44, `${width}x${height}: ${selector}[${index}] has 44px target`)
        check(await control.isVisible(), `${width}x${height}: ${selector}[${index}] remains reachable when scrolled`)
      }
    }
    const links = await page.locator('.download-options a').evaluateAll(items => items.map(item => ({ label: item.textContent.trim(), href: item.href, target: item.target, rel: item.rel })))
    check(links[0].href === 'https://apps.apple.com/us/app/hash-fleet/id6812623943', `${width}x${height}: first action is the released iOS listing`)
    check(links.find(link => link.label.startsWith('Download .zip'))?.href === 'https://github.com/SMWARREN/HashFleet/releases/latest/download/HashFleet-macos-arm64.zip', `${width}x${height}: native Mac points at real ZIP alias`)
    check(links.find(link => link.label.startsWith('Download .tar.gz'))?.href === 'https://github.com/SMWARREN/HashFleet/releases/latest/download/hashfleet-cli-macos-arm64.tar.gz', `${width}x${height}: CLI points at separate real tarball alias`)
    check(links.some(link => link.label.startsWith('Checksums') && link.href.endsWith('/SHA256SUMS.txt')), `${width}x${height}: checksum manifest is discoverable`)
    check(links.every(link => link.href.startsWith('https://') && link.target === '_blank' && link.rel.includes('noopener') && link.rel.includes('noreferrer')), `${width}x${height}: external link boundaries preserved`)
    layouts.push(layout)
  }
  await page.setViewportSize({ width: 1440, height: 1000 })
  await page.goto(origin)
  await page.waitForLoadState('networkidle')
  const invoker = page.locator('header.site-header').getByRole('button', { name: 'Get Hash Fleet', exact: true })
  await invoker.click()
  check(new URL(page.url()).hash === '#download', 'Homepage CTA updates the addressable fragment')
  await page.locator('dialog[open]').waitFor()
  await page.waitForFunction(() => document.activeElement?.matches('.dialog-close'))
  check(await page.locator('.dialog-close').evaluate(item => item === document.activeElement), 'Dialog initially focuses its close control')
  await page.keyboard.press('Shift+Tab')
  check(await page.locator('.download-options__footer a').last().evaluate(item => item === document.activeElement), 'Shift+Tab wraps to last dialog link')
  await page.keyboard.press('Tab')
  check(await page.locator('.dialog-close').evaluate(item => item === document.activeElement), 'Tab wraps to first dialog control')
  for (let index = 0; index < 10; index++) {
    await page.keyboard.press('Tab')
    check(await page.evaluate(() => Boolean(document.activeElement?.closest('dialog[open]'))), `Tab ${index + 1}: focus remains contained`)
  }
  await page.keyboard.press('Escape')
  await page.waitForFunction(() => !document.querySelector('dialog[open]'))
  await page.waitForFunction(() => document.activeElement?.textContent?.trim() === 'Get Hash Fleet')
  check(await invoker.evaluate(item => item === document.activeElement), 'Escape closes dialog and restores exact CTA focus')
  // Native <dialog> restores focus before its queued close event reaches React.
  await page.waitForFunction(() => location.hash === '')
  check(new URL(page.url()).hash === '', 'Escape removes only the dialog fragment')
  await invoker.click()
  await page.getByRole('button', { name: 'Close dialog', exact: true }).click()
  await page.waitForFunction(() => !document.querySelector('dialog[open]'))
  check(await invoker.evaluate(item => item === document.activeElement), 'Close button restores CTA focus')
  await invoker.click()
  await page.mouse.click(4, 4)
  await page.waitForFunction(() => !document.querySelector('dialog[open]'))
  check(await invoker.evaluate(item => item === document.activeElement), 'Backdrop closes without activating the page underneath')
  await page.goto(`${origin}/#features`)
  await invoker.click()
  await page.goBack()
  await page.waitForFunction(() => location.hash === '#features' && !document.querySelector('dialog[open]'))
  check(new URL(page.url()).hash === '#features' && await page.locator('dialog[open]').count() === 0, 'Browser Back returns to prior section and closes the modal')
  await page.goForward()
  await page.locator('dialog[open] #dialog-title').waitFor()
  check(new URL(page.url()).hash === '#download', 'Browser Forward reopens the download dialog')
  await page.evaluate(() => { location.hash = '#privacy' })
  await page.getByRole('heading', { name: 'Your fleet stays yours.', exact: true }).waitFor()
  check(await page.locator('dialog[open]').count() === 1, 'Hash navigation to privacy preserves a single live modal')
  await page.keyboard.press('Escape')
  await page.locator('header.site-header').getByRole('button', { name: 'Switch to light theme' }).click()
  await invoker.click()
  check(await page.evaluate(() => document.documentElement.dataset.theme) === 'light', 'Download dialog works in the real light theme')
  check(await page.locator('dialog[open]').evaluate(item => getComputedStyle(item).backgroundColor !== 'rgba(0, 0, 0, 0)'), 'Light theme dialog remains opaque/readable')
  await page.keyboard.press('Escape')
  await page.locator('.site-footer').getByRole('button', { name: 'Privacy', exact: true }).click()
  await page.getByRole('heading', { name: 'Your fleet stays yours.', exact: true }).waitFor()
  check(await page.locator('dialog a[href="mailto:support@hashfleet.app"]').count() === 1, 'Privacy/contact dialog remains intact through its normal CTA')
  await page.keyboard.press('Escape')
  check(await page.locator('.faq-list details').count() === 8, 'All eight FAQ disclosures remain')
  await page.locator('.faq-list details').first().locator('summary').click()
  check(await page.locator('.faq-list details').first().evaluate(item => item.open), 'FAQ remains interactive after download/privacy navigation')
  for (const fragment of ['#download-other', '#download?url=https://example.invalid', '#privacy/extra']) {
    await page.goto(`${origin}/${fragment}`)
    await page.waitForLoadState('networkidle')
    check(await page.locator('dialog[open]').count() === 0, `${fragment}: modified fragments do not open privileged dialogs`)
  }
  await page.goto(`${origin}/demo/iphone`)
  await page.getByRole('tab', { name: 'iPhone app', exact: true }).waitFor()
  check(await page.getByRole('tab', { name: 'iPhone app', exact: true }).getAttribute('aria-selected') === 'true', 'Existing direct iPhone walkthrough route is preserved')
  await openDownload()
  check(browserErrors.length === 0, `No browser errors: ${JSON.stringify(browserErrors)}`)
  check(failedRequests.length === 0, `No failed requests: ${JSON.stringify(failedRequests)}`)
  check(externalRequests.length === 0, `No requests outside the exact authorized origin: ${JSON.stringify(externalRequests)}`)
  const result = { status: 'passed', origin, checks: checks.length, responseInterception: false, responseMocking: false, requestIsolation, layouts, browserErrors, failedRequests, externalRequests }
  await page.evaluate(value => { window.__hashfleetDownloadAcceptance = value }, result)
  return result
}
