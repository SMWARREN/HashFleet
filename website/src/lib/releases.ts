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
