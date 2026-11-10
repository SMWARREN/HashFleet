// Run with the installed Playwright CLI after injecting the two checked-in JSON fixtures.
// This supersedes lookalike-specific assertions in browser-acceptance.js, not its safety requirements.
async (page) => {
async function verifyNativeLanding(page, origin, publicHost, csp, manifest, check) {
  await page.emulateMedia({ reducedMotion: 'reduce' })
  await page.setViewportSize({ width: 1440, height: 1000 })
  const response = await page.goto(origin)
  check(response.status() === 200, 'Production homepage returns 200')
  if (publicHost) check(response.headers()['content-security-policy'] === csp, 'Public server provides the exact restrictive CSP')
  await page.getByRole('heading', { level: 1 }).waitFor()
  check(await page.title() === 'HashFleet | Free Bitaxe Mining Management Software', 'Mining management page title')
  check(await page.locator('head title').count() === 1 && await page.locator('meta[name="description"]').count() === 1, 'Exactly one title and meta description')
  check(await page.locator('link[rel="canonical"]').count() === 1 && await page.locator('link[rel="canonical"]').getAttribute('href') === 'https://hashfleet.app/', 'One canonical homepage URL')
  check(await page.locator('meta[property="og:title"]').getAttribute('content') === await page.title() && await page.locator('meta[name="twitter:title"]').getAttribute('content') === await page.title(), 'Search and sharing titles agree')
  check(await page.locator('script[type="application/ld+json"]').count() === 1, 'One structured-data graph')
  const schema = JSON.parse(await page.locator('script[type="application/ld+json"]').textContent())
  const software = schema['@graph'].find(item => item['@type'] === 'SoftwareApplication')
  check(schema['@context'] === 'https://schema.org' && software.isAccessibleForFree === true && software.offers.price === '0' && !software.aggregateRating && !software.review, 'Software schema describes the free app without invented ratings')
  check(await page.locator('h1').count() === 1, 'Exactly one main heading')
  check(await page.evaluate(() => document.documentElement.dataset.theme) === 'dark', 'The original site defaults to dark theme')
  check(await page.getByRole('img', { name: "Hash Fleet's gold and graphite miner artwork" }).count() === 1, 'Original product artwork keeps an accessible description')
  check(await page.getByRole('link', { name: 'Hash Fleet home' }).count() === 2, 'Original header and footer branding')
  check(JSON.stringify(await page.getByRole('tab').allTextContents()) === JSON.stringify(['Mac app', 'iPhone app', 'Apple Watch', 'Terminal']), 'Four ordered product platform tabs')
  check(await page.locator('[role="tabpanel"]:visible').count() === 1, 'Only one platform visible')
  check(await page.evaluate(() => [...document.querySelectorAll('[aria-controls]')].every(element => document.getElementById(element.getAttribute('aria-controls')))), 'All tab controls resolve')
  check(await page.locator('.hero-phone img').getAttribute('src') === manifest.captures.find(item => item.id === 'ios-fleet').src, 'Hero phone uses the actual native fleet capture')
  check(await page.locator('.hero-mac img').getAttribute('src') === manifest.captures.find(item => item.id === 'mac-overview').src, 'Hero Mac uses the actual primary Mac capture')
  check(await page.locator('.mini-phone-tabs, .phone-tab-bar, .app-summary, .phone-settings-page').count() === 0, 'No old invented app UI survives in hero or tours')
  check((await page.locator('.hero-terminal').innerText()).includes('HASH FLEET'), 'Hero terminal uses the real colored CLI status header')
  check(await page.locator('.hero-mac img, .hero-phone img').evaluateAll(async images => {
    await Promise.all(images.map(image => image.decode()))
    return images.every(image => image.complete && image.naturalWidth > 0)
  }), 'Both native hero captures decode before visual review')
  await page.screenshot({ path: 'output/playwright/product-parity-landing.png' })
}

async function verifyNativeDownloadDialog(page, focused, check) {
  const download = page.locator('.header-actions').getByRole('button', { name: 'Get Hash Fleet' })
  await download.click()
  const dialog = page.getByRole('dialog')
  await dialog.waitFor()
  check(await dialog.getByRole('link', { name: 'Get Mac build' }).getAttribute('href') === 'https://github.com/SMWARREN/HashFleet/releases/latest/download/HashFleet-macos-arm64.zip', 'Existing latest Mac download is preserved')
  check(await dialog.getByRole('link', { name: 'Get terminal CLI' }).getAttribute('href') === 'https://github.com/SMWARREN/HashFleet/releases/latest/download/hashfleet-cli-macos-arm64.tar.gz', 'Existing latest CLI download is preserved')
  check(await dialog.getByText('Coming soon', { exact: true }).count() === 1, 'Unreleased iOS build remains honestly labeled')
  check(await focused(dialog.getByRole('button', { name: 'Close dialog' })), 'Dialog begins with focus inside')
  await page.keyboard.press('Shift+Tab')
  check(await dialog.evaluate(element => element.contains(document.activeElement)), 'Native modal keeps reverse-tab focus inside')
  await page.keyboard.press('Tab')
  check(await dialog.evaluate(element => element.contains(document.activeElement)), 'Native modal keeps forward-tab focus inside')
  await page.keyboard.press('Escape')
  await dialog.waitFor({ state: 'detached' })
  check(await focused(download), 'Escape restores download trigger focus')
  await download.click()
  await page.mouse.click(5, 5)
  await page.getByRole('dialog').waitFor({ state: 'detached' })
  check(await focused(download), 'Backdrop dismissal restores the original download trigger')
  await download.click()
  await page.getByRole('button', { name: 'Close dialog' }).click()
  await page.getByRole('dialog').waitFor({ state: 'detached' })
  check(await focused(download), 'Close button restores the original download trigger')
}

async function verifyNativePlatformTabs(page, check, focused, macTab, phoneTab, watchTab, terminalTab) {
  await page.getByRole('button', { name: 'Explore the captured iPhone screens', exact: true }).click()
  check(await phoneTab.getAttribute('aria-selected') === 'true' && await focused(phoneTab), 'Real-capture hero phone opens and focuses the iPhone tour')
  await page.getByRole('button', { name: 'Open the browser CLI demo', exact: true }).click()
  check(await terminalTab.getAttribute('aria-selected') === 'true' && await focused(terminalTab), 'Actual-output hero terminal opens and focuses the CLI demo')
  await page.getByRole('button', { name: 'Take it for a spin' }).click()
  check(await focused(macTab), 'Hero CTA focuses the selected Mac tab')
  await macTab.press('ArrowRight')
  check(await phoneTab.getAttribute('aria-selected') === 'true' && await focused(phoneTab), 'ArrowRight selects and focuses iPhone')
  await phoneTab.press('ArrowRight')
  check(await watchTab.getAttribute('aria-selected') === 'true' && await focused(watchTab), 'ArrowRight selects and focuses the added Apple Watch platform')
  await watchTab.press('ArrowRight')
  check(await terminalTab.getAttribute('aria-selected') === 'true' && await focused(terminalTab), 'ArrowRight continues from Apple Watch to Terminal')
  await phoneTab.click()
  await phoneTab.press('End')
  check(await terminalTab.getAttribute('aria-selected') === 'true' && await focused(terminalTab), 'End selects and focuses Terminal')
  await terminalTab.press('Home')
  check(await macTab.getAttribute('aria-selected') === 'true' && await focused(macTab), 'Home selects and focuses Mac')
  await macTab.press('ArrowLeft')
  check(await terminalTab.getAttribute('aria-selected') === 'true' && await focused(terminalTab), 'ArrowLeft wraps from the first to the last platform')
  await terminalTab.press('ArrowRight')
  check(await macTab.getAttribute('aria-selected') === 'true' && await focused(macTab), 'ArrowRight wraps from the last to the first platform')
}

async function verifyNativeAssetBytes(page, manifest, check) {
  const assets = await page.evaluate(async captures => Promise.all(captures.map(async capture => {
    const response = await fetch(capture.src, { cache: 'no-store' })
    const bytes = await response.arrayBuffer()
    const hash = [...new Uint8Array(await crypto.subtle.digest('SHA-256', bytes))].map(value => value.toString(16).padStart(2, '0')).join('')
    return { id: capture.id, status: response.status, mime: response.headers.get('content-type'), bytes: bytes.byteLength, hash }
  })), manifest.captures)
  for (const asset of assets) {
    const expected = manifest.captures.find(item => item.id === asset.id)
    check(asset.status === 200 && asset.mime?.startsWith('image/webp') && asset.bytes === expected.bytes && asset.hash === expected.sha256, `${asset.id}: served lossless native bytes and WebP MIME match the verified manifest`)
  }
  return assets
}

async function verifyNativeTourPickers({ macTab, mac, phoneTab, phone }) {
  for (const [tab, panel, platform] of [[macTab, mac, 'Mac'], [phoneTab, phone, 'iPhone']]) {
    await tab.click()
    check((await panel.innerText()).includes('not a recreated dashboard or a live app stream'), `${platform}: captured-screen disclosure is visible`)
    check((await panel.innerText()).includes('Other controls are part of the image'), `${platform}: inactive native controls are clearly disclosed`)
    check((await panel.innerText()).includes('No device connections. No settings changes.'), `${platform}: safety boundary remains visible`)
    const picker = panel.getByRole('combobox', { name: `${platform} screen` })
    const ids = await picker.locator('option').evaluateAll(options => options.map(option => option.value))
    check(ids.length === (platform === 'Mac' ? 11 : 7), `${platform}: every captured native screen is reachable`)
    for (const id of ids) {
      await picker.selectOption(id)
      check(await captureId(panel) === id, `${id}: selection displays the correct native capture`)
      const expected = manifest.captures.find(item => item.id === id)
      check(JSON.stringify(await decode(panel)) === JSON.stringify([expected.width, expected.height]), `${id}: native full-resolution dimensions load`)
    }
    await panel.getByRole('button', { name: 'Reset tour' }).click()
    await settleCapture(panel)
    check(await captureId(panel) === ids[0] && await panel.getByRole('button', { name: `Previous ${platform} capture` }).isDisabled(), `${platform}: reset returns to home and clears history`)
    const toggle = panel.getByRole('button', { name: 'Clickable areas', exact: true })
    await toggle.click()
    check(await toggle.getAttribute('aria-pressed') === 'false', `${platform}: hotspot outlines can be hidden`)
    await toggle.click()
    check(await toggle.getAttribute('aria-pressed') === 'true', `${platform}: hotspot outlines can be restored`)
  }
}

async function verifyMacWalkthrough(mac, settleCapture, captureId, focused, check) {
  await mac.getByRole('button', { name: 'Enlarge screen', exact: true }).click()
  const macViewport = mac.locator('.native-viewport')
  await macViewport.evaluate(element => { element.scrollTop = 80 })
  const workshop = mac.getByRole('button', { name: 'Mac walkthrough: Workshop Gamma', exact: true })
  await workshop.click()
  await settleCapture(mac)
  check(await captureId(mac) === 'mac-workshop', 'Native Mac sidebar opens the corresponding miner detail')
  check(await focused(mac.locator('.native-screen-status h3')), 'Hotspot navigation focuses its new screen heading')
  check(await macViewport.evaluate(element => element.scrollTop === 0), 'New native screen starts at the top')
  await mac.getByRole('button', { name: 'Previous Mac capture' }).click()
  await settleCapture(mac)
  check(await captureId(mac) === 'mac-overview' && await focused(workshop), 'Back restores the native sidebar trigger focus')
  check(await macViewport.evaluate(element => element.scrollTop === 80), 'Back restores the captured-screen vertical scroll')
  await macViewport.evaluate(element => { element.scrollTop = 100; element.scrollLeft = 150 })
  await mac.getByRole('combobox', { name: 'Mac screen' }).selectOption('mac-energy')
  await settleCapture(mac)
  await mac.getByRole('button', { name: 'Previous Mac capture' }).click()
  await settleCapture(mac)
  check(await macViewport.evaluate(element => element.scrollLeft === 150 && element.scrollTop === 100), 'Picker history restores both horizontal and vertical inspection scroll')
  await mac.getByRole('button', { name: 'Fit screen', exact: true }).click()
  await mac.getByRole('button', { name: 'Reset tour' }).click()
  await settleCapture(mac)
  await mac.locator('.native-viewport').scrollIntoViewIfNeeded()
  await mac.locator('.native-walkthrough').screenshot({ path: 'output/playwright/product-parity-mac.png' })
}

async function verifyPhoneWalkthrough(phone, macTab, phoneTab, settleCapture, captureId, focused, check) {
  const phoneHeading = phone.locator('.native-screen-status h3')
  const gear = phone.getByRole('button', { name: 'iPhone walkthrough: Open the captured gear menu', exact: true })
  await gear.focus()
  await gear.press('Enter')
  await settleCapture(phone)
  check(await captureId(phone) === 'ios-current' && await focused(phoneHeading), 'Keyboard activates the real phone gear-menu journey')
  await phone.getByRole('button', { name: 'iPhone walkthrough: App settings', exact: true }).click()
  await settleCapture(phone)
  check(await captureId(phone) === 'ios-settings', 'Gear menu opens the captured App settings sheet')
  await phone.getByRole('button', { name: 'iPhone walkthrough: Fleet preferences', exact: true }).click()
  await settleCapture(phone)
  check(await captureId(phone) === 'ios-fleet-settings', 'App settings opens the actual native Fleet preferences')
  check(await phone.getByRole('checkbox').count() === 0 && await phone.getByRole('switch').count() === 0, 'Image switches are not fake functional browser settings')
  await phone.getByRole('button', { name: 'Previous iPhone capture' }).click()
  await settleCapture(phone)
  check(await captureId(phone) === 'ios-settings' && await focused(phone.getByRole('button', { name: 'iPhone walkthrough: Fleet preferences', exact: true })), 'Phone Back restores the captured settings trigger')
  await phone.getByRole('button', { name: 'iPhone walkthrough: Done, return to the captured fleet', exact: true }).click()
  await settleCapture(phone)
  check(await captureId(phone) === 'ios-fleet', 'Native Done returns to the fleet capture')
  await phone.getByRole('button', { name: 'See the miner cards', exact: false }).click()
  await settleCapture(phone)
  check(await captureId(phone) === 'ios-miners', 'Tour exposes real expanded native miner cards')
  await phone.getByRole('button', { name: 'iPhone walkthrough: Inspect Office Gamma', exact: true }).click()
  await settleCapture(phone)
  check(await captureId(phone) === 'ios-office', 'Scrolled Office Gamma card opens the correct captured miner identity')
  await macTab.click()
  await phoneTab.click()
  check(await captureId(phone) === 'ios-office', 'Changing platform tabs preserves tour state')
  await phone.getByRole('button', { name: 'Reset tour' }).click()
  await settleCapture(phone)
  await phone.locator('.native-transcript summary').click()
  check((await phone.locator('.native-transcript').innerText()).includes('SAMPLE FLEET HASHRATE'), 'Native screen has an accessible readable transcript')
  await phone.locator('.native-transcript summary').click()
  await phone.locator('.native-walkthrough').screenshot({ path: 'output/playwright/product-parity-iphone.png' })
}

async function verifyNativeTerminal(page, cli, nativeStatus, check) {
  const terminal = page.locator('#panel-terminal')
  const input = terminal.getByRole('textbox', { name: 'Terminal command' })
  const last = () => terminal.locator('.terminal-demo__result').last()
  const run = async command => { await input.fill(command); await input.press('Enter'); return (await last().innerText()).trimEnd() }
  check(await run('hashfleet status') === nativeStatus('table'), 'Browser table equals the real captured native colored CLI table, including both best-share columns')
  check(await run('hashfleet status --details') === nativeStatus('details'), 'Browser details equal real native colored diagnostic output')
  check(await run('hashfleet status --json') === cli.commands.json, 'Browser full JSON equals the real sanitized native Codable output')
  check(await run('hashfleet --help') === cli.commands.help, 'Native help is not mixed with invented browser commands')
  check((await terminal.innerText()).includes('help / clear are browser-only utilities'), 'Browser-only utilities are explicitly labeled')
  check((await run('hashfleet status gamma-demo.invalid office-demo.invalid')).includes('2/2 online'), 'Explicit fictional-host selection works')
  for (const command of ['hashfleet status cpu-demo.invalid', 'hashfleet status 192.168.1.20', 'hashfleet status; echo unsafe', 'hashfleet restart gamma-demo.invalid']) check((await run(command)).includes('Nothing was executed'), `${command}: refused without I/O`)
  await input.fill('unsent draft')
  await input.press('ArrowUp')
  check(await input.inputValue() === 'hashfleet restart gamma-demo.invalid', 'Terminal ArrowUp recalls the last command')
  await input.press('ArrowDown')
  check(await input.inputValue() === 'unsent draft', 'Terminal ArrowDown restores an unsent draft')
  await terminal.getByRole('button', { name: 'Clear panel, browser demo utility' }).click()
  check(await terminal.locator('.terminal-demo__entry').count() === 0, 'Clear empties only the browser panel')
  await terminal.getByRole('button', { name: 'hashfleet status', exact: true }).click()
  check((await last().innerText()).trimEnd() === nativeStatus('table'), 'CLI demo remains usable after clear')
  await terminal.locator('.terminal-demo').screenshot({ path: 'output/playwright/product-parity-cli.png' })
  return { terminal, input, last }
}

async function verifyNativeDashboard(terminal, input, focused, check) {
  await input.fill('hashfleet watch --demo')
  await input.press('Enter')
  const dashboard = terminal.locator('.cli-dashboard')
  const screen = dashboard.locator('.cli-dashboard__viewport')
  await screen.waitFor()
  await screen.focus()
  await screen.press('j')
  check(await dashboard.getByRole('combobox', { name: 'Selected demo miner' }).inputValue() === '1', 'Dashboard j selects the next miner')
  await screen.press('d')
  check((await screen.innerText()).includes('DETAILS / Gamma / studio'), 'Dashboard d opens the selected miner details')
  await screen.press('3')
  check((await screen.innerText()).includes('COOLING & POWER'), 'Detail number keys change native sections')
  await screen.press('e')
  await dashboard.getByRole('button', { name: '2 Cooling', exact: true }).click()
  check((await screen.innerText()).includes('Manual fan (%)'), 'Cooling settings button shows native fan fields')
  await dashboard.getByRole('button', { name: '3 Tuning', exact: true }).click()
  check((await screen.innerText()).includes('Core voltage (mV)'), 'Tuning settings button shows native voltage fields')
  await dashboard.getByRole('button', { name: '5 Pools', exact: true }).click()
  check((await screen.innerText()).includes('Primary pool host'), 'Pool settings button shows native pool fields')
  check((await screen.innerText()).includes('DEMO · preview only. No changes will be sent.'), 'Settings retain the native demo write restriction')
  await dashboard.getByRole('button', { name: 'Fleet', exact: true }).click()
  await dashboard.getByRole('button', { name: 'Pause space', exact: true }).click()
  check((await screen.innerText()).includes('PAUSED'), 'Pause changes the captured dashboard state')
  await dashboard.getByRole('button', { name: 'Resume space', exact: true }).click()
  check(!(await screen.innerText()).includes('PAUSED'), 'Resume restores the sample dashboard')
  await dashboard.getByRole('button', { name: 'Sort: name s', exact: true }).click()
  check((await screen.innerText()).includes('sort: hashrate'), 'Sort changes the actual native sample order')
  await dashboard.getByRole('combobox', { name: 'Selected demo miner' }).selectOption('3')
  await dashboard.getByRole('button', { name: 'Details d', exact: true }).click()
  check((await screen.innerText()).includes('Miner unavailable'.toUpperCase()), 'Offline miner details preserve missing-data behavior')
  await dashboard.getByRole('button', { name: 'Logo l', exact: true }).click()
  check((await screen.innerText()).includes('HASH FLEET / LOGO'), 'Logo control opens the transparent native pixel artwork')
  await screen.focus()
  await screen.press('Escape')
  await terminal.locator('.terminal-demo').screenshot({ path: 'output/playwright/product-parity-cli-dashboard.png' })
  await screen.press('q')
  check(await dashboard.count() === 0 && await focused(input), 'Quit returns focus to the existing command prompt')
  await input.fill('draft after dashboard')
  await input.press('ArrowUp')
  check(await input.inputValue() === 'hashfleet watch --demo', 'Interactive commands remain in command history')
  await input.press('ArrowDown')
  check(await input.inputValue() === 'draft after dashboard', 'Command draft survives dashboard history navigation')
  await input.fill('hashfleet status')
  await input.press('Enter')
  return { dashboard, screen }
}

async function verifyNativeTerminalResponsive(width, { input, screen, dashboard, terminal }) {
  await input.fill('hashfleet watch --demo')
  await input.press('Enter')
  await screen.waitFor()
  check(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), `Interactive CLI at ${width}px: output pans inside the terminal`)
  const controls = await dashboard.locator('.cli-dashboard__controls').evaluateAll(groups => groups.flatMap(group => [...group.querySelectorAll('button,select')].map(control => {
    const rect = control.getBoundingClientRect(); return { left: rect.left, right: rect.right, height: rect.height }
  })))
  check(controls.every(control => control.left >= 0 && control.right <= width && control.height >= 44), `Interactive CLI at ${width}px: controls fit with 44px touch targets`)
  await dashboard.getByRole('combobox', { name: 'Selected demo miner' }).selectOption('2')
  await dashboard.getByRole('button', { name: 'Settings e', exact: true }).click()
  await dashboard.getByRole('button', { name: '5 Pools', exact: true }).click()
  check((await screen.innerText()).includes('Naja Duo / rack') && (await screen.innerText()).includes('Primary pool host'), `Interactive CLI at ${width}px: miner and pool navigation work`)
  if (width === 375) await terminal.locator('.terminal-demo').screenshot({ path: 'output/playwright/product-parity-mobile-cli.png' })
  await dashboard.getByRole('button', { name: 'Quit q', exact: true }).click()
}

