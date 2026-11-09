import { useEffect, useRef, useState } from 'react'
import type { KeyboardEvent } from 'react'
import { IPhoneDemo, MacDemo, NativePreview, StatusDot } from './components/AppDemos'
import WatchDemo, { WatchPreview } from './components/WatchDemo'
import HashChart from './components/HashChart'
import Icon from './components/Icon'
import type { IconName } from './components/Icon'
import TerminalDemo from './components/TerminalDemo'
import SupportSection from './components/SupportSection'
import { privacyFragment, resolveSiteDialog } from './lib/routes'
import cliCaptures from './lib/cli-captures.json'
import AnsiOutput from './components/AnsiOutput'
import { demoMiners, summarizeFleet } from './lib/demo'

type Platform = 'mac' | 'iphone' | 'watch' | 'terminal'
type DialogName = 'download' | 'privacy' | null
const platforms: { id: Platform, label: string, icon: IconName, caption: string }[] = [
  { id: 'mac', label: 'Mac app', icon: 'mac', caption: 'A proper workspace for your entire fleet.' },
  { id: 'iphone', label: 'iPhone app', icon: 'phone', caption: 'Your miners, just a glance away.' },
  { id: 'watch', label: 'Apple Watch', icon: 'watch', caption: 'A native, timestamped look at your fleet, right on your wrist.' },
  { id: 'terminal', label: 'Terminal', icon: 'terminal', caption: 'Straight to the signal. No clicks required.' },
]

function safeReleaseUrl(value: unknown): string | undefined {
  if (typeof value !== 'string' || value.trim() === '') return undefined
  try {
    const url = new URL(value)
    return url.protocol === 'https:' && !url.username && !url.password ? url.href : undefined
  } catch { return undefined }
}
const macUrl = safeReleaseUrl(import.meta.env.VITE_MAC_DOWNLOAD_URL)
const iosUrl = safeReleaseUrl(import.meta.env.VITE_IOS_DOWNLOAD_URL)
const cliUrl = safeReleaseUrl(import.meta.env.VITE_CLI_DOWNLOAD_URL)
const sourceUrl = safeReleaseUrl(import.meta.env.VITE_SOURCE_URL)
const previewTotals = summarizeFleet(demoMiners)
function Brand() {
  return <a className="brand" href="#top" aria-label="Hash Fleet home"><img src="/images/brand.png" alt="" width="42" height="42" /><span>Hash<span className="brand-light">Fleet</span><i className="brand-period">.</i></span></a>
}

function NativeIdentityMark() {
  return <div className="native-identity-mark" data-site-app-mark aria-label="Hash Fleet local-first native app">
    <img src="/images/brand.png" alt="" width="30" height="30" />
    <span><strong>Hash Fleet</strong><small><span className="native-identity-dot" />LOCAL-FIRST</small></span>
  </div>
}

