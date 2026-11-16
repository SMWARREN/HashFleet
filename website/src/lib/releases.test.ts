import { describe, expect, it } from 'vitest'
import { IOS_APP_STORE_URL, iosReleaseUrl, safeReleaseUrl } from './releases'

describe('public release links', () => {
  it.each([undefined, null, '', '   '])('defaults an unset iOS override (%s) to the launched app', value => {
    expect(iosReleaseUrl(value)).toBe('https://apps.apple.com/us/app/hash-fleet/id6812623943')
  })

  it('retains a valid explicit iOS release override', () => {
    expect(iosReleaseUrl('https://apps.apple.com/app/id6812623943')).toBe('https://apps.apple.com/app/id6812623943')
  })

  it.each(['http://example.com/app', 'javascript:alert(1)', 'not a URL', 'https://user:password@example.com/app'])('rejects an unsafe override without silently using the default: %s', value => {
    expect(iosReleaseUrl(value)).toBeUndefined()
    expect(safeReleaseUrl(value)).toBeUndefined()
  })

  it('keeps the verified App Store URL safe for public navigation', () => {
    expect(safeReleaseUrl(IOS_APP_STORE_URL)).toBe(IOS_APP_STORE_URL)
  })
})
