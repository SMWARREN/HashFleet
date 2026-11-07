import { useRef, useState } from 'react'
import Icon from './Icon'
import { copySupportAddress, cryptoSupport, paypalSupportURL } from '../lib/support'
import type { CryptoSupport } from '../lib/support'
import './support.css'

function CryptoCard({ destination }: { destination: CryptoSupport }) {
  const [status, setStatus] = useState('')
  const [copying, setCopying] = useState(false)
  const addressRef = useRef<HTMLElement>(null)
  const addressID = `support-address-${destination.symbol.toLowerCase()}`

  async function copyAddress() {
    if (copying) return
    setCopying(true)
    setStatus('')
    // Getter access can itself be denied. Always retain a manual selection fallback.
    let copied = false
    try { copied = await copySupportAddress(destination.address, navigator.clipboard) } catch { /* handled below */ }
    if (copied) {
      setStatus(`${destination.symbol} address copied. Verify the address and network in your wallet.`)
    } else {
      addressRef.current?.focus()
      if (addressRef.current) {
        const selection = window.getSelection()
        const range = document.createRange()
        range.selectNodeContents(addressRef.current)
        selection?.removeAllRanges()
        selection?.addRange(range)
      }
      setStatus('Automatic copy is unavailable. Select and copy the full address shown above.')
    }
    setCopying(false)
  }

  return <article className="support-crypto-card" aria-labelledby={`support-title-${destination.symbol}`}>
    <div className="support-coin-heading"><span className="support-coin-symbol" aria-hidden="true">{destination.symbol}</span><div>
      <h3 id={`support-title-${destination.symbol}`}>{destination.name}</h3>
      <p>{destination.network} only</p>
    </div></div>
    <code id={addressID} ref={addressRef} tabIndex={0} aria-label={`${destination.name} receiving address`}>{destination.address}</code>
    <button type="button" className="button support-copy" aria-label={`Copy ${destination.symbol} address`} aria-describedby={addressID} disabled={copying} onClick={copyAddress}>
      {copying ? 'Copying…' : `Copy ${destination.symbol} address`} <Icon name="arrow" size={16} />
    </button>
    <p className="support-copy-status" role="status" aria-live="polite" aria-atomic="true">{status}</p>
  </article>
}

export default function SupportSection() {
  return <section className="support-section container" id="support" aria-labelledby="support-heading">
    <div className="support-intro"><div><span className="eyebrow">INDEPENDENT. OPEN SOURCE. COMMUNITY SUPPORTED.</span>
      <h2 id="support-heading">Support Hash Fleet.</h2>
      <p>If Hash Fleet makes your day a little easier, you can leave an optional developer tip. The app stays free. No features are purchased or unlocked.</p>
    </div><span className="support-thanks">Thank you for helping<br />keep development going.</span></div>
    <div className="support-paypal"><div><h3>A simple way to say thanks.</h3>
      <p>Choose your amount with PayPal. Apple Pay, cards and Venmo may also be available at checkout, depending on your device and location.</p>
      <p className="support-small">Opens PayPal in a new tab. PayPal handles payment details and any verification.</p>
    </div><a className="button button-primary" href={paypalSupportURL} target="_blank" rel="noopener noreferrer">Leave a tip via PayPal <Icon name="external" size={17} /></a></div>
    <div className="support-crypto-heading"><h3>Prefer crypto?</h3><p>Send directly from your own wallet. These transfers are separate from PayPal. No wallet connection is requested by this site.</p></div>
    <div className="support-crypto-grid">{cryptoSupport.map(destination => <CryptoCard key={destination.symbol} destination={destination} />)}</div>
    <p className="support-safety">Use only the named coin and mainnet. Verify the full receiving address in your wallet before sending. Crypto transfers cannot be reversed by Hash Fleet. Never share a seed phrase or private key.</p>
  </section>
}