async function verifyNativeTourResponsive(panel, name, width) {
  const controls = await panel.locator('.native-tour-toolbar').evaluate(element => [...element.querySelectorAll('select,button')].map(control => { const rect = control.getBoundingClientRect(); return { left: rect.left, right: rect.right, width: rect.width, height: rect.height } }))
  check(controls.every(control => control.left >= 0 && control.right <= width && control.width > 0 && control.height >= 40), `${name} at ${width}px: tour controls remain within the page with usable height`)
  await panel.getByRole('button', { name: 'Enlarge screen', exact: true }).click()
  check(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), `${name} at ${width}px: enlargement pans inside the viewport, not the page`)
  await panel.getByRole('button', { name: 'Fit screen', exact: true }).click()
}

async function verifyNativeResponsiveLayouts(context) {
  const { macTab, mac, phoneTab, phone, terminalTab, terminal } = context
  for (const width of [1440, 1024, 768, 375, 320]) {
    await page.setViewportSize({ width, height: width < 640 ? 812 : 1000 })
    for (const [tab, panel, name] of [[macTab, mac, 'Mac'], [phoneTab, phone, 'iPhone'], [terminalTab, terminal, 'Terminal']]) {
      await tab.click()
      check(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), `${name} at ${width}px: no page-wide overflow`)
      if (name === 'Terminal' && width < 640) {
        await verifyNativeTerminalResponsive(width, context)
      }
      if (name !== 'Terminal') {
        await verifyNativeTourResponsive(panel, name, width)
      }
    }
    if (width === 375) { await phoneTab.click(); await phone.locator('.native-walkthrough').screenshot({ path: 'output/playwright/product-parity-mobile-iphone.png' }) }
  }
}

