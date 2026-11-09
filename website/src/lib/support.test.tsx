import { describe, expect, it, vi } from 'vitest'
import { renderToStaticMarkup } from 'react-dom/server'
import SupportSection from '../components/SupportSection'
import { copySupportAddress, cryptoSupport, paypalSupportURL } from './support'

const expected = [
  ['BTC', 'Bitcoin mainnet', '1AZLMVdq1Dpc8FqibVUoMqJkh5wMQpd1wg'],
  ['ETH', 'Ethereum mainnet', '0xe0297d17680a3fa52975cf1cfc27bd2c1e73010c'],
  ['SOL', 'Solana mainnet', '2Ny4ZFGWtdVix4ZhGWCq3VCKLBRMC75aduCrYJUavA27'],
]
describe('public developer support', () => {
  it('preserves the exact owner-supplied destinations and mainnets', () => {
    expect(cryptoSupport.map(({ symbol, network, address }) => [symbol, network, address])).toEqual(expected)
    expect(paypalSupportURL).toBe('https://www.paypal.com/ncp/payment/6NAMWWPAKSFV2')
  })
  it.each(expected)('copies the exact %s destination', async (_symbol, _network, address) => {
    const writeText = vi.fn().mockResolvedValue(undefined)
    expect(await copySupportAddress(address, { writeText })).toBe(true)
    expect(writeText).toHaveBeenCalledExactlyOnceWith(address)
  })
  it('does not copy an unreviewed destination', async () => {
    const writeText = vi.fn()
    expect(await copySupportAddress('unreviewed-address', { writeText })).toBe(false)
    expect(writeText).not.toHaveBeenCalled()
  })
  it('handles unavailable or denied clipboard access', async () => {
    expect(await copySupportAddress(expected[0][2])).toBe(false)
    expect(await copySupportAddress(expected[0][2], { writeText: vi.fn().mockRejectedValue(new Error('denied')) })).toBe(false)
  })
  it('renders accessible copy controls, safe external link and optional-tip notices without browser globals', () => {
    const html = renderToStaticMarkup(<SupportSection />)
    for (const [symbol, network, address] of expected) {
      expect(html).toContain(address)
      expect(html).toContain(network + ' only')
      expect(html).toContain('aria-label="Copy ' + symbol + ' address"')
    }
    expect(html).toContain('target="_blank" rel="noopener noreferrer"')
    expect(html).toContain('No features are purchased or unlocked.')
    expect(html).toContain('These transfers are separate from PayPal.')
    expect(html.match(/role="status"/g)).toHaveLength(3)
    expect(html).not.toMatch(/<script|<iframe|<form/)
  })
})
