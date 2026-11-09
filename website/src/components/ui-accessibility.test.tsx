import { renderToStaticMarkup } from 'react-dom/server'
import { describe, expect, it } from 'vitest'
import { IPhoneDemo, MacDemo } from './AppDemos'
import DashboardPreview from './DashboardPreview'
import SupportSection from './SupportSection'
import TerminalDemo from './TerminalDemo'

describe('intentional UI accessibility and contrast contracts', () => {
  it('keeps the CLI keyboard viewport focusable without a fake widget role', () => {
    const html = renderToStaticMarkup(<DashboardPreview onExit={() => undefined} />)
    expect(html).toContain('<section class="cli-dashboard__viewport" tabindex="0" aria-label="Interactive CLI fleet">')
    expect(html).toContain('aria-label="Selected demo miner"')
    expect(html).not.toMatch(/role="(?:application|button|textbox)"/)
  })
  it('keeps terminal output keyboard-scrollable and labelled', () => {
    const html = renderToStaticMarkup(<TerminalDemo />)
    expect(html).toContain('<section class="terminal-demo__output" aria-label="Terminal command output" tabindex="0">')
  })
  it.each([
    ['Mac', MacDemo],
    ['iPhone', IPhoneDemo],
  ] as const)('preserves %s viewport focus and flow content inside its live status', (platform, Component) => {
    const html = renderToStaticMarkup(<Component />)
    expect(html).toMatch(/<div class="native-screen-status" role="status"><h3 tabindex="-1">.+?<\/h3><p>.+?<\/p><\/div>/)
    expect(html).toContain(`tabindex="0" aria-label="${platform} capture viewport, scroll to inspect the screen"`)
    expect(html).not.toMatch(/<output[^>]*><h3/)
  })
  it('retains focusable receiving addresses and associated copy controls', () => {
    const html = renderToStaticMarkup(<SupportSection />)
    for (const symbol of ['btc', 'eth', 'sol']) {
      expect(html).toContain(`<code id="support-address-${symbol}" tabindex="0" aria-label=`)
      expect(html).toContain(`aria-describedby="support-address-${symbol}"`)
    }
  })
})
