/** Match JavaScript's default UTF-16 string ordering, independent of host locale. */
export function compareText(left: string, right: string): number {
  if (left < right) return -1
  if (left > right) return 1
  return 0
}
