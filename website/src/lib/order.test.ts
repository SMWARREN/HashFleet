import { describe, expect, it } from 'vitest'
import { compareText } from './order'

describe('deterministic text ordering', () => {
  it('orders by UTF-16 code units rather than host locale or numeric collation', () => {
    expect(['z', '10', '2', '_', 'A', 'a', 'ä', '', '😀'].sort(compareText))
      .toEqual(['', '10', '2', 'A', '_', 'a', 'z', 'ä', '😀'])
    expect(compareText('same', 'same')).toBe(0)
    expect(compareText('a', 'aa')).toBe(-1)
    expect(compareText('aa', 'a')).toBe(1)
  })
})
