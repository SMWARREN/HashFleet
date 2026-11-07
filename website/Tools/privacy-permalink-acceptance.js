async (page) => {
  const origin = new URL(page.url()).origin
  const checks = []
  const errors = []
  const failedRequests = []
  const externalRequests = []
  const serviceRequests = []
  const check = (value, label) => { if (!value) throw new Error(label); checks.push(label) }
  page.on('pageerror', error => errors.push(error.message))
  page.on('requestfailed', request => failedRequests.push({ url: request.url(), error: request.failure()?.errorText }))
  page.on('request', request => {
    const url = new URL(request.url())
    if (url.origin !== origin) externalRequests.push(request.url())
    if (url.pathname.startsWith('/api/')) serviceRequests.push(request.url())
  })
  const dialog = page.getByRole('dialog', { name: 'Your fleet stays yours.' })
  const close = page.getByRole('button', { name: 'Close dialog' })
  const privacy = page.getByRole('navigation', { name: 'Footer navigation' }).getByRole('button', { name: 'Privacy', exact: true })
  async function open(path = '/#privacy') {
    const navigation = await page.goto(origin + path, { waitUntil: 'networkidle' })
    const response = navigation ?? await page.reload({ waitUntil: 'networkidle' })
    check(response.status() === 200, path + ' HTTP 200')
    await dialog.waitFor({ state: 'visible' })
    check(new URL(page.url()).hash === '#privacy', path + ' retains the direct fragment')
  }
  await open()
  const policy = await dialog.innerText()
  for (const phrase of ['This website', 'The native apps', 'Your connection', 'off by default', 'push token', 'plaintext', 'not continuous monitoring']) {
    check(policy.includes(phrase), 'existing privacy disclosure: ' + phrase)
  }
  check(policy.includes('Sean Warren') && policy.includes('support@hashfleet.app'), 'owner-authorized public privacy contact is present')
  check(await dialog.getByRole('link', { name: 'support@hashfleet.app', exact: true }).getAttribute('href') === 'mailto:support@hashfleet.app', 'privacy email has the exact authorized mailto target')
  check(await dialog.getByRole('link', { name: 'Technical support and contact details', exact: true }).getAttribute('href') === '/support/', 'privacy links to real technical support, not optional tipping')
  check(await page.getByRole('navigation', { name: 'Footer navigation', includeHidden: true }).getByRole('link', { name: 'Help & contact', exact: true, includeHidden: true }).getAttribute('href') === '/support/', 'homepage footer exposes the real help page')
  await page.reload({ waitUntil: 'networkidle' })
  await dialog.waitFor({ state: 'visible' })
  check(await dialog.isVisible(), 'direct policy survives a full reload')
  await page.keyboard.press('Escape')
  await dialog.waitFor({ state: 'detached' })
  await page.waitForURL(url => url.hash === '')
  check(new URL(page.url()).hash === '', 'Escape removes the privacy fragment')
  await privacy.click()
  await dialog.waitFor({ state: 'visible' })
  await page.waitForURL(url => url.hash === '#privacy')
  check(new URL(page.url()).hash === '#privacy', 'existing footer creates the shareable URL')
  const lastControl = dialog.locator('button, a[href]').last()
  await lastControl.focus()
  await page.keyboard.press('Tab')
  check(await close.evaluate(element => element === document.activeElement), 'Tab wraps from the last contact link to the modal close control')
  await page.keyboard.press('Shift+Tab')
  check(await lastControl.evaluate(element => element === document.activeElement), 'Shift+Tab wraps from the close control to the last contact link')
  await close.click()
  await dialog.waitFor({ state: 'detached' })
  await page.waitForURL(url => url.hash === '')
  check(await privacy.evaluate(element => element === document.activeElement), 'footer focus is restored after closing')
  check(new URL(page.url()).hash === '', 'close button removes the privacy fragment')
  await page.goto(origin + '/#support', { waitUntil: 'networkidle' })
  await page.evaluate(() => { window.location.hash = '#privacy' })
  await dialog.waitFor({ state: 'visible' })
  await page.goBack()
  await dialog.waitFor({ state: 'detached' })
  check(new URL(page.url()).hash === '#support', 'Back restores the previous page fragment')
  await page.goForward()
  await dialog.waitFor({ state: 'visible' })
  check(new URL(page.url()).hash === '#privacy', 'Forward reopens the policy')
  await close.click()
  for (const [width, height, name] of [[1440, 1080, 'desktop'], [390, 844, 'phone'], [844, 390, 'landscape'], [768, 1024, 'tablet'], [320, 780, 'small-phone']]) {
    await page.setViewportSize({ width, height })
    for (const theme of ['dark', 'light']) {
      if (await page.evaluate(() => document.documentElement.dataset.theme) !== theme) {
        await page.getByRole('button', { name: /^Switch to .* theme$/ }).click()
      }
      await privacy.click()
      await dialog.waitFor({ state: 'visible' })
      const box = await dialog.boundingBox()
      check(box && box.x >= -1 && box.x + box.width <= width + 1 && box.y >= -1 && box.y + box.height <= height + 1, name + ' ' + theme + ' dialog fits viewport')
      check(await dialog.evaluate(element => element.scrollWidth <= element.clientWidth + 1), name + ' ' + theme + ' no horizontal clipping')
      await page.screenshot({ path: 'output/playwright/privacy-' + name + '-' + theme + '.png' })
      await close.click()
      await dialog.waitFor({ state: 'detached' })
    }
  }
  await page.goto(origin + '/#support', { waitUntil: 'networkidle' })
  check(await page.locator('#support').isVisible(), 'existing optional-tip section remains intact')
  await page.getByRole('button', { name: 'Get Hash Fleet', exact: true }).click()
  await page.getByRole('dialog', { name: 'Make it your fleet.' }).waitFor({ state: 'visible' })
  await page.evaluate(() => { window.location.hash = '#faq' })
  check(await page.getByRole('dialog', { name: 'Make it your fleet.' }).isVisible(), 'unrelated fragment does not close the download dialog')
  await close.click()
  await page.evaluate(() => { window.location.hash = '#Privacy' })
  check(await page.getByRole('dialog').count() === 0, 'unknown fragment does not open the policy')
  check(await page.evaluate(() => localStorage.length === 0 && sessionStorage.length === 0 && document.cookie === ''), 'no browser persistence or cookies')
  check(errors.length === 0, 'no browser runtime errors: ' + JSON.stringify(errors))
  check(failedRequests.length === 0, 'no failed requests: ' + JSON.stringify(failedRequests))
  check(externalRequests.length === 0 && serviceRequests.length === 0, 'no third-party or service requests')
  await page.evaluate(result => { window.__hashfleetPrivacyAcceptance = result }, { status: 'passed', origin, checks: checks.length, responseInterception: false, publicContactPublished: true, publicContactPublicationAuthorized: true, externalRequests, serviceRequests, errors, failedRequests })
}
