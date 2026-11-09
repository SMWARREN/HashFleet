import captures from './cli-captures.json'
import { plainAnsi } from './ansi'
import { compareText } from './order'

/** Pure, allowlisted terminal simulator. It never evaluates shell input or performs I/O. */
export const MAX_COMMAND_LENGTH = 256
export const MAX_SCROLLBACK = 24
export const MAX_HISTORY = 40
export const SAMPLE_OBSERVED_AT = '2026-01-01T12:00:00Z'

export interface SampleMiner {
  readonly name: string
  readonly address: string
  readonly kind: 'espMiner' | 'xmrig'
  readonly algorithm: 'SHA-256' | 'RandomX'
  /** Matches MinerInfo.hashRate: normalized GH/s, including XMRig. */
  readonly hashRate: number
  readonly temp?: number
  readonly power?: number
  readonly bestDiff?: string
  readonly bestSessionDiff?: string
}

type CapturedMiner = {
  device: { address: string, id: string, kind: 'espMiner' | 'xmrig', name: string }
  info: Record<string, unknown> & { hashRate?: number, temp?: number, power?: number, bestDiff?: string, bestSessionDiff?: string }
  observedAt: string
}
type CapturedSnapshot = { miners: CapturedMiner[], observedAt: string }
const commands = captures.commands
const parsedSnapshot = JSON.parse(commands.json) as CapturedSnapshot
const names: Record<string, string> = {
  'gamma-demo.invalid': 'Workshop Gamma',
  'office-demo.invalid': 'Office Gamma',
  'supra-demo.invalid': 'Little Supra',
}

export const SAMPLE_MINERS: readonly SampleMiner[] = Object.freeze(parsedSnapshot.miners.map((entry) => Object.freeze({
  name: names[entry.device.address] ?? entry.device.name,
  address: entry.device.address,
  kind: entry.device.kind,
  algorithm: 'SHA-256' as const,
  hashRate: entry.info.hashRate ?? 0,
  ...(typeof entry.info.temp === 'number' ? { temp: entry.info.temp } : {}),
  ...(typeof entry.info.power === 'number' ? { power: entry.info.power } : {}),
  ...(typeof entry.info.bestDiff === 'string' ? { bestDiff: entry.info.bestDiff } : {}),
  ...(typeof entry.info.bestSessionDiff === 'string' ? { bestSessionDiff: entry.info.bestSessionDiff } : {}),
})))

export const SUGGESTED_COMMANDS = [
  'hashfleet watch --demo',
  'hashfleet status',
  'hashfleet settings --demo',
  'hashfleet logo',
  'hashfleet status --details',
  'hashfleet status --json',
  'hashfleet status gamma-demo.invalid office-demo.invalid',
  'hashfleet --help',
] as const

const USAGE = commands.help
const BROWSER_GUIDE = `${USAGE}\n\nBrowser demo: fictional sample data only. No network requests.\nAllowed sample hosts: gamma-demo.invalid, office-demo.invalid, supra-demo.invalid.\nBrowser-only utilities: help (show this guide), clear (clear this panel). They are not hashfleet commands.\nUse ArrowUp / ArrowDown for command history. Try hashfleet watch --demo for keyboard navigation, hashfleet settings --demo for native settings previews, or hashfleet logo.`
const ALLOWED_HOSTS = new Set(SAMPLE_MINERS.map((miner) => miner.address))

export interface CommandResult {
  command: string
  kind: 'success' | 'error' | 'empty' | 'clear'
  output: string
  ansi?: string
  view?: 'dashboard' | 'settings'
}

/** Reassemble actual colored terminal captures for the selected fictional hosts. */
export function coloredStatus(details: boolean, selected: readonly string[], explicit: boolean): string {
  const capture = details ? captures.tty.details : captures.tty.table
  const groups = capture.miners as Record<string, string>
  return [capture.header.replace(/(?<!\d)\d+\/\d+ online/, `${selected.length}/${selected.length} online`),
    ...selected.map(host => explicit
      ? groups[host].replace(names[host].padEnd(23), host.padEnd(23))
      : groups[host]), capture.footer].join('\n')
}

function failure(command: string, message = 'Unknown command or host. This browser demo only accepts the documented hashfleet status syntax and fictional sample hosts. Nothing was executed.'): CommandResult {
  return { command, kind: 'error', output: message }
}

function nativeParseError(command: string, message: string): CommandResult {
  return failure(command, `hashfleet: ${message}\n\n${USAGE}`)
}

function selectTable(capture: string, selected: readonly string[], explicit: boolean): string {
  const lines = capture.split('\n')
  const header = lines.slice(0, 3)
  const groups: string[][] = []
  for (const line of lines.slice(3)) {
    if (/^(?:Workshop Gamma|Office Gamma|Little Supra)\s/.test(line)) groups.push([line])
    else if (groups.length > 0) groups.at(-1)?.push(line)
  }
  const groupByHost = new Map(groups.map((group) => [group[0].slice(21, 49).trim(), group]))
  const chosen = selected.flatMap((host) => {
    const group = groupByHost.get(host)
    if (!group) return []
    if (!explicit) return [group]
    return [[`${host.padEnd(20)}${group[0].slice(20)}`, ...group.slice(1)]]
  })
  const count = chosen.length
  header[0] = header[0].replace(/(?<!\d)\d+\/\d+ online/, `${count}/${count} online`)
  return [...header, ...chosen.flat()].join('\n')
}

function stableValue(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(stableValue)
  if (value && typeof value === 'object') {
    return Object.fromEntries(Object.entries(value).sort(([a], [b]) => compareText(a, b)).map(([key, item]) => [key, stableValue(item)]))
  }
  return value
}

type StatusOptions = { json: boolean, details: boolean, statusSeen: boolean, hosts: string[] }

