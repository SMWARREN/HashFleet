async (page) => {
  const origin = new URL(page.url()).origin
  const checks = []
  const errors = []
  const externalRequests = []
  const check = (condition, label) => {
    if (!condition) {
      throw new Error(label)
    }
    checks.push(label)
  }
  page.on('pageerror', error => errors.push(error.message))
  page.on('request', request => { if (new URL(request.url()).origin !== origin) externalRequests.push(request.url()) })
  await page.setViewportSize({ width: 1440, height: 1080 })
  await page.goto(origin + '/#support')
  const support = page.locator('#support')
  await support.waitFor({ state: 'visible' })
  await page.waitForFunction(() => Math.abs(document.querySelector('#support').getBoundingClientRect().top) < 200)
  check(await page.getByRole('navigation', { name: 'Main navigation' }).getByRole('link', { name: 'Support', exact: true }).count() === 1, 'header support anchor')
  check(await page.getByRole('navigation', { name: 'Footer navigation' }).getByRole('link', { name: 'Support', exact: true }).count() === 1, 'footer support anchor')
  const paypal = support.getByRole('link', { name: /Leave a tip via PayPal/ })
  check(await paypal.getAttribute('href') === 'https://www.paypal.com/ncp/payment/6NAMWWPAKSFV2', 'exact verified PayPal link')
  check(await paypal.getAttribute('target') === '_blank' && await paypal.getAttribute('rel') === 'noopener noreferrer', 'safe external PayPal tab')
  check((await support.innerText()).includes('No features are purchased or unlocked.'), 'optional tip not a purchase')
  const expected = [
    ['BTC', 'Bitcoin mainnet', '1AZLMVdq1Dpc8FqibVUoMqJkh5wMQpd1wg'],
    ['ETH', 'Ethereum mainnet', '0xe0297d17680a3fa52975cf1cfc27bd2c1e73010c'],
    ['SOL', 'Solana mainnet', '2Ny4ZFGWtdVix4ZhGWCq3VCKLBRMC75aduCrYJUavA27'],
  ]
  await page.context().grantPermissions(['clipboard-read', 'clipboard-write'], { origin })
  for (const [symbol, network, address] of expected) {
    const code = page.locator('#support-address-' + symbol.toLowerCase())
    check(await code.textContent() === address, symbol + ' exact complete destination')
    const card = support.locator('article').filter({ has: code })
    check((await card.innerText()).includes(network + ' only'), symbol + ' explicit mainnet')
    await card.getByRole('button', { name: 'Copy ' + symbol + ' address' }).click()
    await card.getByRole('status').filter({ hasText: symbol + ' address copied.' }).waitFor()
    check(await page.evaluate(() => navigator.clipboard.readText()) === address, symbol + ' actual clipboard exact')
  }
  await page.evaluate(() => Object.defineProperty(navigator, 'clipboard', { configurable: true, value: { writeText: async () => { throw new Error('permission denied') } } }))
  for (const [symbol, , address] of expected) {
    await support.getByRole('button', { name: 'Copy ' + symbol + ' address' }).click()
    check(await page.evaluate(() => window.getSelection()?.toString()) === address, symbol + ' denied clipboard selects exact address')
    check(await page.locator('#support-address-' + symbol.toLowerCase()).evaluate(element => document.activeElement === element), symbol + ' fallback keyboard focus')
  }
  await page.evaluate(() => Object.defineProperty(navigator, 'clipboard', { configurable: true, value: undefined }))
  await support.getByRole('button', { name: 'Copy BTC address' }).click()
  check((await support.locator('article').first().innerText()).includes('Automatic copy is unavailable.'), 'missing clipboard gives manual fallback')
  for (const width of [1440, 1024, 768, 390, 320]) {
    await page.setViewportSize({ width, height: 1080 })
    for (const theme of ['dark', 'light']) {
      await page.evaluate(theme => document.documentElement.dataset.theme = theme, theme)
      await support.scrollIntoViewIfNeeded()
      check(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), width + ' ' + theme + ' no horizontal overflow')
      for (const [symbol] of expected) {
        const box = await page.locator('#support-address-' + symbol.toLowerCase()).boundingBox()
        check(box && box.x >= 0 && box.x + box.width <= width + 1, width + ' ' + theme + ' ' + symbol + ' address contained')
      }
    }
  }
  await page.getByRole('button', { name: 'Open navigation' }).click()
  await page.getByRole('navigation', { name: 'Main navigation' }).getByRole('link', { name: 'Support', exact: true }).click()
  check(await page.getByRole('button', { name: 'Open navigation' }).getAttribute('aria-expanded') === 'false', 'mobile Support link closes menu')
  await support.screenshot({ path: 'output/playwright/support-mobile.png' })
  await page.setViewportSize({ width: 1440, height: 1080 })
  await page.evaluate(() => document.documentElement.dataset.theme = 'dark')
  await support.screenshot({ path: 'output/playwright/support-desktop.png' })
  check(errors.length === 0, 'no browser errors')
  check(externalRequests.length === 0, 'no automatic third-party or wallet requests')
  const result = { status: 'passed', origin, checks: checks.length, errors, externalRequests, responseInterception: false, paymentAttempted: false }
  await page.evaluate(result => { window.__hashfleetSupportAcceptance = result }, result)
  return result
}
