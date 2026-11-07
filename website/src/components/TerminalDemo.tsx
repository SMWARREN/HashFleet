import { lazy, Suspense, useEffect, useId, useRef, useState } from 'react'
import AnsiOutput from './AnsiOutput'
import {
  createTerminalState,
  MAX_COMMAND_LENGTH,
  navigateHistory,
  SUGGESTED_COMMANDS,
  submitCommand,
} from '../lib/terminal'
import './terminal.css'
const DashboardPreview = lazy(() => import('./DashboardPreview'))

export default function TerminalDemo({ compact = false }: { compact?: boolean }) {
  const [terminal, setTerminal] = useState(createTerminalState)
  const inputRef = useRef<HTMLInputElement>(null)
  const outputRef = useRef<HTMLDivElement>(null)
  const id = useId()

  useEffect(() => {
    const output = outputRef.current
    const last = output?.lastElementChild as HTMLElement | null
    if (output && last) output.scrollTop = last.offsetTop
  }, [terminal.entries])

  function execute(command?: string) {
    setTerminal((state) => submitCommand(state, command ?? state.input))
    inputRef.current?.focus({ preventScroll: true })
  }

  return (
    <section className={`terminal-demo${compact ? ' terminal-demo--compact' : ''}`} aria-labelledby={`${id}-title`}>
      <header className="terminal-demo__titlebar">
        <span className="terminal-demo__traffic" aria-hidden="true"><i /><i /><i /></span>
        <span id={`${id}-title`} className="terminal-demo__title">hashfleet – zsh</span>
        <span className="terminal-demo__badge">SAMPLE DATA</span>
      </header>

      <div className="terminal-demo__notice" id={`${id}-notice`}>
        <span className="terminal-demo__status-dot" aria-hidden="true" />
        Browser demo · fictional fleet · no connections
      </div>

      <div ref={outputRef} className="terminal-demo__output" role="region" aria-label="Terminal command output" tabIndex={0}>
        {terminal.entries.length === 0 && <p className="terminal-demo__empty">Panel cleared. Try a suggested command below.</p>}
        {terminal.entries.map((entry, index) => (
          <div className="terminal-demo__entry" key={`${index}-${entry.command}`}
            hidden={!!terminal.entries.at(-1)?.view && index !== terminal.entries.length - 1}>
            <div className="terminal-demo__command"><span aria-hidden="true">❯</span> <span>{entry.command}</span></div>
            {entry.view && index === terminal.entries.length - 1 ? <Suspense fallback={<p>Opening CLI demo…</p>}>
              <DashboardPreview settings={entry.view === 'settings'} onExit={() => {
                setTerminal(state => ({ ...state, entries: state.entries.map((item, i) => i === state.entries.length - 1 ? { ...item, view: undefined, output: 'Demo closed. Run another command below.' } : item) }))
                inputRef.current?.focus({ preventScroll: true })
              }} />
            </Suspense> : <pre className={entry.kind === 'error' ? 'terminal-demo__result terminal-demo__result--error' : 'terminal-demo__result'}>
              {entry.ansi ? <AnsiOutput value={entry.ansi} /> : entry.output}
            </pre>}
          </div>
        ))}
      </div>

      <form className="terminal-demo__form" onSubmit={(event) => { event.preventDefault(); execute() }}>
        <label htmlFor={`${id}-input`} className="terminal-demo__prompt"><span aria-hidden="true">❯</span><span className="terminal-demo__sr-only">Terminal command</span></label>
        <input
          id={`${id}-input`}
          ref={inputRef}
          value={terminal.input}
          maxLength={MAX_COMMAND_LENGTH}
          placeholder="Try hashfleet --help"
          aria-describedby={`${id}-notice ${id}-hint`}
          autoComplete="off"
          autoCapitalize="none"
          autoCorrect="off"
          spellCheck={false}
          enterKeyHint="send"
          onChange={(event) => {
            const input = event.target.value.slice(0, MAX_COMMAND_LENGTH)
            setTerminal((state) => ({ ...state, input, historyIndex: null, draft: '' }))
          }}
          onKeyDown={(event) => {
            if (event.nativeEvent.isComposing) return
            if (event.key === 'ArrowUp' || event.key === 'ArrowDown') {
              event.preventDefault()
              const direction = event.key === 'ArrowUp' ? 'up' : 'down'
              setTerminal((state) => navigateHistory(state, direction))
            }
          }}
        />
        <button type="submit" className="terminal-demo__run" aria-label="Run simulated command">Run <span aria-hidden="true">↵</span></button>
      </form>

      <div className="terminal-demo__suggestions" aria-label="Suggested terminal commands">
        {SUGGESTED_COMMANDS.map((command) => <button type="button" key={command} onClick={() => execute(command)}>{command}</button>)}
        <button type="button" onClick={() => execute('clear')} aria-label="Clear panel, browser demo utility">clear <span>demo utility</span></button>
      </div>

      <footer className="terminal-demo__footer" id={`${id}-hint`}>
        <span>Native CLI sample · BEST (ALL) + BEST (SESSION) · simulated only</span>
        <span>↑ ↓ history · help / clear are browser-only utilities</span>
      </footer>
      <p className="terminal-demo__sr-only" role="status" aria-live="polite" aria-atomic="true">
        {terminal.entries.length ? `${terminal.entries.at(-1)?.command}: ${terminal.entries.at(-1)?.kind === 'error' ? terminal.entries.at(-1)?.output : 'Sample output ready in the terminal command output region.'}` : 'Terminal panel cleared.'}
      </p>
    </section>
  )
}
