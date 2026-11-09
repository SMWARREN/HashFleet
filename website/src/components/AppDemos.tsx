import { useId, useLayoutEffect, useRef, useState } from 'react'
import Icon from './Icon'
import { captureFor, screensFor } from '../lib/nativeScreens'
import type { NativePlatform } from '../lib/nativeScreens'

export function StatusDot() { return <span className="status-dot" aria-hidden="true" /> }

export function NativePreview({ platform }: Readonly<{ platform: NativePlatform }>) {
  const capture = captureFor(platform === 'mac' ? 'mac-overview' : 'ios-fleet')
  return <img className="native-preview" src={capture.src} alt={`Actual ${platform === 'mac' ? 'Mac' : 'iPhone'} app running in native demo mode`} width={capture.width} height={capture.height} />
}

type HistoryEntry = { id: string, left: number, top: number, target?: string }

function NativeWalkthrough({ platform }: Readonly<{ platform: NativePlatform }>) {
  const screens = screensFor(platform)
  const [screenId, setScreenId] = useState(screens[0].id)
  const [history, setHistory] = useState<HistoryEntry[]>([])
  const [showTargets, setShowTargets] = useState(true)
  const [enlarged, setEnlarged] = useState(false)
  const [failed, setFailed] = useState(false)
  const viewport = useRef<HTMLDivElement>(null)
  const heading = useRef<HTMLHeadingElement>(null)
  const restore = useRef<HistoryEntry | null>(null)
  const focusHeading = useRef(false)
  const id = useId()
  const screen = screens.find(item => item.id === screenId) ?? screens[0]
  const capture = captureFor(screen.id)
  const platformName = platform === 'mac' ? 'Mac' : 'iPhone'
  const enlargedWidth = platform === 'mac' ? 1440 : 402

  useLayoutEffect(() => {
    if (viewport.current) {
      viewport.current.scrollLeft = restore.current?.left ?? 0
      viewport.current.scrollTop = restore.current?.top ?? 0
    }
    const targetId = restore.current?.target
    const oldTrigger = targetId ? [...(viewport.current?.querySelectorAll<HTMLButtonElement>('[data-capture-target]') ?? [])].find(button => button.dataset.captureTarget === targetId) : undefined
    if (oldTrigger) oldTrigger.focus({ preventScroll: true })
    else if (focusHeading.current) heading.current?.focus({ preventScroll: true })
    restore.current = null
    focusHeading.current = false
  }, [screen.id])

  function navigate(next: string, fromHotspot = false) {
    if (next === screen.id || !screens.some(item => item.id === next)) return
    setHistory(previous => [...previous, { id: screen.id, left: viewport.current?.scrollLeft ?? 0, top: viewport.current?.scrollTop ?? 0, target: fromHotspot ? next : undefined }])
    setFailed(false)
    focusHeading.current = fromHotspot
    setScreenId(next)
  }

  function back() {
    const previous = history.at(-1)
    if (!previous) return
    restore.current = previous
    setHistory(items => items.slice(0, -1))
    setFailed(false)
    setScreenId(previous.id)
  }

  function reset() {
    setHistory([])
    setFailed(false)
    setScreenId(screens[0].id)
    if (viewport.current) viewport.current.scrollTo(0, 0)
  }

  return <section className={`native-walkthrough native-walkthrough--${platform}`} aria-label={`${platformName} native screen walkthrough`} data-native-platform={platform}>
    <div className="native-capture-label"><span><Icon name="check" size={15} /> ACTUAL NATIVE APP SCREENS</span><small>CAPTURED OCT 25, 2026 · SAMPLE DATA</small></div>
    <p className="native-disclosure">Explore captured screens from the real {platformName} app, not a recreated dashboard or a live app stream. Outlined areas navigate the walkthrough. Other controls are part of the image.</p>
    <div className="native-tour-toolbar">
      <label htmlFor={`${id}-screen`}>{platformName} screen<select id={`${id}-screen`} value={screen.id} onChange={event => navigate(event.target.value)}>{screens.map(item => <option key={item.id} value={item.id}>{item.label}</option>)}</select></label>
      <div className="native-tour-actions"><button onClick={back} disabled={!history.length} aria-label={`Previous ${platformName} capture`}><Icon name="arrow" size={14} /> Back</button><button onClick={reset}>Reset tour</button><button aria-pressed={enlarged} onClick={() => setEnlarged(value => !value)}>{enlarged ? 'Fit screen' : 'Enlarge screen'}</button><button aria-pressed={showTargets} onClick={() => setShowTargets(value => !value)}>Clickable areas</button></div>
    </div>
    <div className="native-screen-status" role="status"><h3 ref={heading} tabIndex={-1}>{screen.label}</h3><p>{screen.description}</p></div>
    <div ref={viewport} className={`native-viewport ${showTargets ? 'native-viewport--targets' : ''} ${enlarged ? 'native-viewport--enlarged' : ''}`} tabIndex={0} aria-label={`${platformName} capture viewport, scroll to inspect the screen`}>
      {failed ? <p className="native-load-error" role="alert">This native capture could not be loaded. Choose another screen or reload the page.</p> : <div className="native-canvas" style={{ width: enlarged ? enlargedWidth : '100%' }}>
        <img key={capture.src} className="native-capture" src={capture.src} width={capture.width} height={capture.height} alt={`Actual native ${platformName} app: ${screen.label}`} loading="lazy" decoding="async" onError={() => setFailed(true)} data-native-capture={capture.id} />
        {screen.targets.filter(item => item.target !== screen.id).map(item => <button key={`${item.target}-${item.label}`} className="native-hotspot" data-capture-target={item.target} aria-label={`${platformName} walkthrough: ${item.label}`} title={item.label} onClick={() => navigate(item.target, true)} style={{ left: `${item.x}%`, top: `${item.y}%`, width: `${item.width}%`, height: `${item.height}%` }}><span className="capture-sr-only">{item.label}</span></button>)}
      </div>}
    </div>
    <div className="native-tour-footer"><span><Icon name="shield" size={14} /> No device connections. No settings changes.</span><span>{screens.findIndex(item => item.id === screen.id) + 1} / {screens.length} captured screens</span></div>
    {platform === 'iphone' && <div className="native-tour-shortcuts" aria-label="iPhone capture shortcuts"><button onClick={() => navigate('ios-miners')}>See the miner cards <Icon name="arrow" size={14} /></button><button onClick={() => navigate('ios-fleet')}>Fleet overview</button></div>}
    <details className="native-transcript"><summary>Read this screen’s description</summary><p>{screen.transcript}</p></details>
  </section>
}

export function MacDemo({ compact = false }: Readonly<{ compact?: boolean }>) {
  return compact ? <NativePreview platform="mac" /> : <NativeWalkthrough platform="mac" />
}

export function IPhoneDemo() { return <NativeWalkthrough platform="iphone" /> }
