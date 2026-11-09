import { isValidElement } from 'react'
import type { CSSProperties, ReactElement, ReactNode } from 'react'
import { renderToStaticMarkup } from 'react-dom/server'
import { describe, expect, it, vi } from 'vitest'
import AnsiOutput from './AnsiOutput'

// Inspect generated keys without mounting a browser or replacing React's renderer.
vi.mock('react', async importOriginal => ({
  ...await importOriginal<typeof import('react')>(),
  useMemo: <T,>(factory: () => T) => factory(),
}))

type Span = ReactElement<{ children: ReactNode, style: CSSProperties }>
function runs(value: string): Span[] {
  return AnsiOutput({ value }).props.children
}
function pixels(run: Span): Span[] {
  return (run.props.children as ReactNode[]).filter((node): node is Span => isValidElement(node))
}

const red = '\x1b[38;2;255;0;0m'
const reset = '\x1b[0m'

describe('ANSI output reconciliation and rendering', () => {
  it('keeps an unchanged run identity when unrelated runs are prepended', () => {
    const before = runs(`${red}red${reset}plain`)
    const after = runs(`prefix${red}red${reset}plain`)
    expect(after.slice(1).map(run => run.key)).toEqual(before.map(run => run.key))
  })
  it('uses distinct stable identities for repeated text with the same or different styles', () => {
    const value = `${red}same${reset}same${red}same`
    const keys = runs(value).map(run => run.key)
    expect(new Set(keys).size).toBe(3)
    expect(runs(value).map(run => run.key)).toEqual(keys)
    expect(runs(`${red}same`)[0].key).not.toBe(runs('same')[0].key)
  })
  it('keeps half-block identities when unrelated half-blocks are inserted', () => {
    const before = pixels(runs('▀▀ gap ▄▄')[0])
    const after = pixels(runs('▀ prefix ▀▀ gap ▄▄')[0])
    expect(after.slice(1).map(part => part.key)).toEqual(before.map(part => part.key))
  })
  it('keeps repeated half-block keys unique and gradients correctly oriented', () => {
    const parts = pixels(runs(`${red}\x1b[48;2;0;0;255m▀ gap ▄ gap ▀`)[0])
    expect(new Set(parts.map(part => part.key)).size).toBe(3)
    expect(parts[0].props.style.backgroundImage).toBe('linear-gradient(to bottom, rgb(255, 0, 0) 50%, rgb(0, 0, 255) 50%)')
    expect(parts[1].props.style.backgroundImage).toBe('linear-gradient(to bottom, rgb(0, 0, 255) 50%, rgb(255, 0, 0) 50%)')
  })
  it('preserves text, emphasis, opacity and escaping without interpreting HTML', () => {
    expect(renderToStaticMarkup(<AnsiOutput value={'\x1b[1;2m<b>&\x1b[0m plain'} />)).toBe('<span style="font-weight:700;opacity:0.72">&lt;b&gt;&amp;</span><span> plain</span>')
    expect(renderToStaticMarkup(<AnsiOutput value="" />)).toBe('')
  })
  it('preserves half-block fallback colors and plain text between pixel spans', () => {
    const html = renderToStaticMarkup(<AnsiOutput value="▀ text ▄" />)
    expect(html).toContain('linear-gradient(to bottom, currentColor 50%, transparent 50%)')
    expect(html).toContain('linear-gradient(to bottom, transparent 50%, currentColor 50%)')
    expect(html).toContain('</span> text <span')
  })
})