function Dialog({ name, onClose }: Readonly<{ name: Exclude<DialogName, null>, onClose: () => void }>) {
  const ref = useRef<HTMLDialogElement>(null)
  useEffect(() => { if (ref.current && !ref.current.open) ref.current.showModal() }, [])
  function close() {
    if (ref.current?.open) ref.current.close()
    else onClose()
  }
  function containTabFocus(event: KeyboardEvent<HTMLDialogElement>) {
    if (event.key !== 'Tab') return
    const controls = [...event.currentTarget.querySelectorAll<HTMLElement>('button, a[href], input, select, textarea, [tabindex]')]
      .filter(control => control.tabIndex >= 0 && !control.matches(':disabled') && control.getClientRects().length > 0)
    const first = controls[0]
    const last = controls.at(-1)
    if (!first || (event.shiftKey ? document.activeElement === first : document.activeElement === last)) {
      event.preventDefault()
      const next = event.shiftKey ? last : first
      next?.focus()
    }
  }
  return <dialog ref={ref} className="site-dialog" onClose={onClose} onKeyDown={containTabFocus} onClick={event => { if (event.target === event.currentTarget) close() }} aria-labelledby="dialog-title">
    <div className="dialog-content"><button className="dialog-close icon-button" onClick={close} aria-label="Close dialog" autoFocus><Icon name="close" /></button>
      <img className="dialog-brand" src="/images/brand.png" alt="" width="64" height="64" />
      {name === 'download' ? <>
        <span className="eyebrow">YOUR HASH. YOUR HARDWARE.</span><h2 id="dialog-title">Make it your fleet.</h2><p>Choose the native Mac app, the standalone terminal CLI, or both. Each installs independently. You can also explore the screen walkthroughs and browser CLI demo before downloading.</p>
        <div className="release-card"><Icon name="mac" size={26} /><div><strong>Hash Fleet for Mac</strong><span>Apple Silicon · macOS 14+ · native app only</span></div>{macUrl ? <a className="button button-small" href={macUrl} target="_blank" rel="noopener noreferrer">Get Mac build <Icon name="external" size={15} /></a> : <span className="release-status">Preview above · public build soon</span>}</div>
        <div className="release-card"><Icon name="phone" size={26} /><div><strong>Hash Fleet for iPhone & iPad</strong><span>iOS 17+ · native SwiftUI app</span></div>{iosUrl ? <a className="button button-small" href={iosUrl} target="_blank" rel="noopener noreferrer">Get iOS build <Icon name="external" size={15} /></a> : <span className="release-status">Coming soon</span>}</div>
        <div className="release-card"><Icon name="watch" size={26} /><div><strong>Hash Fleet for Apple Watch</strong><span>watchOS 26.5+ · native Watch app</span></div><span className="release-status">Included with the iOS app</span></div>
        <div className="release-card"><Icon name="terminal" size={26} /><div><strong>Hash Fleet CLI</strong><span>Apple Silicon · macOS 14+ · terminal only</span></div>{cliUrl ? <a className="button button-small" href={cliUrl} target="_blank" rel="noopener noreferrer">Get terminal CLI <Icon name="external" size={15} /></a> : <span className="release-status">Public CLI download coming soon</span>}</div>
        {macUrl && cliUrl ? <div className="release-note"><strong>Prefer Homebrew? Install either or both:</strong><p><code>brew install --cask hashfleet</code></p><p><code>brew install hashfleet-cli</code></p><a href="https://github.com/SMWARREN/HashFleet/blob/main/docs/HOMEBREW.md" target="_blank" rel="noopener noreferrer">Homebrew setup and installation details</a></div> : null}
        {sourceUrl ? <a className="source-link" href={sourceUrl} target="_blank" rel="noopener noreferrer"><Icon name="code" size={18} /> Explore the source <Icon name="external" size={14} /></a> : <p className="release-note"><Icon name="code" size={18} /> Open-source project · public repository link coming soon.</p>}
        <p className="dialog-fineprint">No email signup, no waitlist tracking, no made-up download links.</p>
      </> : <>
        <span className="eyebrow">PRIVACY, NOT PROMISES</span><h2 id="dialog-title">Your fleet stays yours.</h2>
        <div className="privacy-copy"><h3>This website</h3><p>The native-screen walkthroughs and terminal demo use fictional readings and run in your browser. Native images are captured screens with tour navigation, not a native app stream. They do not discover, connect to, or change miners. There are no analytics scripts, advertising, cookies, account forms, or telemetry uploads in this website. Your demo choices are not persisted.</p><p>The hosting provider may process standard request logs such as IP addresses to deliver the website. Visiting external release or repository links follows the destination's privacy policy.</p><h3>The native apps</h3><p>Hash Fleet stores fleet configuration locally and connects directly to the miners you add. Optional public chain and pool services can be disabled. Logs and raw miner responses may contain sensitive information, so review them before sharing.</p><p>Optional scheduled push checks are off by default and controlled inside the iPhone and Mac apps, not this website. When configured and enabled, the scheduling service receives a push token, opaque miner IDs, switches and intervals. Miner names, LAN addresses and readings stay on your device. A bundled notification extension attempts a short local check after an Apple push. Delivery and local-network access are best effort, not continuous monitoring or guaranteed hourly updates. No separate companion app is required.</p><h3>Your connection</h3><p>Miner HTTP APIs are generally plaintext local-network endpoints. Use a trusted VPN for remote access. Never port-forward a miner to the public internet.</p><h3>Contact and privacy requests</h3><p>For app support, privacy questions or data-removal requests, contact Sean Warren at <a href="mailto:support@hashfleet.app">support@hashfleet.app</a>. Email contains the information you choose to send. Do not include passwords, private keys or unredacted miner logs.</p><p><a href="/support/">Technical support and contact details</a></p></div>
      </>}
    </div>
  </dialog>
}

