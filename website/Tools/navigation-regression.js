async (page) => {
  const observations = []
  const errors = []
  page.on('pageerror', error => errors.push(error.message))
  await page.emulateMedia({ reducedMotion: 'reduce' })
  await page.setViewportSize({ width: 1440, height: 1000 })
  const focused = locator => locator.evaluate(element => document.activeElement === element)
  for (const [build, origin] of [['previous', 'http://127.0.0.1:4176'], ['current', 'http://127.0.0.1:4175']]) {
    const response = await page.goto(origin)
    if (response.status() !== 200 || !response.headers()['content-security-policy']) throw new Error('Actual artifact/server did not load')
    await page.getByRole('heading', { level: 1 }).waitFor()
    const scriptAsset = await page.locator('script[type="module"]').getAttribute('src')
    const macTab = page.getByRole('tab', { name: 'Mac app', exact: true })
    await page.getByRole('button', { name: 'Take it for a spin' }).click()
    const ctaTabFocused = await focused(macTab)
    const mac = page.locator('#panel-mac')
    await mac.getByRole('button', { name: 'Inspect MacBook Pro', exact: true }).click()
    const macDetailBackFocused = await focused(mac.getByRole('button', { name: 'Back to fleet' }))
    await mac.getByRole('button', { name: 'Back to fleet' }).click()
    await page.getByRole('tab', { name: 'iPhone app', exact: true }).click()
    const phone = page.locator('#panel-iphone')
    await phone.getByRole('button', { name: 'Inspect MacBook Pro on iPhone' }).click()
    const phoneDetailBackFocused = await focused(phone.getByRole('button', { name: 'Back to fleet' }))
    const phoneDetailScrollTop = await phone.locator('.phone-scroll').evaluate(element => element.scrollTop)
    await phone.getByRole('button', { name: 'Back to fleet' }).click()
    const phoneMinerReturnFocused = await focused(phone.getByRole('button', { name: 'Inspect MacBook Pro on iPhone' }))
    const phoneFleetScrollTop = await phone.locator('.phone-scroll').evaluate(element => element.scrollTop)
    observations.push({ build, origin, scriptAsset, ctaTabFocused, macDetailBackFocused, phoneDetailBackFocused, phoneDetailScrollTop, phoneMinerReturnFocused, phoneFleetScrollTop })
  }
  const [previous, current] = observations
  if (previous.scriptAsset === current.scriptAsset) throw new Error('Comparison used the same artifact twice')
  for (const key of ['ctaTabFocused', 'macDetailBackFocused', 'phoneDetailBackFocused', 'phoneMinerReturnFocused']) {
    if (previous[key] !== false || current[key] !== true) throw new Error(`Expected observed improvement for ${key}`)
  }
  if (current.phoneDetailScrollTop !== 0 || current.phoneFleetScrollTop <= 0) throw new Error('Current iPhone scroll behavior is not restored')
  if (errors.length) throw new Error(`Actual browser errors: ${errors.join(', ')}`)
  return await page.evaluate(result => {
    window.__hashfleetNavigationComparison = result
    return result
  }, { status: 'passed', responseInterception: false, appSourceImported: false, observations, browserErrors: errors })
}
