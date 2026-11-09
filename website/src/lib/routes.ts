export type PreviewPlatform = 'mac' | 'iphone' | 'terminal'
export type SiteRoute = { kind: 'home' } | { kind: 'demo', platform: PreviewPlatform } | { kind: 'unavailable' }

export const privacyFragment = '#privacy'

// Fragments stay on the existing page and never become redirect destinations.
export function resolveSiteDialog(fragment: string): 'privacy' | null {
  return fragment === privacyFragment ? 'privacy' : null
}

// An explicit page allowlist, not a file/API router or a redirect destination.
export function resolveSiteRoute(pathname: string): SiteRoute {
  if (pathname === '/' || pathname === '/index.html') return { kind: 'home' }
  const match = /^\/demo(?:\/(mac|iphone|terminal))?\/?$/.exec(pathname)
  if (match) return { kind: 'demo', platform: (match[1] ?? 'mac') as PreviewPlatform }
  return { kind: 'unavailable' }
}
