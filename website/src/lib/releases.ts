export const IOS_APP_STORE_URL = 'https://apps.apple.com/us/app/hash-fleet/id6812623943'

export function safeReleaseUrl(value: unknown): string | undefined {
  if (typeof value !== 'string' || value.trim() === '') return undefined
  try {
    const url = new URL(value)
    return url.protocol === 'https:' && !url.username && !url.password ? url.href : undefined
  } catch { return undefined }
}

export function iosReleaseUrl(value: unknown): string | undefined {
  return safeReleaseUrl(typeof value === 'string' && value.trim() !== '' ? value : IOS_APP_STORE_URL)
}

const REPOSITORY_URL = 'https://github.com/SMWARREN/HashFleet'
// The release pipeline publishes these unversioned aliases with each release.
const LATEST_DOWNLOAD = `${REPOSITORY_URL}/releases/latest/download`
export const RELEASE_NOTES_URL = `${REPOSITORY_URL}/releases/latest`
export const CHECKSUMS_URL = `${LATEST_DOWNLOAD}/SHA256SUMS.txt`
export const HOMEBREW_SETUP_URL = `${REPOSITORY_URL}/blob/main/docs/HOMEBREW.md`

export function resolveReleaseLinks(overrides: { mac?: unknown, ios?: unknown, cli?: unknown, source?: unknown } = {}) {
  const releaseUrl = (value: unknown, fallback: string) => safeReleaseUrl(
    typeof value === 'string' && value.trim() !== '' ? value : fallback,
  )
  return {
    mac: releaseUrl(overrides.mac, `${LATEST_DOWNLOAD}/HashFleet-macos-arm64.zip`),
    ios: iosReleaseUrl(overrides.ios),
    cli: releaseUrl(overrides.cli, `${LATEST_DOWNLOAD}/hashfleet-cli-macos-arm64.tar.gz`),
    source: releaseUrl(overrides.source, REPOSITORY_URL),
  }
}

export type ReleaseLinks = ReturnType<typeof resolveReleaseLinks>
