import { createElement } from 'react'
import { renderToStaticMarkup } from 'react-dom/server'
import { afterEach, describe, expect, it, vi } from 'vitest'
import TerminalDemo from '../components/TerminalDemo'
import { demoMiners } from './demo'
import captures from './cli-captures.json'
import { compareText } from './order'
import {
  createTerminalState,
  MAX_COMMAND_LENGTH,
  MAX_HISTORY,
  MAX_SCROLLBACK,
  navigateHistory,
  runCommand,
  SAMPLE_MINERS,
  SAMPLE_OBSERVED_AT,
  SUGGESTED_COMMANDS,
  submitCommand,
} from './terminal'

afterEach(() => vi.unstubAllGlobals())

describe('documented CLI sample commands', () => {
  it('starts with useful status output for all three native demo devices', () => {
    const state = createTerminalState()
    expect(state.entries).toHaveLength(1)
    expect(state.entries[0].command).toBe('hashfleet status')
    expect(state.entries[0].output).toContain('HashFleet status · 3/3 online')
    for (const miner of demoMiners) expect(state.entries[0].output).toContain(miner.host)
    expect(state.entries[0].output.match(/ONLINE/g)).toHaveLength(3)
  })

  it.each(SUGGESTED_COMMANDS)('runs the suggested command %s', (command) => {
    expect(runCommand(command).kind).toBe('success')
  })

  it.each(['hashfleet status', '  hashfleet   status  ', '\thashfleet\tstatus\t'])('accepts valid status input %j', (command) => {
    expect(runCommand(command).output).toBe(runCommand('hashfleet status').output)
  })

  it.each(['hashfleet --help', 'hashfleet -h', 'hashfleet status --help'])('returns native usage for %s', (command) => {
    const result = runCommand(command)
    expect(result.kind).toBe('success')
    expect(result.output).toContain('hashfleet status [--json | --details] [<miner-host> ...]')
    expect(result.output).toContain('--details adds mining, cooling, hardware and pool information')
    expect(result.output).not.toContain('Browser-only utilities')
  })

  it('labels help and clear as browser-only utilities', () => {
    const result = runCommand('help')
    expect(result.output).toContain('Browser-only utilities: help')
    expect(result.output).toContain('clear (clear this panel)')
    expect(result.output).toContain('No network requests')
  })

  it.each(['gamma-demo.invalid', 'office-demo.invalid', 'supra-demo.invalid'])('selects a single explicit ASIC host %s', (host) => {
    const result = runCommand(`hashfleet status ${host}`)
    expect(result.kind).toBe('success')
    expect(result.output).toContain('1/1 online')
    expect(result.output.match(/ONLINE/g)).toHaveLength(1)
    for (const miner of SAMPLE_MINERS) {
      if (miner.address !== host) expect(result.output).not.toContain(miner.address)
    }
  })

  it('selects multiple hosts in native sorted output order', () => {
    const a = runCommand('hashfleet status office-demo.invalid gamma-demo.invalid gamma-demo.invalid')
    const b = runCommand('hashfleet status gamma-demo.invalid office-demo.invalid')
    expect(a.output).toContain('3/3 online')
    expect(a.output.match(/gamma-demo\.invalid/g)).toHaveLength(4)
    expect(b.output).toContain('2/2 online')
    expect(b.output.indexOf('gamma-demo.invalid')).toBeLessThan(b.output.indexOf('office-demo.invalid'))
  })

  it('matches captured native --details output and includes both best-share columns', () => {
    const result = runCommand('hashfleet status --details')
    expect(result.output).toContain('BEST (ALL)')
    expect(result.output).toContain('BEST (SESSION)')
    expect(result.output).toContain('COOLING & POWER')
    expect(result.output).toContain('CONFIGURED POOLS')
    expect(result.output).not.toContain('Primary pool error')
    expect(runCommand('hashfleet status --details --json').kind).toBe('error')
  })

  it('uses the actual captured native table, details, help and full JSON output', () => {
    expect(runCommand('hashfleet status').output).toBe(captures.commands.table)
    expect(runCommand('hashfleet status --details').output).toBe(captures.commands.details)
    expect(runCommand('hashfleet --help').output).toBe(captures.commands.help)
    expect(runCommand('hashfleet status --json').output).toBe(captures.commands.json)
    expect(captures.requestAudit).toHaveLength(15)
    expect(captures.requestAudit.every(([method, path]) => method === 'GET' && path === '/api/system/info')).toBe(true)
  })

  it('accepts the native CLI positional host shorthand', () => {
    expect(runCommand('hashfleet gamma-demo.invalid').output).toBe(runCommand('hashfleet status gamma-demo.invalid').output)
  })

  it('rejects an explicit host outside the native demo fixture', () => {
    const result = runCommand('hashfleet status cpu-demo.invalid')
    expect(result.kind).toBe('error')
    expect(result.output).toContain('allowlisted fictional sample host')
    expect(result.output).toContain('Nothing was executed')
  })
})

