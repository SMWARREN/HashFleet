/** Public receiving destinations supplied by the project owner. Never add wallet secrets. */
export const paypalSupportURL = 'https://www.paypal.com/ncp/payment/6NAMWWPAKSFV2'

export const cryptoSupport = [
  { symbol: 'BTC', name: 'Bitcoin', network: 'Bitcoin mainnet', address: '1AZLMVdq1Dpc8FqibVUoMqJkh5wMQpd1wg' },
  { symbol: 'ETH', name: 'Ethereum', network: 'Ethereum mainnet', address: '0xe0297d17680a3fa52975cf1cfc27bd2c1e73010c' },
  { symbol: 'SOL', name: 'Solana', network: 'Solana mainnet', address: '2Ny4ZFGWtdVix4ZhGWCq3VCKLBRMC75aduCrYJUavA27' },
] as const

export type CryptoSupport = typeof cryptoSupport[number]
type ClipboardWriter = Pick<Clipboard, 'writeText'>

/** An explicit click copies only a static public address, never a transaction request. */
export async function copySupportAddress(address: string, clipboard?: ClipboardWriter): Promise<boolean> {
  if (!cryptoSupport.some(destination => destination.address === address) || !clipboard) return false
  try {
    await clipboard.writeText(address)
    return true
  } catch {
    return false
  }
}