async function verifyNativePrivacyAndTheme(page, phoneTab, phone, captureId, focused, check) {
  for (const disclosure of await page.locator('.faq-list details').all()) {
    await disclosure.locator('summary').click()
    check(await disclosure.getAttribute('open') !== null, 'FAQ opens via native disclosure')
    await disclosure.locator('summary').click()
  }
  const privacy = page.getByRole('button', { name: 'Privacy', exact: true })
  await privacy.click()
  check((await page.getByRole('dialog').innerText()).includes('captured screens with tour navigation, not a native app stream'), 'Privacy accurately describes capture navigation')
  check((await page.getByRole('dialog').innerText()).includes('best effort, not continuous monitoring'), 'Privacy preserves notification activation/delivery limits')
  await page.getByRole('button', { name: 'Close dialog' }).click()
  await page.getByRole('dialog').waitFor({ state: 'detached' })
  check(await focused(privacy), 'Privacy dialog restores its trigger focus')
  await page.getByRole('button', { name: 'Switch to light theme' }).click()
  check(await page.evaluate(() => document.documentElement.dataset.theme) === 'light', 'Original light theme works')
  await phoneTab.click()
  check(await captureId(phone) === 'ios-fleet', 'Site light theme does not repaint a dark native capture')
  await page.getByRole('button', { name: 'Switch to dark theme' }).click()
  check(await page.evaluate(() => document.documentElement.dataset.theme) === 'dark', 'Original dark theme is restorable')
}

