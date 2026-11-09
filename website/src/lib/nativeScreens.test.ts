import { createElement } from 'react'
import { renderToStaticMarkup } from 'react-dom/server'
import { describe, expect, it } from 'vitest'
import App from '../App'
import { IPhoneDemo, MacDemo, NativePreview } from '../components/AppDemos'
import captures from './native-captures.json'
import { captureFor, nativeScreens, screensFor } from './nativeScreens'
import { compareText } from './order'

describe('actual native capture contract', () => {
  it('maps every screen to exactly one distinct reviewed capture', () => {
    const ids = nativeScreens.map(screen => screen.id)
    expect(new Set(ids).size).toBe(ids.length)
    expect(captures.captures.map(capture => capture.id).sort(compareText)).toEqual([...ids].sort(compareText))
    expect(new Set(captures.captures.map(capture => capture.sha256)).size).toBe(ids.length)
    expect(screensFor('mac')).toHaveLength(11)
    expect(screensFor('iphone')).toHaveLength(7)
  })

  it.each(nativeScreens)('$id uses a versioned same-origin full-resolution native image', screen => {
    const capture = captureFor(screen.id)
    expect(capture.src).toBe(`/images/native/${screen.id}-${captures.capturedAt.replaceAll('-', '')}.webp`)
    expect([capture.width, capture.height]).toEqual(screen.platform === 'mac' ? [2880, 2000] : [1206, 2622])
    expect(capture.sourceSha256).toMatch(/^[a-f0-9]{64}$/)
    expect(capture.sha256).toMatch(/^[a-f0-9]{64}$/)
    expect(capture.rgbaSha256).toMatch(/^[a-f0-9]{64}$/)
    expect(capture.bytes).toBeGreaterThan(1000)
    expect(capture.bytes).toBeLessThan(600000)
    expect(screen.label.length).toBeGreaterThan(3)
    expect(screen.description.length).toBeGreaterThan(30)
    expect(screen.transcript.length).toBeGreaterThan(60)
  })

  it('keeps every hotspot within its image and on the same native platform', () => {
    for (const screen of nativeScreens) {
      for (const target of screen.targets) {
        expect(nativeScreens.find(item => item.id === target.target)?.platform).toBe(screen.platform)
        expect(target.label.length).toBeGreaterThan(2)
        expect(target.x).toBeGreaterThanOrEqual(0)
        expect(target.y).toBeGreaterThanOrEqual(0)
        expect(target.width).toBeGreaterThan(0)
        expect(target.height).toBeGreaterThan(0)
        expect(target.x + target.width).toBeLessThanOrEqual(100)
        expect(target.y + target.height).toBeLessThanOrEqual(100)
      }
    }
  })

  it('fails closed on an unknown native image instead of substituting a different screen', () => {
    expect(() => captureFor('not-a-screen')).toThrow('Missing native capture: not-a-screen')
  })

  it('keeps real phone gear-menu navigation and settings labels, not invented tabs', () => {
    const home = nativeScreens.find(screen => screen.id === 'ios-fleet')!
    const gear = nativeScreens.find(screen => screen.id === 'ios-current')!
    expect(home.targets.map(target => target.target)).toEqual(['ios-current'])
    expect(gear.targets.map(target => target.target)).toEqual(['ios-settings', 'ios-about'])
    for (const id of ['ios-settings', 'mac-settings']) {
      const transcript = nativeScreens.find(screen => screen.id === id)!.transcript
      expect(transcript).toContain('Notifications and banners')
      expect(transcript).toContain('Your fleet')
      expect(transcript).toContain('Across iOS')
      expect(transcript).not.toContain('Connections. Connectivity')
    }
    expect(nativeScreens.find(screen => screen.id === 'ios-office')!.transcript).toContain('office-demo.invalid')
  })
})

describe('transparent captured-screen walkthroughs', () => {
  it.each([['Mac', MacDemo], ['iPhone', IPhoneDemo]] as const)('%s explains exactly what works in the browser', (platform, Component) => {
    const markup = renderToStaticMarkup(createElement(Component))
    expect(markup).toContain('ACTUAL NATIVE APP SCREENS')
    expect(markup).toContain(`real ${platform} app`)
    expect(markup).toContain('not a recreated dashboard or a live app stream')
    expect(markup).toContain('Other controls are part of the image')
    expect(markup).toContain('No device connections. No settings changes.')
    expect(markup).toContain('Read this screen’s description')
    expect(markup).toContain('aria-label="' + platform + ' capture viewport, scroll to inspect the screen"')
    expect(markup).toContain('Reset tour')
    expect(markup).toContain('Enlarge screen')
    expect(markup).not.toContain('role="switch"')
    expect(markup).not.toContain('type="checkbox"')
    expect(markup).not.toContain('phone-tab-bar')
    expect(markup).not.toContain('app-summary')
    expect(markup).not.toContain('<iframe')
  })

  it.each(['mac', 'iphone'] as const)('uses the identical %s image in the hero and walkthrough', platform => {
    const preview = renderToStaticMarkup(createElement(NativePreview, { platform }))
    const tour = renderToStaticMarkup(createElement(platform === 'mac' ? MacDemo : IPhoneDemo))
    const source = captureFor(platform === 'mac' ? 'mac-overview' : 'ios-fleet').src
    expect(preview).toContain(`src="${source}"`)
    expect(tour).toContain(`src="${source}"`)
    expect(preview).toContain('native-preview')
  })

  it('does not leave the old invented phone UI in the marketing hero', () => {
    const markup = renderToStaticMarkup(createElement(App))
    expect(markup).toContain('Explore the captured iPhone screens')
    expect(markup).toContain('HASH FLEET')
    expect(markup).toContain('3/3 online')
    expect(markup).toContain('Real native screens. Actual CLI output. Fictional miners.')
    expect(markup).not.toMatch(/class="(?:mini-phone-tabs|phone-tab-bar|phone-settings-page|phone-hash-card)/)
    expect(markup).not.toContain('Restart device')
    expect(markup).not.toContain('No CPU host')
    expect(markup).toContain('Native switches, add-miner, refresh, export, and hardware controls visible in images are not running here.')
    expect(markup).toContain('The website only navigates captured native screens and simulates allowlisted CLI commands.')
  })
})
