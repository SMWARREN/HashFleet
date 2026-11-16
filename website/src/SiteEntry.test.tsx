import { renderToStaticMarkup } from 'react-dom/server'
import { afterEach, describe, expect, it, vi } from 'vitest'
import SiteEntry from './SiteEntry'

afterEach(() => vi.unstubAllGlobals())

function renderLocation(pathname: string, hash: string) {
  vi.stubGlobal('window', { location: { pathname, hash } })
  return renderToStaticMarkup(<SiteEntry />)
}

describe('addressable dialogs through the real site entry', () => {
  it.each(['/', '/index.html', '/demo', '/demo/mac', '/demo/iphone', '/demo/terminal'])('renders the download dialog at %s#download', pathname => {
    const html = renderLocation(pathname, '#download')
    expect(html).toContain('<dialog class="site-dialog site-dialog--download" aria-labelledby="dialog-title">')
    expect(html).toContain('<h2 id="dialog-title">Download Hash Fleet</h2>')
    expect(html).toContain('aria-label="Close dialog" autofocus=""')
    expect(html).toContain('Awaiting approval')
    expect(html).toContain('Hash Fleet FAQ.')
    if (pathname === '/demo/iphone' || pathname === '/demo/terminal') {
      const platform = pathname.split('/').at(-1)
      expect(html).toContain(`id="tab-${platform}" role="tab" aria-selected="true"`)
    }
  })

  it('preserves the privacy dialog and contact content at #privacy', () => {
    const html = renderLocation('/', '#privacy')
    expect(html).toContain('<dialog class="site-dialog" aria-labelledby="dialog-title">')
    expect(html).toContain('<h2 id="dialog-title">Your fleet stays yours.</h2>')
    expect(html).toContain('href="mailto:support@hashfleet.app"')
    expect(html).not.toContain('data-download="ios"')
  })

  it.each(['', '#support', '#download?next=https://example.invalid'])('keeps the homepage closed for %s', fragment => {
    expect(renderLocation('/', fragment)).not.toContain('<dialog')
  })

  it('does not turn the download fragment into a server route or bypass unavailable pages', () => {
    const html = renderLocation('/download', '#download')
    expect(html).toContain('data-route-unavailable="true"')
    expect(html).not.toContain('<dialog')
  })
})