function HeroScene({ explore }: Readonly<{ explore: (platform: Platform) => void }>) {
  return <div className="hero-scene" aria-label="Hash Fleet Mac, iPhone, Apple Watch and terminal product previews">
    <div className="scene-orbit orbit-one" /><div className="scene-orbit orbit-two" /><span className="scene-cross cross-one">+</span><span className="scene-cross cross-two">+</span>
    <div className="hero-mac"><MacDemo compact /></div>
    <button className="hero-phone" onClick={() => explore('iphone')} aria-label="Explore the captured iPhone screens">
      <div className="hero-phone-screen"><NativePreview platform="iphone" /></div>
    </button>
    <button className="hero-watch" onClick={() => explore('watch')} aria-label="Explore the captured Apple Watch screens"><WatchPreview /></button>
    <button className="hero-terminal" onClick={() => explore('terminal')} aria-label="Open the browser CLI demo"><span className="mini-terminal-chrome"><span className="traffic-lights" aria-hidden="true"><i /><i /><i /></span><span>hashfleet · zsh</span><span>SAMPLE</span></span><span className="mini-command"><span>❯</span> hashfleet status</span><span className="mini-terminal-output"><span className="mini-terminal-brand"><AnsiOutput value={cliCaptures.tty.table.header.split('\n').slice(0, 12).join('\n')} /></span></span><span className="mini-command mini-prompt"><span>❯</span><span className="terminal-cursor" /></span></button>
    <div className="scene-caption"><span className="caption-line" />ONE FLEET. EVERY SCREEN.</div>
  </div>
}