async function verifyNativeCompletion({ macTab, assets }) {
  await page.getByRole('button', { name: 'Open navigation' }).click()
  check(await page.getByRole('button', { name: 'Close navigation' }).getAttribute('aria-expanded') === 'true', 'Original mobile navigation opens')
  await page.getByRole('navigation', { name: 'Main navigation', exact: true }).getByRole('link', { name: 'Features' }).click()
  check(await page.getByRole('button', { name: 'Open navigation' }).getAttribute('aria-expanded') === 'false', 'Original mobile menu closes after selection')
  check(await page.evaluate(() => { const ids = [...document.querySelectorAll('[id]')].map(element => element.id); return new Set(ids).size === ids.length }), 'All page IDs remain unique')
  check(await page.evaluate(() => localStorage.length === 0 && sessionStorage.length === 0), 'Tour and terminal choices are not persisted')
  check((await page.context().cookies(origin)).length === 0, 'No cookies are set')
  check(failedRequests.length === 0, `No unexpected failed requests: ${failedRequests.join(', ')}`)
  check(requests.every(request => request.url.startsWith(`${origin}/`) && request.method === 'GET'), 'Only same-origin GET website assets requested')
  check(requests.every(request => !/192\.168\.|10\.\d+\.\d+\.|stratum\.|solo\.ckpool|\/api\//.test(request.url)), 'No live miner, pool, or notification API requests')
  check(errors.length === 0, `No browser or CSP errors: ${errors.join(', ')}`)

  // Isolate an intentionally failed image so it cannot be mistaken for a clean-page asset error.
  const failurePage = await page.context().newPage()
  await failurePage.route(`**${manifest.captures.find(item => item.id === 'mac-network').src}`, route => route.fulfill({ status: 404, body: 'intentional image failure' }))
  await failurePage.goto(origin)
  await failurePage.getByRole('combobox', { name: 'Mac screen' }).selectOption('mac-network')
  await failurePage.locator('#panel-mac .native-viewport').scrollIntoViewIfNeeded()
  await failurePage.getByRole('alert').waitFor()
  check((await failurePage.getByRole('alert').innerText()).includes('could not be loaded'), 'Intentionally missing capture produces a readable error')
  await failurePage.locator('#panel-mac').getByRole('button', { name: 'Reset tour' }).click()
  await failurePage.locator('[data-native-capture="mac-overview"]').evaluate(async image => image.decode())
  check(await failurePage.getByRole('alert').count() === 0, 'Reset recovers from a missing image')
  await failurePage.close()

  await page.setViewportSize({ width: 1440, height: 1000 })
  await macTab.click()
  await page.evaluate(() => window.scrollTo(0, 0))
  await page.screenshot({ path: 'output/playwright/product-parity-final.png' })
  const result = { status: 'passed', origin, cspSource: publicHost ? 'server-response' : 'injected-preview-test', checks: checks.length, cases: checks, nativeCaptures: assets.length, intentionalFailureRecovery: 'separate page', browserErrors: errors, failedRequests, requests: [...new Set(requests.map(request => `${request.method} ${request.url}`))] }
  await page.evaluate(result => { window.__hashfleetNativeParity = result }, result)
  return result
}

  const manifest = __NATIVE_MANIFEST__
  const cli = __CLI_CAPTURES__
  const plainAnsi = value => value.replace(/\x1b\[[0-9;?]*[A-Za-z]/g, '')
  const nativeStatus = key => plainAnsi([cli.tty[key].header,
    ...JSON.parse(cli.commands.json).miners.map(miner => cli.tty[key].miners[miner.device.address]),
    cli.tty[key].footer].join('\n')).trimEnd()
  const origin = new URL(page.url()).origin
  const publicHost = origin === 'https://hashfleet.app'
  if (!['http://127.0.0.1:4174', 'http://127.0.0.1:4175', 'https://hashfleet.app'].includes(origin)) throw new Error(`Unsupported acceptance origin: ${origin}`)
  const csp = "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; connect-src 'self'; object-src 'none'; base-uri 'self'; frame-ancestors 'none'; form-action 'self'"
  const checks = []
  const errors = []
  const failedRequests = []
  const requests = []
  const check = (value, label) => {
    if (!value) {
      throw new Error(`Acceptance failed: ${label}`)
    }
    checks.push(label)
  }
  const focused = locator => locator.evaluate(element => element === document.activeElement)
  const captureId = panel => panel.locator('[data-native-capture]').evaluate(image => image.dataset.nativeCapture ?? null)
  // Wait for the selected image without moving its saved inspection scroll or focus.
  const settleCapture = panel => panel.locator('[data-native-capture]').evaluate(async image => { await image.decode() })
  const decode = async panel => {
    const image = panel.locator('[data-native-capture]')
    await image.scrollIntoViewIfNeeded()
    await page.waitForFunction(id => {
      const image = document.querySelector(`#${id} [data-native-capture]`)
      return image?.complete && image.naturalWidth > 0
    }, await panel.getAttribute('id'))
    return image.evaluate(async image => { await image.decode(); return [image.naturalWidth, image.naturalHeight] })
  }
  page.on('pageerror', error => errors.push(error.message))
  page.on('console', message => { if (message.type() === 'error') errors.push(message.text()) })
  page.on('requestfailed', request => failedRequests.push(`${request.url()}: ${request.failure()?.errorText} (after: ${checks.at(-1) ?? 'initial navigation'})`))
  page.on('request', request => requests.push({ url: request.url(), method: request.method() }))
  if (!publicHost) await page.route(`${origin}/`, async route => {
    const response = await route.fetch()
    await route.fulfill({ response, headers: { ...response.headers(), 'content-security-policy': csp } })
  })
  try {
  await verifyNativeLanding(page, origin, publicHost, csp, manifest, check)
  await verifyNativeDownloadDialog(page, focused, check)

  const macTab = page.getByRole('tab', { name: 'Mac app', exact: true })
  const phoneTab = page.getByRole('tab', { name: 'iPhone app', exact: true })
  const watchTab = page.getByRole('tab', { name: 'Apple Watch', exact: true })
  const terminalTab = page.getByRole('tab', { name: 'Terminal', exact: true })
  await verifyNativePlatformTabs(page, check, focused, macTab, phoneTab, watchTab, terminalTab)

  // The byte hashes tie served assets to the pixel-identity manifest verified against native PNGs.
  const assets = await verifyNativeAssetBytes(page, manifest, check)

  const mac = page.locator('#panel-mac')
  const phone = page.locator('#panel-iphone')
  await verifyNativeTourPickers({ macTab, mac, phoneTab, phone })

  await macTab.click()
  await verifyMacWalkthrough(mac, settleCapture, captureId, focused, check)

  await phoneTab.click()
  await verifyPhoneWalkthrough(phone, macTab, phoneTab, settleCapture, captureId, focused, check)

  await terminalTab.click()
  const { terminal, input } = await verifyNativeTerminal(page, cli, nativeStatus, check)
  const { dashboard, screen } = await verifyNativeDashboard(terminal, input, focused, check)

  await verifyNativePrivacyAndTheme(page, phoneTab, phone, captureId, focused, check)

  await verifyNativeResponsiveLayouts({ macTab, mac, phoneTab, phone, terminalTab, terminal, input, dashboard, screen })
  return await verifyNativeCompletion({ macTab, assets })
  } catch (error) {
    await page.evaluate(result => { window.__hashfleetNativeParity = result }, { status: 'failed', checks: checks.length, lastCheck: checks.at(-1), browserErrors: errors, failedRequests, message: String(error) })
    await page.screenshot({ path: 'output/playwright/product-parity-failure.png' })
    throw error
  }
}