describe('truthful snapshot data and algorithm units', () => {
  it('uses shared fictional fixture values without combining algorithms', () => {
    const output = runCommand('hashfleet status').output
    expect(output.match(/TH\/s/g)).toHaveLength(2)
    expect(output.match(/GH\/s/g)).toHaveLength(1)
    expect(output).toContain('1.22 TH/s')
    expect(output).toContain('1.16 TH/s')
    expect(output).toContain('638 GH/s')
    expect(output).toContain('18.40G')
    expect(output).toContain('9.20M')
    expect(output).not.toMatch(/total|combined/i)
  })

  it('emits valid deterministic JSON with native Codable stored-field shape', () => {
    const result = runCommand('hashfleet status --json')
    expect(result.kind).toBe('success')
    const snapshot = JSON.parse(result.output)
    expect(Object.keys(snapshot).sort(compareText)).toEqual(['miners', 'observedAt'])
    expect(snapshot.observedAt).toBe(SAMPLE_OBSERVED_AT)
    expect(snapshot.miners).toHaveLength(3)
    for (const miner of snapshot.miners) {
      expect(Object.keys(miner).sort(compareText)).toEqual(['device', 'info', 'observedAt'])
      expect(miner.device.id).toMatch(/^[0-9a-f-]{36}$/)
      expect(miner.observedAt).toBe(SAMPLE_OBSERVED_AT)
      expect(miner.info.hashRate).toBeGreaterThan(0)
      expect(miner.info).not.toHaveProperty('raw')
      expect(miner).not.toHaveProperty('isOnline')
    }
    expect(snapshot.miners.every((miner: { device: { kind: string } }) => miner.device.kind === 'espMiner')).toBe(true)
    expect(result.output).toBe(runCommand('hashfleet status --json').output)
    expect(runCommand('hashfleet --json').output).toBe(result.output)
  })

  it.each(['hashfleet status --json gamma-demo.invalid', 'hashfleet status gamma-demo.invalid --json', 'hashfleet --json gamma-demo.invalid'])('filters JSON using supported flag placement: %s', (command) => {
    const snapshot = JSON.parse(runCommand(command).output)
    expect(snapshot.miners).toHaveLength(1)
    expect(snapshot.miners[0].device.address).toBe('gamma-demo.invalid')
    expect(snapshot.miners[0].device.name).toBe('gamma-demo.invalid')
    expect(snapshot.miners[0].info.hashRate).toBe(1218)
  })

  it('keeps samples immutable and independent from each result', () => {
    const baseline = runCommand('hashfleet status --json').output
    const parsed = JSON.parse(baseline)
    parsed.miners[0].info.hashRate = 999
    expect(runCommand('hashfleet status --json').output).toBe(baseline)
    expect(Object.isFrozen(SAMPLE_MINERS)).toBe(true)
    for (const miner of SAMPLE_MINERS) expect(Object.isFrozen(miner)).toBe(true)
  })

  it('contains only fictional local hostnames and no private addresses or credential fields', () => {
    const output = runCommand('hashfleet status --json').output
    expect(output).not.toMatch(/192\.168\.|10\.\d+\.\d+\.|172\.(?:1[6-9]|2\d|3[01])\./)
    expect(output).not.toMatch(/password|wallet|bearer|token|private.?key|stratumUser/i)
    for (const miner of SAMPLE_MINERS) expect(miner.address).toMatch(/^[a-z0-9-]+\.invalid$/)
  })
})

