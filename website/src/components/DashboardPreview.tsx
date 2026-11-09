import { useEffect, useRef, useState } from 'react'
import captures from '../lib/cli-dashboard-captures.json'
import AnsiOutput from './AnsiOutput'

const DETAILS = ['Overview', 'Mining', 'Hardware', 'Pool']
const SETTINGS = ['General', 'Cooling', 'Tuning', 'Display', 'Pools']
const ORDERS = { name: [0, 1, 2, 3], hashrate: [2, 0, 1, 3], temperature: [0, 1, 2, 3] }
const SORTS = ['name', 'hashrate', 'temperature'] as const
type Screen = 'fleet' | 'details' | 'settings' | 'logo'

export default function DashboardPreview({ settings = false, onExit }: { settings?: boolean, onExit: () => void }) {
  const [screen, setScreen] = useState<Screen>(settings ? 'settings' : 'fleet')
  const [miner, setMiner] = useState(0)
  const [section, setSection] = useState(1)
  const [category, setCategory] = useState(1)
  const [paused, setPaused] = useState(false)
  const [sort, setSort] = useState<typeof SORTS[number]>('name')
  const [announcement, setAnnouncement] = useState('')
  const viewport = useRef<HTMLDivElement>(null)
  useEffect(() => {
    const element = viewport.current
    element?.focus({ preventScroll: true })
    const entry = element?.closest<HTMLElement>('.terminal-demo__entry')
    const output = element?.closest<HTMLElement>('.terminal-demo__output')
    if (entry && output) output.scrollTop = entry.offsetTop
  }, [])
  useEffect(() => { if (viewport.current) viewport.current.scrollTop = 0 }, [screen, miner, section, category])
  const key = screen === 'fleet' ? `fleet:${sort}:${Number(paused)}:${miner}`
    : screen === 'details' ? `details:${miner}:${section}`
    : screen === 'settings' ? `settings:${miner}:${category}` : 'logo'
  const frame = (captures.frames as Record<string, number[]>)[key].map(index => captures.lines[index]).join('\n')
  const tabs = screen === 'settings' ? SETTINGS : DETAILS
  const selectedTab = screen === 'settings' ? category : section

  function move(direction: number) {
    const order = ORDERS[sort]
    setMiner(order[Math.max(0, Math.min(3, order.indexOf(miner) + direction))])
  }
  function changeTab(value: number) {
    if (screen === 'settings') setCategory(value)
    else { setScreen('details'); setSection(value) }
  }
  function cycleSort() { setSort(SORTS[(SORTS.indexOf(sort) + 1) % SORTS.length]) }
  function handleKey(event: React.KeyboardEvent<HTMLDivElement>) {
    if (event.target !== event.currentTarget || event.altKey || event.metaKey) return
    const key = event.key.toLowerCase()
    if (key === 'tab') return // Keep normal browser focus navigation available.
    if (key === 'q' || (event.ctrlKey && key === 'c')) onExit()
    else if (key === 'escape' || key === 'b') setScreen('fleet')
    else if (key === 'l') setScreen(screen === 'logo' ? 'fleet' : 'logo')
    else if (key === 'd' || key === 'enter') {
      if (screen === 'settings') setAnnouncement('Native demo mode is preview only. Use the installed CLI to edit and review changes.')
      else setScreen(screen === 'details' ? 'fleet' : 'details')
    } else if (key === 'e') setScreen('settings')
    else if (/^[1-5]$/.test(key) && Number(key) <= (screen === 'settings' ? 5 : 4)) changeTab(Number(key))
    else if (key === 'arrowleft' || key === 'arrowright') {
      const direction = key === 'arrowleft' ? -1 : 1
      if (screen === 'settings') setCategory((category - 1 + direction + 5) % 5 + 1)
      else move(direction)
    } else if (key === '[' || key === ']') move(key === '[' ? -1 : 1)
    else if (['j', 'k', 'arrowup', 'arrowdown'].includes(key)) {
      const direction = key === 'j' || key === 'arrowdown' ? 1 : -1
      if (screen === 'fleet') move(direction)
      else viewport.current?.scrollBy({ top: direction * 40 })
    } else if (key === ' ' && screen === 'fleet') setPaused(!paused)
    else if (key === 's' && screen === 'fleet') cycleSort()
    else if (key === 'r') setAnnouncement('Sample snapshot reloaded. These are captured demo readings, not a live fleet.')
    else return
    event.preventDefault()
  }

  return <div className="cli-dashboard">
    <div className="cli-dashboard__controls" aria-label="Interactive CLI controls">
      <button type="button" aria-pressed={screen === 'fleet'} onClick={() => setScreen('fleet')}>Fleet</button>
      <label>Miner <select aria-label="Selected demo miner" value={miner} onChange={event => setMiner(Number(event.target.value))}>
        {captures.miners.map((name, index) => <option value={index} key={name}>{name}</option>)}
      </select></label>
      <button type="button" aria-pressed={screen === 'details'} onClick={() => setScreen('details')}>Details <kbd>d</kbd></button>
      <button type="button" aria-pressed={screen === 'settings'} onClick={() => setScreen('settings')}>Settings <kbd>e</kbd></button>
      <button type="button" aria-pressed={screen === 'logo'} onClick={() => setScreen(screen === 'logo' ? 'fleet' : 'logo')}>Logo <kbd>l</kbd></button>
      {screen === 'fleet' && <>
        <button type="button" onClick={() => setPaused(!paused)}>{paused ? 'Resume' : 'Pause'} <kbd>space</kbd></button>
        <button type="button" onClick={cycleSort}>Sort: {sort} <kbd>s</kbd></button>
      </>}
      <button type="button" onClick={onExit}>Quit <kbd>q</kbd></button>
    </div>
    {(screen === 'details' || screen === 'settings') && <div className="cli-dashboard__controls" aria-label={screen === 'settings' ? 'Settings sections' : 'Miner detail sections'}>
      {tabs.map((tab, index) => <button type="button" key={tab} aria-pressed={selectedTab === index + 1} onClick={() => changeTab(index + 1)}><kbd>{index + 1}</kbd> {tab}</button>)}
    </div>}
    <div ref={viewport} className="cli-dashboard__viewport" tabIndex={0} role="region" aria-label={`Interactive CLI ${screen}`} onKeyDown={handleKey}>
      <pre className="terminal-demo__result cli-dashboard__screen"><AnsiOutput value={frame} /></pre>
    </div>
    <p className="cli-dashboard__caption">Actual CLI demo screens · click the terminal to use its keys · sample readings stay local.
      {screen === 'settings' && ' Settings are preview only, just like native --demo.'}</p>
    <span className="terminal-demo__sr-only" role="status">{announcement || `${captures.miners[miner]} · ${screen}${screen === 'settings' || screen === 'details' ? ` · ${tabs[selectedTab - 1]}` : ''}`}</span>
  </div>
}
