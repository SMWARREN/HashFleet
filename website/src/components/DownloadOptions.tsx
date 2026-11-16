import Icon from './Icon'
import { CHECKSUMS_URL, HOMEBREW_SETUP_URL, RELEASE_NOTES_URL } from '../lib/releases'
import type { ReleaseLinks } from '../lib/releases'
import './download-options.css'

export default function DownloadOptions({ links }: Readonly<{ links: ReleaseLinks }>) {
  return <div className="download-options">
    <header className="download-options__header">
      <img src="/images/brand.png" alt="" width="40" height="40" />
      <span className="eyebrow">FREE & OPEN SOURCE</span>
      <h2 id="dialog-title">Download Hash Fleet</h2>
      <p>Your fleet, on your terms. Choose your install.</p>
    </header>

    <section className="download-options__section" aria-labelledby="download-store-title">
      <h3 id="download-store-title">App Store</h3>
      <div className="download-options__rows">
        <div className="download-options__row download-options__row--primary" data-download="ios">
          <Icon name="phone" size={23} />
          <div className="download-options__label"><strong>iPhone & iPad</strong><span>iOS 17+ · iPadOS 17+</span></div>
          {links.ios ? <a className="download-options__action download-options__action--primary" href={links.ios} target="_blank" rel="noopener noreferrer">Download on the App Store <Icon name="external" size={15} /></a> : <span className="download-options__status">App Store link unavailable</span>}
        </div>
        <p className="download-options__watch"><Icon name="watch" size={16} /><span>Apple Watch included with the iOS app · watchOS 26.5+</span></p>
        <div className="download-options__row" data-download="mac-store">
          <Icon name="mac" size={23} />
          <div className="download-options__label"><strong>Mac App Store</strong><span>Native Mac app · not yet released</span></div>
          <span className="download-options__status">Awaiting approval</span>
        </div>
      </div>
    </section>

    <section className="download-options__section" aria-labelledby="download-mac-title">
      <div className="download-options__section-heading"><h3 id="download-mac-title">Native Mac</h3><span>Direct download · v1.0.0</span></div>
      <div className="download-options__row download-options__standalone" data-download="mac-direct">
        <Icon name="mac" size={23} />
        <div className="download-options__label"><strong>Apple Silicon</strong><span>macOS 14+ · native Mac app</span></div>
        {links.mac ? <a className="download-options__action" href={links.mac} target="_blank" rel="noopener noreferrer">Download .zip <Icon name="download" size={16} /></a> : <span className="download-options__status">Mac download unavailable</span>}
      </div>
      <p className="download-options__note"><Icon name="shield" size={15} />Developer ID signed and Apple-notarized.</p>
    </section>

    <section className="download-options__section download-options__section--terminal" aria-labelledby="download-cli-title">
      <div className="download-options__section-heading"><h3 id="download-cli-title">Terminal CLI</h3><span>Separate installation · v1.0.0</span></div>
      <div className="download-options__row download-options__standalone" data-download="cli">
        <Icon name="terminal" size={23} />
        <div className="download-options__label"><strong>hashfleet</strong><span>Apple Silicon · macOS 14+ · terminal only</span></div>
        {links.cli ? <a className="download-options__action" href={links.cli} target="_blank" rel="noopener noreferrer">Download .tar.gz <Icon name="download" size={16} /></a> : <span className="download-options__status">CLI download unavailable</span>}
      </div>
      <p className="download-options__note">Developer ID signed and Apple-notarized. Installs independently of the Mac app.</p>
      <div className="download-options__homebrew">
        <a href={HOMEBREW_SETUP_URL} target="_blank" rel="noopener noreferrer">Homebrew setup <Icon name="external" size={14} /></a>
        <span>Then <code>brew install hashfleet-cli</code></span>
      </div>
    </section>

    <nav className="download-options__footer" aria-label="Release resources">
      <a href={RELEASE_NOTES_URL} target="_blank" rel="noopener noreferrer">Release notes <Icon name="external" size={13} /></a>
      <a href={CHECKSUMS_URL} target="_blank" rel="noopener noreferrer">Checksums <Icon name="external" size={13} /></a>
      {links.source ? <a href={links.source} target="_blank" rel="noopener noreferrer">Source <Icon name="code" size={15} /></a> : <span>Source link unavailable</span>}
    </nav>
  </div>
}