function consumeStatusToken(command: string, token: string, options: StatusOptions): CommandResult | undefined {
  switch (token) {
    case 'status':
      if (options.statusSeen || options.hosts.length > 0 || options.json || options.details) {
        return nativeParseError(command, 'status must be the first command word.')
      }
      options.statusSeen = true
      break
    case '--json':
      if (options.json) return nativeParseError(command, '--json may be supplied only once.')
      options.json = true
      break
    case '--details':
      if (options.details) return nativeParseError(command, '--details may be supplied only once.')
      options.details = true
      break
    default:
      if (token.startsWith('-')) return nativeParseError(command, `unknown option '${token}'.`)
      if (!ALLOWED_HOSTS.has(token)) {
        return failure(command, `Browser demo: '${token}' is not an allowlisted fictional sample host. Nothing was executed.`)
      }
      options.hosts.push(token)
  }
}

function specialCommand(command: string, tokens: string[]): CommandResult | undefined {
  if (tokens.includes('--help') || tokens.includes('-h')) return { command, kind: 'success', output: USAGE }
  if (tokens.length === 0 || (tokens[0] === 'watch' && (tokens.length === 1 || (tokens.length === 2 && tokens[1] === '--demo')))) {
    return { command, kind: 'success', output: 'Interactive sample dashboard. Use arrows, d for details, e for settings, or the buttons.', view: 'dashboard' }
  }
  if (tokens[0] === 'settings' && (tokens.length === 1 || (tokens.length === 2 && tokens[1] === '--demo'))) {
    return { command, kind: 'success', output: 'Native demo settings: view pool, fan and tuning settings. No changes are sent.', view: 'settings' }
  }
  if (tokens.length === 1 && tokens[0] === 'logo') {
    return { command, kind: 'success', output: plainAnsi(captures.logo), ansi: captures.logo }
  }
}

function statusResult(command: string, { hosts, json, details }: StatusOptions): CommandResult {
  const selected = hosts.length ? [...hosts].sort(compareText) : SAMPLE_MINERS.map((miner) => miner.address)
  const minerByHost = new Map(parsedSnapshot.miners.map((miner) => [miner.device.address, miner]))
  const miners = selected.flatMap((host) => minerByHost.get(host) ? [minerByHost.get(host)!] : [])
  if (json) {
    if (hosts.length === 0) return { command, kind: 'success', output: commands.json }
    const snapshot = stableValue({ ...parsedSnapshot, miners: miners.map((miner) => ({
      ...miner,
      // Native explicit-host mode names each device with its supplied host.
      device: { ...miner.device, address: miner.device.address, name: miner.device.address },
    })) })
    return { command, kind: 'success', output: JSON.stringify(snapshot, null, 2) }
  }
  return {
    command,
    kind: 'success',
    output: selectTable(details ? commands.details : commands.table, selected, hosts.length > 0),
    ansi: coloredStatus(details, selected, hosts.length > 0),
  }
}

/** Supports native status syntax, with a stricter fictional-host allowlist in the browser. */
export function runCommand(input: string): CommandResult {
  const command = input.slice(0, MAX_COMMAND_LENGTH).replace(/[\u0000-\u001f\u007f]/g, ' ').trim()
  if (input.length > MAX_COMMAND_LENGTH) return failure(command, `Browser demo: input exceeds ${MAX_COMMAND_LENGTH} characters. Nothing was executed.`)
  if (!input.trim()) return { command: '', kind: 'empty', output: '' }
  if (/[^a-zA-Z0-9. :\t-]/.test(input)) return failure(command)
  const words = input.trim().split(/[ \t]+/)
  if (words.length === 1 && words[0] === 'clear') return { command, kind: 'clear', output: '' }
  if (words.length === 1 && words[0] === 'help') return { command, kind: 'success', output: BROWSER_GUIDE }
  if (words[0] !== 'hashfleet') return failure(command)
  const tokens = words.slice(1)
  const special = specialCommand(command, tokens)
  if (special) return special
  const options: StatusOptions = { json: false, details: false, statusSeen: false, hosts: [] }
  for (const token of tokens) {
    const error = consumeStatusToken(command, token, options)
    if (error) return error
  }
  if (options.json && options.details) return nativeParseError(command, '--json and --details are alternative output formats.')
  return statusResult(command, options)
}

export interface TerminalState {
  input: string
  entries: CommandResult[]
  history: string[]
  historyIndex: number | null
  draft: string
}

export function createTerminalState(): TerminalState {
  return {
    input: '',
    entries: [runCommand('hashfleet status')],
    history: ['hashfleet status'],
    historyIndex: null,
    draft: '',
  }
}

export function submitCommand(state: TerminalState, input = state.input): TerminalState {
  const result = runCommand(input)
  if (result.kind === 'empty') return { ...state, input: '', historyIndex: null, draft: '' }
  const history = state.history.at(-1) === result.command
    ? state.history
    : [...state.history, result.command].slice(-MAX_HISTORY)
  return {
    input: '',
    entries: result.kind === 'clear' ? [] : [...state.entries, result].slice(-MAX_SCROLLBACK),
    history,
    historyIndex: null,
    draft: '',
  }
}

export function navigateHistory(state: TerminalState, direction: 'up' | 'down'): TerminalState {
  if (state.history.length === 0 || (direction === 'down' && state.historyIndex === null)) return state
  const draft = state.historyIndex === null ? state.input : state.draft
  const index = direction === 'up'
    ? Math.max(0, (state.historyIndex ?? state.history.length) - 1)
    : (state.historyIndex ?? state.history.length) + 1
  return index >= state.history.length
    ? { ...state, input: draft, historyIndex: null, draft: '' }
    : { ...state, input: state.history[index], historyIndex: index, draft }
}
