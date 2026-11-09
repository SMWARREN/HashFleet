async (page) => {
  const origin = new URL(page.url()).origin
  const checks = []
  const errors = []
  const failedRequests = []
  const externalRequests = []
  const serviceRequests = []
  const check = (value, label) => {
    if (!value) {
      throw new Error(label)
    }
    checks.push(label)
  }
  page.on('pageerror', error => errors.push(error.message))
  page.on('requestfailed', request => failedRequests.push({ url: request.url(), error: request.failure()?.errorText }))
  page.on('request', request => {
    const url = new URL(request.url())
    if (url.origin !== origin) externalRequests.push(request.url())
    if (url.pathname.startsWith('/api/')) serviceRequests.push(request.url())
  })
  const response = await page.goto(origin + '/support/', { waitUntil: 'networkidle' })
  check(response?.status() === 200, 'real support URL returns HTTP 200')
  check((response.headers()['content-type'] ?? '').includes('text/html'), 'real support response is HTML')
  check(await page.title() === 'Help & contact · Hash Fleet', 'support has its own descriptive page title')
  check(await page.locator('link[rel="canonical"]').getAttribute('href') === 'https://hashfleet.app/support/', 'canonical support URL is exact')
  check(await page.getByRole('heading', { level: 1 }).innerText() === 'A real person.\nA little help.', 'technical support heading is present')
  const address = page.locator('address')
  check((await address.innerText()).includes('Sean Warren'), 'authorized developer name is visible')
  const email = address.getByRole('link', { name: 'support@hashfleet.app', exact: true })
  check(await email.getAttribute('href') === 'mailto:support@hashfleet.app', 'authorized email text and mailto match exactly')
  check(await page.locator('a[href^="tel:"]').count() === 0 && !(await page.content()).replace(/\D/g, '').includes('9803096281'), 'public phone number and telephone links are absent from the full page source')
  check(await page.locator('script, form, input, textarea, iframe').count() === 0, 'static contact page has no scripts, forms or embedded services')
  const body = await page.locator('body').innerText()
  check(body.includes('Never send passwords, private keys, recovery phrases') && body.includes('Remove miner addresses, wallet details'), 'support warns against sending secrets or unredacted miner information')
  check(await page.getByRole('link', { name: 'Hash Fleet privacy policy', exact: true }).getAttribute('href') === '/#privacy', 'support has the working privacy permalink')
  check(body.includes('© 2026 Sean Warren.'), 'authorized copyright name is visible')
  const reloaded = await page.reload({ waitUntil: 'networkidle' })
  check(reloaded?.status() === 200 && await address.isVisible(), 'real support page survives a cold reload')
  await page.keyboard.press('Tab')
  check(await page.getByRole('link', { name: 'Skip to content', exact: true }).evaluate(element => element === document.activeElement), 'keyboard first control is the visible skip link')
  await page.keyboard.press('Enter')
  check(await page.locator('main').evaluate(element => element === document.activeElement), 'skip link moves keyboard focus to main content')
  for (const [width, height, name] of [[1440, 1080, 'desktop'], [390, 844, 'phone'], [844, 390, 'landscape'], [768, 1024, 'tablet'], [320, 780, 'small-phone']]) {
    await page.setViewportSize({ width, height })
    for (const theme of ['dark', 'light']) {
      await page.emulateMedia({ colorScheme: theme })
      await page.evaluate(() => window.scrollTo(0, 0))
      check(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1), name + ' ' + theme + ' has no page horizontal overflow')
      const colorScheme = await page.locator('html').evaluate(element => getComputedStyle(element).colorScheme)
      check(colorScheme === theme, name + ' ' + theme + ' follows system color scheme')
      check(await address.evaluate(element => element.scrollWidth <= element.clientWidth + 1), name + ' ' + theme + ' contact details do not clip horizontally')
      check(JSON.stringify(await address.locator('dt').allTextContents()) === JSON.stringify(['Name', 'Email']), name + ' ' + theme + ' contact exposes only name and email')
      for (const [link, label] of [[email, 'email']]) {
        await link.scrollIntoViewIfNeeded()
        const box = await link.boundingBox()
        check(box && box.x >= 0 && box.x + box.width <= width + 1 && box.y >= 0 && box.y + box.height <= height + 1, name + ' ' + theme + ' ' + label + ' is fully legible')
      }
      await email.focus()
      check(await email.evaluate(element => element === document.activeElement), name + ' ' + theme + ' contact email is keyboard-focusable without opening mail')
      await page.evaluate(() => window.scrollTo(0, 0))
      await page.screenshot({ path: 'output/playwright/contact-' + name + '-' + theme + '.png', fullPage: true })
    }
  }
  await page.getByRole('link', { name: 'Hash Fleet privacy policy', exact: true }).click()
  const dialog = page.getByRole('dialog', { name: 'Your fleet stays yours.' })
  await dialog.waitFor({ state: 'visible' })
  await page.waitForLoadState('networkidle')
  check(new URL(page.url()).hash === '#privacy', 'support privacy link opens actual homepage policy')
  check(await dialog.getByRole('link', { name: 'support@hashfleet.app', exact: true }).getAttribute('href') === 'mailto:support@hashfleet.app', 'policy exposes the same authorized contact')
  await dialog.getByRole('link', { name: 'Technical support and contact details', exact: true }).click()
  await page.waitForURL(origin + '/support/')
  await page.waitForLoadState('networkidle')
  check(await address.isVisible(), 'policy support link returns to the real contact page')
  await page.getByRole('link', { name: 'Back to the website', exact: true }).click()
  await page.waitForLoadState('networkidle')
  const footer = page.getByRole('navigation', { name: 'Footer navigation' })
  const help = footer.getByRole('link', { name: 'Help & contact', exact: true })
  check(await help.getAttribute('href') === '/support/', 'homepage footer links to real technical support')
  await help.click()
  await page.waitForURL(origin + '/support/')
  await page.waitForLoadState('networkidle')
  check(await address.isVisible(), 'homepage Help link opens real contact page')
  check(await page.locator('script, form, input, textarea, iframe').count() === 0, 'return visit remains a static, form-free contact page')
  check(await page.evaluate(() => localStorage.length === 0 && sessionStorage.length === 0 && document.cookie === ''), 'no browser persistence or cookies')
  check(errors.length === 0, 'no browser runtime errors: ' + JSON.stringify(errors))
  check(failedRequests.length === 0, 'no failed requests: ' + JSON.stringify(failedRequests))
  check(externalRequests.length === 0 && serviceRequests.length === 0, 'no third-party or backend service requests')
  await page.evaluate(result => { window.__hashfleetContactAcceptance = result }, { status: 'passed', origin, checks: checks.length, checkLabels: checks, responseInterception: false, noEmailOrPhoneLinkOpened: true, externalRequests, serviceRequests, errors, failedRequests })
}
