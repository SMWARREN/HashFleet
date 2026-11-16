import { renderToStaticMarkup } from 'react-dom/server'
import { describe, expect, it } from 'vitest'
import DownloadOptions from './DownloadOptions'
import { resolveReleaseLinks } from '../lib/releases'

const defaultLinks = resolveReleaseLinks()
const render = (overrides: Parameters<typeof resolveReleaseLinks>[0] = {}) => renderToStaticMarkup(<DownloadOptions links={resolveReleaseLinks(overrides)} />)

describe('download channel contracts', () => {
  it('puts the real iPhone and iPad App Store action first, ahead of direct Mac and CLI', () => {
    const html = render()
    const hrefs = [...html.matchAll(/<a\b[^>]*href="([^"]+)"/g)].map(match => match[1])
    expect(hrefs.slice(0, 3)).toEqual([
      'https://apps.apple.com/us/app/hash-fleet/id6812623943',
      'https://github.com/SMWARREN/HashFleet/releases/latest/download/HashFleet-macos-arm64.zip',
      'https://github.com/SMWARREN/HashFleet/releases/latest/download/hashfleet-cli-macos-arm64.tar.gz',
    ])
    expect(html).toContain('<h2 id="dialog-title">Download Hash Fleet</h2>')
    expect(html).toContain('iPhone &amp; iPad')
    expect(html).toContain('download-options__action--primary')
  })

  it('identifies the native Mac App Store as pending status, never as an iPad or active download', () => {
    const html = render()
    const pendingRow = html.split('data-download="mac-store"')[1].split('</section>')[0]
    expect(pendingRow).toContain('Mac App Store')
    expect(pendingRow).toContain('Native Mac app · not yet released')
    expect(pendingRow).toContain('Awaiting approval')
    expect(pendingRow).not.toMatch(/<a\b|<button\b|href=|iPad/)
    expect(html.indexOf('data-download="mac-store"')).toBeLessThan(html.indexOf('data-download="mac-direct"'))
  })

  it('keeps the included Watch note and exact OS requirement with the iOS channel', () => {
    const html = render()
    expect(html).toContain('Apple Watch included with the iOS app · watchOS 26.5+')
    expect(html.indexOf('watchOS 26.5+')).toBeLessThan(html.indexOf('data-download="mac-store"'))
  })

  it('describes signed native direct Mac and separately installed terminal packages accurately', () => {
    const html = render()
    expect(html).toContain('Direct download · v1.0.0')
    expect(html).toContain('macOS 14+ · native Mac app')
    expect(html).toContain('Separate installation · v1.0.0')
    expect(html).toContain('Apple Silicon · macOS 14+ · terminal only')
    expect(html.match(/Developer ID signed and Apple-notarized/g)).toHaveLength(2)
    expect(html).toContain('Installs independently of the Mac app.')
    expect(html).not.toMatch(/unsigned|nightly|Windows|Linux|Intel|menu.bar|Coming soon/i)
  })

  it('provides real Homebrew setup, release notes, checksum and source destinations', () => {
    const html = render()
    for (const href of [
      'https://github.com/SMWARREN/HashFleet/blob/main/docs/HOMEBREW.md',
      'https://github.com/SMWARREN/HashFleet/releases/latest',
      'https://github.com/SMWARREN/HashFleet/releases/latest/download/SHA256SUMS.txt',
      'https://github.com/SMWARREN/HashFleet',
    ]) expect(html).toContain(`href="${href}"`)
    expect(html).toContain('brew install hashfleet-cli')
    const anchors = html.match(/<a\b[^>]*>/g) ?? []
    expect(anchors).toHaveLength(7)
    for (const anchor of anchors) expect(anchor).toContain('target="_blank" rel="noopener noreferrer"')
  })

  it.each(['http://example.invalid/file', 'javascript:alert(1)', 'not a URL', 'https://user:password@example.invalid/file'])('disables each unsafe override instead of substituting downloads: %s', value => {
    const links = resolveReleaseLinks({ mac: value, ios: value, cli: value, source: value })
    expect(links).toEqual({ mac: undefined, ios: undefined, cli: undefined, source: undefined })
    const html = renderToStaticMarkup(<DownloadOptions links={links} />)
    for (const message of ['App Store link unavailable', 'Mac download unavailable', 'CLI download unavailable', 'Source link unavailable']) {
      expect(html).toContain(message)
    }
    for (const href of Object.values(defaultLinks)) expect(html).not.toContain(`href="${href}"`)
    expect(html).not.toContain(value)
    expect(html).toContain('Awaiting approval')
  })

  it.each(['mac', 'ios', 'cli', 'source'] as const)('an invalid %s override leaves the other channels intact', channel => {
    const links = resolveReleaseLinks({ [channel]: 'http://example.invalid/unsafe' })
    expect(links[channel]).toBeUndefined()
    for (const other of ['mac', 'ios', 'cli', 'source'] as const) {
      if (other !== channel) expect(links[other]).toBe(defaultLinks[other])
    }
  })

  it.each([undefined, null, '', '   '])('retains published defaults for empty overrides (%s)', value => {
    expect(resolveReleaseLinks({ mac: value, ios: value, cli: value, source: value })).toEqual(defaultLinks)
  })

  it('preserves valid explicit HTTPS overrides through the reusable component', () => {
    const html = render({ mac: 'https://example.invalid/mac.zip', ios: 'https://example.invalid/ios', cli: 'https://example.invalid/cli.tar.gz', source: 'https://example.invalid/source' })
    for (const path of ['mac.zip', 'ios', 'cli.tar.gz', 'source']) {
      expect(html).toContain(`href="https://example.invalid/${path}"`)
    }
  })
})