const faqs: ReadonlyArray<{ question: string, answer: string, link?: { href: string, label: string } }> = [
  { question: 'Which miners can I use with Hash Fleet?', answer: 'Hash Fleet’s current native build focuses on ESP-Miner / AxeOS ASICs, including Bitaxe and Naja miners. Readings and supported operations vary by firmware, hardware, and build. Missing or stale readings stay labeled, and monitoring support does not guarantee every device operation.' },
  { question: 'Is this a real app, or just a website?', answer: 'The product is a native SwiftUI app for iPhone, iPad, and Mac, plus a Mac command-line tool with a live dashboard and reviewed miner settings. The Mac, iPhone and Apple Watch walkthroughs use lossless captures from the actual apps, with clickable navigation between captured screens. They are not native apps running in your browser. The terminal uses output captured from the real CLI against synthetic local fixtures. All displayed miner readings are fictional sample data.' },
  { question: 'Does it need a cloud account or subscription?', answer: 'No Hash Fleet account, subscriptions, analytics, or hosted telemetry backend are required by the native app. Your configured fleet lives locally. Optional public chain and pool statistics can be disabled for local-only operation.' },
  { question: 'Can I check my miners away from home?', answer: 'Yes, through a private VPN such as Tailscale. Never port-forward a miner API to the internet. Hash Fleet has no cloud relay. We validated a setup where a small ESP32-S3 board at home joins Tailscale and forwards only your miners’ addresses, so the app keeps using their normal home addresses over cellular. The open-source firmware and step-by-step setup are on GitHub.', link: { href: 'https://github.com/SMWARREN/HashFleet/blob/main/docs/REMOTE-ACCESS-TAILSCALE.md', label: 'Remote access setup guide' } },
  { question: 'Does the iPhone app monitor continuously in the background?', answer: 'No. iOS may delay or skip best-effort background checks. Widgets and Live Activities show timestamped snapshots, not uninterrupted live monitoring while the app is suspended.' },
  { question: 'What can I do on Apple Watch?', answer: 'The native Watch app shows a timestamped fleet summary and individual miner details. It supports local-network discovery and manual setup on the Watch. You can optionally import miner names and local addresses from the iPhone app, with confirmation on the Watch. Readings come directly from miners while the Watch app is active, not from the iPhone or continuous background monitoring. This website lets you explore five genuine Watch captures with fictional readings. It cannot scan your network or connect to your Watch. Requires watchOS 26.5 or later.' },
  { question: 'Which native features are not in this browser preview?', answer: 'The native apps include device connections, confirmed hardware operations, local notifications, best-effort background refresh, and platform integrations such as widgets, Live Activities, and Shortcuts. The website only navigates captured native screens and simulates allowlisted CLI commands. Native switches, add-miner, refresh, export, and hardware controls visible in images are not running here. No miner discovery, notifications, file exports, or hardware requests occur.' },
  { question: 'Will trying this demo change my miners?', answer: 'Never. This website has no connection to your mining hardware. The real app and CLI require review and confirmation before changing device settings. The CLI walkthrough here uses its read-only demo mode. Firmware upgrades, pool changes, and manual tuning still require hardware-specific care and can interrupt mining or damage a device.' },
]

