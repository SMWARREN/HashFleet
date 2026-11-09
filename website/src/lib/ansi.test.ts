import { createElement } from 'react'
import { renderToStaticMarkup } from 'react-dom/server'
import { describe, expect, it } from 'vitest'
import AnsiOutput from '../components/AnsiOutput'
import { ansiRuns, plainAnsi } from './ansi'
import { runCommand } from './terminal'
import dashboard from './cli-dashboard-captures.json'

describe('current CLI preview', () => {
  it('preserves transparent half-block pixels and resets styles between runs', () => {
    expect(ansiRuns('\x1b[38;2;245;172;38;49m▀\x1b[0m ')).toEqual([
      { text: '▀', color: 'rgb(245, 172, 38)', backgroundColor: undefined }, { text: ' ' },
    ])
    expect(ansiRuns('\x1b[48;2;10;20;30m▀\x1b[49m▄')[1].backgroundColor).toBeUndefined()
  })
  it('renders text safely, discards cursor controls, and ignores invalid colors', () => {
    const text = '\x1b[2J<img src=x onerror=alert(1)>\x1b[38;2;999;1;1mtext'
    const markup = renderToStaticMarkup(createElement(AnsiOutput, { value: text }))
    expect(markup).toContain('&lt;img')
    expect(markup).not.toContain('<img')
    expect(markup).not.toContain('rgb(999')
    expect(plainAnsi(text)).toBe('<img src=x onerror=alert(1)>text')
  })
  it.each(['hashfleet', 'hashfleet watch', 'hashfleet watch --demo'])('opens interactive navigation for %s', command => {
    expect(runCommand(command).view).toBe('dashboard')
  })
  it('supports native settings previews and the actual transparent logo', () => {
    expect(runCommand('hashfleet settings --demo').view).toBe('settings')
    expect(runCommand('hashfleet logo').ansi).toContain('▀')
    expect(runCommand('hashfleet logo').output).not.toContain('\x1b')
    expect(runCommand('hashfleet settings 192.168.1.5').kind).toBe('error')
  })
  it('colors filtered status without showing unselected miners', () => {
    const result = runCommand('hashfleet status gamma-demo.invalid')
    expect(plainAnsi(result.ansi!)).toContain('1/1 online')
    expect(plainAnsi(result.ansi!)).not.toContain('office-demo.invalid')
    expect(result.ansi).toContain('87;190;133')
  })
  it('has real captures for every miner, sort, pause, detail and settings section', () => {
    const frames = Object.fromEntries(Object.entries(dashboard.frames).map(([key, rows]) => [key, rows.map(index => dashboard.lines[index]).join('\n')]))
    for (let miner = 0; miner < 4; miner++) {
      for (const sort of ['name', 'hashrate', 'temperature']) for (const paused of [0, 1]) {
        const frame = plainAnsi(frames[`fleet:${sort}:${paused}:${miner}`])
        expect(frame).toContain(`› ${dashboard.miners[miner]}`)
        expect(frame).toContain(`sort: ${sort}`)
        if (paused) expect(frame).toContain('PAUSED')
      }
      for (let section = 1; section <= 4; section++) expect(plainAnsi(frames[`details:${miner}:${section}`])).toContain(`DETAILS / ${dashboard.miners[miner]}`)
      for (let category = 1; category <= 5; category++) expect(plainAnsi(frames[`settings:${miner}:${category}`])).toContain('DEMO · preview only')
    }
  })
})