describe('safe allowlist and bounded input', () => {
  it.each(['', ' ', '\t  ', '\n\r\t'])('ignores empty/whitespace input %j', (command) => {
    expect(runCommand(command)).toEqual({ command: '', kind: 'empty', output: '' })
  })

  it.each([
    'hashfleet watch --json', 'hashfleet list', 'hashfleet restart gamma-demo.invalid',
    'hashfleet status --watch', 'hashfleet status --json=true', 'hashfleet status -j',
    'hashfleet status --json --json', 'hashfleet status status',
    'hashfleet status unknown.local', 'hashfleet status https://example.com',
    'hashfleet status 127.0.0.1', 'Hashfleet status', 'status', 'ls',
    'clear now', 'help now', 'hashfleet clear', 'hashfleet help',
  ])('rejects unsupported command or flag %s', (command) => {
    expect(runCommand(command).kind).toBe('error')
    expect(runCommand(command).output).toMatch(/^(?:hashfleet:|Browser demo:|Unknown command)/)
  })

  it.each([
    'hashfleet status; clear', 'hashfleet status && clear', 'hashfleet status | cat',
    'hashfleet status || clear', 'hashfleet $(whoami)', 'hashfleet `whoami`',
    'hashfleet status > output', 'hashfleet status < input', 'hashfleet status\nclear',
    'hashfleet status\rclear', 'hashfleet status\u0000', 'hashfleet status\u001b[2J',
    'hashfleet status ${globalThis.__terminalProbe = true}',
    '<img src=x onerror=alert(1)>', 'javascript:alert(1)',
    'hashfleet status "gamma-demo.invalid"', 'hashfleet status *',
  ])('treats shell or script input as inert unknown text: %j', (command) => {
    const result = runCommand(command)
    expect(result.kind).toBe('error')
    expect(result.output).toContain('Unknown command')
    expect(result.output).toContain('Nothing was executed')
  })

  it('performs no network requests or evaluation for valid or malicious input', () => {
    const forbidden = vi.fn(() => { throw new Error('Forbidden side effect') })
    vi.stubGlobal('fetch', forbidden)
    vi.stubGlobal('WebSocket', forbidden)
    vi.stubGlobal('XMLHttpRequest', forbidden)
    vi.stubGlobal('eval', forbidden)
    for (const command of [...SUGGESTED_COMMANDS, 'clear', 'help', 'hashfleet status; fetch("evil")']) runCommand(command)
    expect(forbidden).not.toHaveBeenCalled()
  })

  it('accepts the exact length boundary and rejects longer input without truncation execution', () => {
    const boundary = 'hashfleet status'.padEnd(MAX_COMMAND_LENGTH, ' ')
    expect(runCommand(boundary).kind).toBe('success')
    const result = runCommand(`${boundary};clear${'a'.repeat(10_000)}`)
    expect(result.kind).toBe('error')
    expect(result.command.length).toBeLessThanOrEqual(MAX_COMMAND_LENGTH)
    expect(result.output).toContain('exceeds 256 characters')
    expect(result.output).not.toContain('3/3 online')
  })
})