export default function App({ initialPlatform = 'mac', startAtDemo = false }: Readonly<{ initialPlatform?: Platform, startAtDemo?: boolean }>) {
  const [platform, setPlatform] = useState<Platform>(initialPlatform)
  const [menuOpen, setMenuOpen] = useState(false)
  const [dialog, setDialog] = useState<DialogName>(() => typeof window === 'undefined' ? null : resolveSiteDialog(window.location.hash))
  const [theme, setTheme] = useState<'dark' | 'light'>('dark')
  const demoRef = useRef<HTMLElement>(null)
  const tabRefs = useRef<(HTMLButtonElement | null)[]>([])
  const dialogInvoker = useRef<HTMLElement | null>(null)

  useEffect(() => { document.documentElement.dataset.theme = theme }, [theme])
  useEffect(() => {
    function syncPrivacyFragment() {
      const linkedDialog = resolveSiteDialog(window.location.hash)
      if (linkedDialog) {
        dialogInvoker.current = document.activeElement instanceof HTMLElement ? document.activeElement : null
        setDialog(linkedDialog)
      } else {
        setDialog(current => current === 'privacy' ? null : current)
      }
    }
    window.addEventListener('hashchange', syncPrivacyFragment)
    return () => window.removeEventListener('hashchange', syncPrivacyFragment)
  }, [])
  useEffect(() => {
    if (!startAtDemo) return
    const frame = requestAnimationFrame(() => demoRef.current?.scrollIntoView({ behavior: 'instant', block: 'start' }))
    return () => cancelAnimationFrame(frame)
  }, [startAtDemo])
  function openDialog(name: Exclude<DialogName, null>) {
    dialogInvoker.current = document.activeElement instanceof HTMLElement ? document.activeElement : null
    if (name === 'privacy' && window.location.hash !== privacyFragment) {
      window.history.pushState(null, '', privacyFragment)
    }
    setDialog(name)
  }
  function closeDialog() {
    const invoker = dialogInvoker.current
    if (resolveSiteDialog(window.location.hash)) {
      window.history.replaceState(null, '', window.location.pathname + window.location.search)
    }
    setDialog(null)
    requestAnimationFrame(() => {
      if (invoker?.isConnected && document.activeElement === document.body) invoker.focus()
    })
  }
  function explore(next: Platform = 'mac') {
    setPlatform(next)
    tabRefs.current[platforms.findIndex(item => item.id === next)]?.focus({ preventScroll: true })
    demoRef.current?.scrollIntoView({ behavior: window.matchMedia('(prefers-reduced-motion: reduce)').matches ? 'instant' : 'smooth', block: 'start' })
  }
  function tabKeyboard(event: KeyboardEvent<HTMLButtonElement>, index: number) {
    let next: number
    if (event.key === 'ArrowRight') next = (index + 1) % platforms.length
    else if (event.key === 'ArrowLeft') next = (index + platforms.length - 1) % platforms.length
    else if (event.key === 'Home') next = 0
    else if (event.key === 'End') next = platforms.length - 1
    else return
    event.preventDefault()
    setPlatform(platforms[next].id)
    tabRefs.current[next]?.focus()
  }

  return <>
    <a className="skip-link" href="#main">Skip to content</a>
    <header className="site-header" id="top"><div className="container header-inner"><Brand /><nav className={menuOpen ? 'main-nav is-open' : 'main-nav'} aria-label="Main navigation"><a href="#features" onClick={() => setMenuOpen(false)}>Features</a><a href="#demo" onClick={() => setMenuOpen(false)}>Try the demo <span className="nav-live-dot" /></a><a href="#faq" onClick={() => setMenuOpen(false)}>FAQ</a><a href="#support" onClick={() => setMenuOpen(false)}>Support</a></nav><div className="header-actions"><NativeIdentityMark /><button className="icon-button theme-toggle" aria-label={`Switch to ${theme === 'dark' ? 'light' : 'dark'} theme`} aria-pressed={theme === 'light'} onClick={() => setTheme(theme === 'dark' ? 'light' : 'dark')}><Icon name={theme === 'dark' ? 'sun' : 'moon'} size={18} /></button><button className="button button-nav" onClick={() => openDialog('download')}>Get Hash Fleet <Icon name="arrow-up" size={15} /></button><button className="icon-button mobile-menu" onClick={() => setMenuOpen(!menuOpen)} aria-label={menuOpen ? 'Close navigation' : 'Open navigation'} aria-expanded={menuOpen}><Icon name={menuOpen ? 'close' : 'menu'} /></button></div></div></header>
    <main id="main">
      <section className="hero container"><div className="hero-copy"><span className="hero-kicker"><span className="kicker-dot" />THE NATIVE MINING COMPANION<span className="dev-tag">IN DEVELOPMENT</span></span><h1>Your hash.<br />{' '}Your hardware.<br />{' '}<span>Your fleet.</span></h1><p className="hero-description">A little less checking.<br />{' '}A lot more knowing.</p><p className="hero-description-secondary">Your miners, together in one beautiful workspace.<br className="desktop-break" /> On your Mac. On your iPhone. On your wrist. In your terminal.</p><div className="hero-actions"><button className="button button-primary" onClick={() => explore('mac')}>Take it for a spin <Icon name="arrow" size={19} /></button><button className="button button-text" onClick={() => openDialog('download')}>Get the app <Icon name="download" size={17} /></button></div><div className="hero-assurances"><span><Icon name="check" size={14} /> Native SwiftUI</span><span><Icon name="check" size={14} /> Local-first</span><span><Icon name="check" size={14} /> Open source</span></div></div><HeroScene explore={explore} /></section>
      <section className="compatibility-strip container" aria-label="Supported ecosystem"><span>BUILT FOR THE WAY YOU MINE</span><div><strong><Icon name="cpu" size={18} /> Bitaxe</strong><strong><Icon name="grid" size={18} /> Naja</strong><strong className="axeos-word">Axe<span>OS</span></strong><strong><Icon name="code" size={18} /> ESP-Miner</strong></div><span className="strip-caption">Firmware capabilities vary.</span></section>
      <section className="features-section container" id="features"><div className="section-heading"><div><span className="eyebrow">LESS FRICTION. MORE SIGNAL.</span><h2>Small details.<br />{' '}<span>Whole-fleet clarity.</span></h2></div><p>From a single Bitaxe on your desk to a growing collection.<br />{' '}Keep the important things in view, not in twenty browser tabs.</p></div><div className="feature-grid"><article className="feature-card feature-card-large"><div className="feature-copy"><span className="feature-icon"><Icon name="chart" size={24} /></span><h3>Every miner.<br />{' '}One clear picture.</h3><p>Hashrate, temperatures, reported power, shares, and uptime. See the fleet, then go deep on any device.</p><button className="text-link" onClick={() => explore('mac')}>Explore the workspace <Icon name="arrow" size={17} /></button></div><div className="feature-visual"><div className="visual-label"><StatusDot />SAMPLE FLEET</div><strong>{previewTotals.sha256.toFixed(2)} <span>TH/s</span></strong><HashChart range="1h" mini /><div className="visual-footer"><span>{demoMiners.length} ASICs</span><span>{previewTotals.reportedPower.toFixed(0)} W reported</span></div></div></article><article className="feature-card"><span className="feature-icon"><Icon name="shield" size={24} /></span><h3>Your data stays<br />{' '}on your side.</h3><p>No Hash Fleet account. No telemetry backend. Direct connections to the miners you choose.</p><span className="feature-footnote"><Icon name="wifi" size={15} /> Local network. Your rules.</span></article><article className="feature-card"><span className="feature-icon"><Icon name="terminal" size={24} /></span><h3>For the command-line<br />{' '}kind of person.</h3><p>One read-only command for fleet status. A clean table with best shares, detailed diagnostics, or structured JSON for your scripts.</p><button className="feature-code" onClick={() => explore('terminal')}><span>❯</span> hashfleet status <Icon name="arrow" size={15} /></button></article></div></section>
      <section className="demo-section" id="demo" ref={demoRef}>
        <div className="container">
          <div className="demo-section-heading"><span className="eyebrow">THE PRODUCT, NOT A LOOKALIKE.</span><h2>One fleet.<br className="mobile-break" /> Four ways in.</h2><p>Real native screens. Actual CLI output. Fictional miners.</p></div>
          <div className="platform-tabs" role="tablist" aria-label="Choose a product demo">
            {platforms.map((item, index) => <button ref={node => { tabRefs.current[index] = node }} id={`tab-${item.id}`} key={item.id} role="tab" aria-selected={platform === item.id} aria-controls={`panel-${item.id}`} tabIndex={platform === item.id ? 0 : -1} onKeyDown={event => tabKeyboard(event, index)} onClick={() => setPlatform(item.id)} className={platform === item.id ? 'is-active' : ''}><Icon name={item.icon} size={18} />{item.label}</button>)}
          </div>
          {platforms.map(item => <div key={item.id} id={`panel-${item.id}`} role="tabpanel" aria-labelledby={`tab-${item.id}`} hidden={platform !== item.id} className={`demo-panel demo-panel--${item.id}`}>
            {{ mac: <MacDemo />, iphone: <div className="iphone-stage"><div className="iphone-stage-copy"><span className="platform-number">02 / IPHONE</span><h3>A pocket-sized<br />{' '}<span>peace of mind.</span></h3><p>Follow the native gear menu.<br />{' '}Inspect the real cards and detail screens.</p><ul><li><Icon name="check" size={17} /> Native, glanceable fleet overview</li><li><Icon name="check" size={17} /> Clear readings, honest missing data</li><li><Icon name="check" size={17} /> Built for iPhone and iPad</li></ul><span className="stage-note"><Icon name="shield" size={16} /> Captured native screens with clickable tour navigation.</span></div><IPhoneDemo /></div>, watch: <WatchDemo />, terminal: <div className="terminal-stage"><div className="terminal-stage-header"><div><span className="platform-number">04 / TERMINAL</span><h3>No mouse. No mystery.</h3></div><p>Type <code>hashfleet watch --demo</code><br />{' '}to explore with keys or buttons.</p></div><TerminalDemo /></div> }[item.id]}
          </div>)}
          <div className="demo-caption"><span><Icon name="shield" size={15} /> SAFE TO EXPLORE</span><p>{platforms.find(item => item.id === platform)?.caption} All readings are simulated. No real miners are connected.</p><span className="demo-caption-hint">{{ mac: 'Click an outlined sidebar item or choose a captured screen.', iphone: 'Tap the outlined gear menu or choose a captured screen.', watch: 'Choose a Watch screen or follow an outlined navigation button.', terminal: 'Type a command and press Enter.' }[platform]}</span></div>
        </div>
      </section>
      <section className="principles-section container" id="principles"><div className="principles-art"><div className="art-halo" /><img src="/images/miner.png" alt="Hash Fleet's gold and graphite miner artwork" width="640" height="640" loading="lazy" /><span className="art-caption"><span className="caption-line" />MADE FOR THE HARDWARE YOU OWN</span></div><div className="principles-copy"><span className="eyebrow">NOT ANOTHER CLOUD DASHBOARD.</span><h2>Built for miners.<br />{' '}<span>Not for mining<br />{' '}your data.</span></h2><p>Your hardware is personal. The software you use to watch it should respect that.</p><div className="principle-row"><span>01</span><div><h3>Native where it matters.</h3><p>SwiftUI on Apple platforms. A focused CLI on your Mac. Each feels right where you use it.</p></div></div><div className="principle-row"><span>02</span><div><h3>Clear about what it knows.</h3><p>Missing sensors and stale snapshots stay visibly labeled in the real app. Captured timestamps and sample assumptions are not live fleet readings.</p></div></div><div className="principle-row"><span>03</span><div><h3>You stay in control.</h3><p>Read-only monitoring first. Explicit confirmation for changes. No surprise tuning or firmware updates.</p></div></div></div></section>
      <section className="faq-section container" id="faq"><div><span className="eyebrow">A FEW THINGS WORTH KNOWING</span><h2>Good questions.<br />{' '}<span>Straight answers.</span></h2></div><div className="faq-list">{faqs.map((faq, index) => <details key={faq.question}><summary><span className="faq-number">0{index + 1}</span><span>{faq.question}</span><Icon name="plus" size={18} /></summary><p>{faq.answer}{faq.link ? <>{' '}<a href={faq.link.href} target="_blank" rel="noopener noreferrer">{faq.link.label} <Icon name="external" size={13} /></a></> : null}</p></details>)}</div></section>
      <SupportSection />
      <section className="final-cta container"><span className="eyebrow">THE FLEET IS YOURS.</span><h2>Give it a home.</h2><p>Less tab juggling. More time for everything else.</p><button className="button button-primary" onClick={() => openDialog('download')}>Get Hash Fleet <Icon name="arrow-up" size={18} /></button><span className="cta-availability">Mac · iPhone & iPad · Terminal <span>{macUrl || cliUrl ? "Mac and terminal downloads available" : "Public builds coming soon"}</span></span></section>
    </main>
    <footer className="site-footer container"><div className="footer-main"><Brand /><span>Your hash. Your hardware.</span><nav aria-label="Footer navigation"><button onClick={() => openDialog('privacy')}>Privacy</button><a href="/support/">Help & contact</a><a href="#faq">Compatibility & safety</a><a href="#support">Support</a>{sourceUrl ? <a href={sourceUrl} target="_blank" rel="noopener noreferrer">Source <Icon name="external" size={13} /></a> : <button onClick={() => openDialog('download')}>Open source <Icon name="external" size={13} /></button>}</nav></div><div className="footer-bottom"><span>© 2026 Hash Fleet. Made for the independent miner.</span><span>Independent project. Not affiliated with Apple, Bitaxe, or the miners' manufacturers.</span><span className="footer-domain">HASHFLEET.APP <span className="kicker-dot" /></span></div></footer>
    {dialog && <Dialog name={dialog} onClose={closeDialog} />}
  </>
}
