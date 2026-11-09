import { describe, expect, it } from 'vitest'
import { privacyFragment, resolveSiteDialog, resolveSiteRoute } from './routes'

describe('privacy policy permalink', () => {
  it('opens only the explicit privacy fragment', () => {
    expect(privacyFragment).toBe('#privacy')
    expect(resolveSiteDialog('#privacy')).toBe('privacy')
  })
  it.each(['', '#', '#support', '#download', '#Privacy', '#privacy/', '#privacy?next=https://example.invalid', '#privacy%20', '#%70rivacy', '#https://example.invalid', '#<script>'])('does not open a dialog for %s', fragment => {
    expect(resolveSiteDialog(fragment)).toBeNull()
  })
})

describe('single-entry website routes', () => {
  it.each(['/', '/index.html'])('keeps the original homepage at %s', path => {
    expect(resolveSiteRoute(path)).toEqual({ kind: 'home' })
  })
  it.each(['/demo', '/demo/'])('defaults %s to the actual Mac preview', path => {
    expect(resolveSiteRoute(path)).toEqual({ kind: 'demo', platform: 'mac' })
  })
  it.each(['mac', 'iphone', 'terminal'] as const)('selects the %s preview from the path', platform => {
    expect(resolveSiteRoute(`/demo/${platform}`)).toEqual({ kind: 'demo', platform })
    expect(resolveSiteRoute(`/demo/${platform}/`)).toEqual({ kind: 'demo', platform })
  })
  it.each(['/.env.local', '/.git/config', '/api/v1.php', '/assets/missing.js', '/images/',
    '/hashfleet-private/config.php', '/missing-native-parity-page', '/demo/unknown',
    '/demo/iphone/extra', '//demo/mac', '/DEMO/MAC', '/demo/%69phone',
    '/<script>alert(1)</script>', '/%ZZ', '/index.html/extra'])('does not treat %s as a public page', path => {
    expect(resolveSiteRoute(path)).toEqual({ kind: 'unavailable' })
  })
})