describe('bounded terminal session and command history', () => {
  it('submits the input, clears the draft and leaves the previous state untouched', () => {
    const original = { ...createTerminalState(), input: 'hashfleet --help' }
    const result = submitCommand(original)
    expect(original.input).toBe('hashfleet --help')
    expect(original.entries).toHaveLength(1)
    expect(result.entries).toHaveLength(2)
    expect(result.input).toBe('')
    expect(result.history.at(-1)).toBe('hashfleet --help')
    expect(result.historyIndex).toBeNull()
  })

  it('does not add empty input to output/history or duplicate consecutive history entries', () => {
    const initial = createTerminalState()
    expect(submitCommand(initial, '  ').entries).toEqual(initial.entries)
    expect(submitCommand(initial, '  ').history).toEqual(initial.history)
    expect(submitCommand(initial, 'hashfleet status').history).toEqual(initial.history)
  })

  it('clears only this panel while retaining local history', () => {
    const state = submitCommand(createTerminalState(), 'clear')
    expect(state.entries).toEqual([])
    expect(state.history).toEqual(['hashfleet status', 'clear'])
    expect(submitCommand(state, 'hashfleet status').entries).toHaveLength(1)
    expect(createTerminalState().entries).toHaveLength(1)
  })

  it('navigates up/down, clamps oldest history, and restores the unsent draft', () => {
    let state = submitCommand(createTerminalState(), 'help')
    state = { ...state, input: 'hashfleet status gamma-demo.invalid' }
    expect(navigateHistory(state, 'down')).toBe(state)
    state = navigateHistory(state, 'up')
    expect(state.input).toBe('help')
    state = navigateHistory(state, 'up')
    expect(state.input).toBe('hashfleet status')
    state = navigateHistory(state, 'up')
    expect(state.historyIndex).toBe(0)
    state = navigateHistory(state, 'down')
    expect(state.input).toBe('help')
    state = navigateHistory(state, 'down')
    expect(state.input).toBe('hashfleet status gamma-demo.invalid')
    expect(state.historyIndex).toBeNull()
    expect(state.draft).toBe('')
  })

  it('handles an empty history without manufacturing input', () => {
    const state = { ...createTerminalState(), history: [], input: 'draft' }
    expect(navigateHistory(state, 'up')).toBe(state)
    expect(navigateHistory(state, 'down')).toBe(state)
  })

  it('bounds scrollback and history after many valid and invalid submissions', () => {
    let state = createTerminalState()
    for (let index = 0; index < 250; index += 1) state = submitCommand(state, `unknown${index}`)
    expect(state.entries).toHaveLength(MAX_SCROLLBACK)
    expect(state.history).toHaveLength(MAX_HISTORY)
    expect(state.entries.at(-1)?.command).toBe('unknown249')
    expect(state.history.at(-1)).toBe('unknown249')
    expect(state.history[0]).toBe('unknown210')
  })
})

describe('React terminal markup contract', () => {
  it.each([false, true])('renders sample labels, output, capped input, utilities and suggested commands (compact=%s)', (compact) => {
    const html = renderToStaticMarkup(createElement(TerminalDemo, { compact }))
    expect(html).toContain('SAMPLE DATA')
    expect(html).toContain('fictional fleet')
    expect(html).toContain('no connections')
    expect(html).toContain('hashfleet – zsh')
    expect(html).toContain('aria-label="Terminal command output"')
    expect(html).toContain('Terminal command</span>')
    expect(html).toContain('maxLength="256"')
    expect(html).toContain('aria-live="polite"')
    expect(html).toContain('3/3 online')
    expect(html).toContain('BEST (ALL)')
    expect(html).toContain('BEST (SESSION)')
    expect(html).toContain('simulated only')
    expect(html).toContain('browser-only utilities')
    expect(html.includes('terminal-demo--compact')).toBe(compact)
    for (const command of SUGGESTED_COMMANDS) expect(html).toContain(command)
  })

  it('defaults to the full panel and gives separate instances unique label IDs', () => {
    const html = renderToStaticMarkup(createElement('div', null, createElement(TerminalDemo), createElement(TerminalDemo)))
    expect(html).not.toContain('terminal-demo--compact')
    const ids = [...html.matchAll(/id="([^"]+-input)"/g)].map((match) => match[1])
    expect(ids).toHaveLength(2)
    expect(new Set(ids).size).toBe(2)
  })
})
