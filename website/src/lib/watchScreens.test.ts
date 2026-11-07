import { createElement } from 'react'
import { renderToStaticMarkup } from 'react-dom/server'
import { describe, expect, it } from 'vitest'
import App from '../App'
import WatchDemo, { WatchPreview } from '../components/WatchDemo'
import captures from './watch-captures.json'
import { watchCaptureFor, watchScreens } from './watchScreens'

describe('authentic Apple Watch capture contract', () => {
  it('maps exactly five original native captures to distinct tour steps', () => {
    expect(watchScreens.map(screen => screen.id)).toEqual(captures.captures.map(capture => capture.id))
    expect(watchScreens).toHaveLength(5)
    expect(new Set(watchScreens.map(screen => screen.id)).size).toBe(5)
    expect(new Set(captures.captures.map(capture => capture.sha256)).size).toBe(5)
    expect(captures.sourceRevision).toBe('a10fec115ba3f74ceed100f023eb235d4a009cd1')
    expect(captures.provenance).toContain('Unmodified PNG attachments')
    expect(captures.provenance).toContain('No generated app screens')
  })

  it.each(watchScreens)('$id uses its original full-resolution native PNG', screen => {
    const capture = watchCaptureFor(screen.id)
    expect(capture.src).toBe(`/images/watch/${screen.id}-20261104.png`)
    expect([capture.width, capture.height]).toEqual([368, 448])
    expect(capture.sha256).toMatch(/^[a-f0-9]{64}$/)
    expect(capture.sha256).toBe(capture.sourceSha256)
    expect(capture.bytes).toBeGreaterThan(20000)
    expect(capture.bytes).toBeLessThan(60000)
    expect(screen.label.length).toBeGreaterThan(5)
    expect(screen.description.length).toBeGreaterThan(50)
    expect(screen.transcript.length).toBeGreaterThan(80)
  })

  it('keeps the captured fleet image and its fictional numbers unchanged', () => {
    expect(watchCaptureFor('watch-fleet').sha256).toBe('bfc714a6691b115e749b11e368ab7571bc3c0d07e2ee7362a8bd03925d6f5007')
    expect(watchScreens[0].transcript).toContain('Demo data. No miners are contacted. 3.94 TH/s. 3 of 3 current. 62.9 W.')
    expect(watchScreens[1].transcript).toContain('November 3, 2026 at 8:08 PM')
  })

  it('uses only bounded Watch-to-Watch captured navigation targets', () => {
    expect(watchScreens[0].target).toBeUndefined()
    for (const screen of watchScreens) {
      if (!screen.target) continue
      const target = screen.target
      expect(watchScreens.some(item => item.id === target.id)).toBe(true)
      expect(target.label.length).toBeGreaterThan(10)
      expect(target.x).toBeGreaterThanOrEqual(0)
      expect(target.y).toBeGreaterThanOrEqual(0)
      expect(target.width).toBeGreaterThan(0)
      expect(target.height).toBeGreaterThan(0)
      expect(target.x + target.width).toBeLessThanOrEqual(100)
      expect(target.y + target.height).toBeLessThanOrEqual(100)
    }
    expect(watchScreens.find(screen => screen.id === 'watch-discovery')?.target?.id).toBe('watch-add')
    expect(watchScreens.find(screen => screen.id === 'watch-add')?.target?.id).toBe('watch-discovery')
  })

  it('rejects unknown screenshots instead of substituting a different product screen', () => {
    // @ts-expect-error Unknown IDs must also fail closed at runtime.
    expect(() => watchCaptureFor('unknown-screen')).toThrow('Missing Watch capture: unknown-screen')
  })
})

describe('honest and accessible Apple Watch product experience', () => {
  it('uses the identical real fleet capture in the hero and interactive tour', () => {
    const src = watchCaptureFor('watch-fleet').src
    for (const Component of [WatchPreview, WatchDemo]) {
      const html = renderToStaticMarkup(createElement(Component))
      expect(html).toContain(`src="${src}"`)
      expect(html).toContain('width="368" height="448"')
      expect(html).not.toContain('<canvas')
      expect(html).not.toContain('<iframe')
    }
  })

  it('offers five buttons, back, next, reset, a transcript and honest capture boundaries', () => {
    const html = renderToStaticMarkup(createElement(WatchDemo))
    expect(html.match(/data-watch-step=/g)).toHaveLength(5)
    expect(html).toContain('aria-current="step"')
    expect(html).toContain('aria-live="polite"')
    expect(html).toContain('Back')
    expect(html).toContain('Next screen')
    expect(html).toContain('Reset tour')
    expect(html).toContain('Read this Watch screen’s description')
    expect(html).toContain('No network scan, miner connection or settings change happens here.')
    expect(html).toContain('Captured times and readings do not update.')
    expect(html).toContain('watchOS 26.5+')
    expect(html).not.toContain('<input')
    expect(html).not.toContain('role="switch"')
    expect(html).not.toContain('type="checkbox"')
    expect(html).not.toContain('data-native-capture')
  })

  it('integrates the fourth tab without replacing existing product demos', () => {
    const html = renderToStaticMarkup(createElement(App))
    expect(html.match(/role="tab"/g)).toHaveLength(4)
    expect(html.match(/role="tabpanel"/g)).toHaveLength(4)
    expect(html).toContain('aria-controls="panel-watch"')
    expect(html).toContain('aria-labelledby="tab-watch"')
    expect(html).toContain('Explore the captured Apple Watch screens')
    expect(html).toContain('Four ways in.')
    expect(html).toContain('On your wrist.')
    expect(html).toContain('04 / TERMINAL')
    expect(html).toContain('What can I do on Apple Watch?')
    expect(html).toContain('import miner names and local addresses')
    expect(html).toContain('not from the iPhone or continuous background monitoring')
    expect(html).not.toContain('receive a fleet snapshot from the iPhone')
    // Contact details live on the dedicated support page and privacy dialog.
    expect(html).toContain('href="/support/"')
    expect(html).not.toContain('tel:')
  })
})
