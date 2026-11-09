import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'

const terminalCSS = readFileSync(new URL('./terminal.css', import.meta.url), 'utf8')

function declaration(selector, property) {
  const rule = terminalCSS.split(`${selector} {`)[1]?.split('}')[0]
  const value = rule?.split(';').find(item => item.trim().startsWith(`${property}:`))?.split(':').slice(1).join(':').trim()
  if (!value) throw new Error(`Missing ${property} declaration for ${selector}`)
  return value
}
function rgb(hex) {
  return [1, 3, 5].map(offset => Number.parseInt(hex.slice(offset, offset + 2), 16) / 255)
}
function luminance(channels) {
  return channels.reduce((sum, channel, index) => sum + (channel <= 0.04045 ? channel / 12.92 : ((channel + 0.055) / 1.055) ** 2.4) * [0.2126, 0.7152, 0.0722][index], 0)
}

describe('terminal CSS accessibility contracts', () => {
  it('preserves overflow scrolling for the focusable terminal viewport', () => {
    expect(declaration('.terminal-demo__output', 'overflow')).toBe('auto')
    expect(declaration('.cli-dashboard__viewport', 'overflow')).toBe('auto')
  })
  it('meets normal-text contrast after compositing the actual translucent button over its terminal canvas', () => {
    const canvas = rgb(declaration('.terminal-demo', '--terminal-canvas'))
    const background = declaration('.terminal-demo__suggestions button', 'background')
    expect(background).toMatch(/^#[\da-f]{8}$/i)
    const alpha = Number.parseInt(background.slice(7, 9), 16) / 255
    const composite = rgb(background).map((channel, index) => channel * alpha + canvas[index] * (1 - alpha))
    const foreground = rgb(declaration('.terminal-demo__suggestions button', 'color'))
    const contrast = (luminance(foreground) + 0.05) / (luminance(composite) + 0.05)
    expect(contrast).toBeGreaterThanOrEqual(4.5)
    expect(contrast).toBeCloseTo(10.553132201758501, 6)
  })
})
