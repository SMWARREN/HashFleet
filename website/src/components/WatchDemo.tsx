import { useRef, useState } from 'react'
import type { ReactNode } from 'react'
import Icon from './Icon'
import { watchCaptureFor, watchScreens } from '../lib/watchScreens'
import type { WatchScreenId } from '../lib/watchScreens'
import './watch.css'

function WatchFrame({ children }: { children: ReactNode }) {
  return <span className="watch-device"><span className="watch-band watch-band--top" aria-hidden="true" /><span className="watch-case">{children}</span><span className="watch-band watch-band--bottom" aria-hidden="true" /></span>
}

export function WatchPreview() {
  const capture = watchCaptureFor('watch-fleet')
  return <WatchFrame><img src={capture.src} width={capture.width} height={capture.height} alt="Actual Apple Watch app in demo mode, with fictional fleet readings" decoding="async" /></WatchFrame>
}

export default function WatchDemo() {
  const [screenId, setScreenId] = useState<WatchScreenId>('watch-fleet')
  const [history, setHistory] = useState<WatchScreenId[]>([])
  const [failed, setFailed] = useState(false)
  const heading = useRef<HTMLHeadingElement>(null)
  const current = watchScreens.findIndex(item => item.id === screenId)
  const screen = watchScreens[current]
  const capture = watchCaptureFor(screen.id)

  function navigate(next: WatchScreenId, focusHeading = false) {
    if (next === screenId) return
    setHistory(previous => [...previous, screenId])
    setScreenId(next)
    setFailed(false)
    if (focusHeading) requestAnimationFrame(() => heading.current?.focus({ preventScroll: true }))
  }
  function back() {
    const previous = history.at(-1)
    if (!previous) return
    setHistory(items => items.slice(0, -1))
    setScreenId(previous)
    setFailed(false)
  }
  function reset() {
    setHistory([])
    setScreenId('watch-fleet')
    setFailed(false)
  }

  return <section className="watch-stage" aria-label="Apple Watch native screen walkthrough" data-watch-tour>
    <div className="watch-stage-copy">
      <span className="platform-number">03 / APPLE WATCH</span>
      <h3>A smaller screen.<br /><span>Still your fleet.</span></h3>
      <p>A quick look at your fleet. A closer look at a miner. Native Watch screens, with the details that matter.</p>
      <div className="watch-product-facts"><span><Icon name="watch" size={16} /> Native watchOS app</span><span><Icon name="wifi" size={16} /> Local-network setup</span><span><Icon name="shield" size={16} /> Timestamped readings</span></div>
      <ol className="watch-tour-steps" aria-label="Choose a captured Watch screen">{watchScreens.map((item, index) => <li key={item.id}><button onClick={() => navigate(item.id)} aria-current={screen.id === item.id ? 'step' : undefined} data-watch-step={item.id}><span aria-hidden="true">0{index + 1}</span><span>{item.label}</span><Icon name="arrow" size={16} /></button></li>)}</ol>
      <p className="watch-browser-note"><Icon name="info" size={16} /> Five real captures. Tour buttons change the image, not a device. No network scan, miner connection or settings change happens here.</p>
    </div>
    <div className="watch-tour-viewer">
      <div className="watch-capture-label"><span><span className="watch-sample-dot" /> NATIVE WATCH CAPTURES</span><small>NOV 4, 2026 · SAMPLE DATA</small></div>
      <div className="watch-display-stage"><WatchFrame>{failed ? <span className="watch-load-error" role="alert">This Watch capture could not be loaded.<button onClick={() => setFailed(false)}>Reload capture</button></span> : <><img key={capture.id} src={capture.src} width={capture.width} height={capture.height} alt={`Actual native Apple Watch app: ${screen.label}. Sample data.`} decoding="async" onError={() => setFailed(true)} data-watch-capture={capture.id} />{screen.target && <button className="watch-hotspot" aria-label={`Watch walkthrough: ${screen.target.label}`} data-watch-target={screen.target.id} onClick={() => navigate(screen.target!.id, true)} style={{ left: `${screen.target.x}%`, top: `${screen.target.y}%`, width: `${screen.target.width}%`, height: `${screen.target.height}%` }}><span className="capture-sr-only">{screen.target.label}</span></button>}</>}</WatchFrame></div>
      <div className="watch-screen-status" role="status" aria-live="polite" aria-atomic="true"><span className="watch-screen-count">{current + 1} / {watchScreens.length}</span><h4 ref={heading} tabIndex={-1}>{screen.label}</h4><p>{screen.description}</p></div>
      <div className="watch-tour-controls"><button onClick={back} disabled={!history.length}><Icon name="chevron" size={15} className="watch-back-icon" /> Back</button><button onClick={reset}>Reset tour</button><button onClick={() => navigate(watchScreens[current + 1].id)} disabled={current === watchScreens.length - 1}>Next screen <Icon name="chevron" size={15} /></button></div>
      <details className="native-transcript"><summary>Read this Watch screen’s description</summary><p>{screen.transcript}</p></details>
      <p className="watch-viewer-fineprint">Original native pixels, not a live app stream. Captured times and readings do not update. watchOS 26.5+.</p>
    </div>
  </section>
}
