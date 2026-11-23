// @vitest-environment jsdom
import { act } from 'react'
import { createRoot } from 'react-dom/client'
import type { Root } from 'react-dom/client'
import type { ReactElement } from 'react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import App from './App'
import { IPhoneDemo, MacDemo } from './components/AppDemos'
import SupportSection from './components/SupportSection'
import TerminalDemo from './components/TerminalDemo'
import WatchDemo from './components/WatchDemo'
import HashChart from './components/HashChart'

;(globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true

let host: HTMLElement
let root: Root

async function mount(element: ReactElement) {
  await act(async () => { root.render(element) })
}
async function click(element: Element | null | undefined) {
  expect(element).toBeTruthy()
  await act(async () => { element!.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true })) })
}
async function key(element: Element, name: string, extra: KeyboardEventInit = {}) {
  await act(async () => { element.dispatchEvent(new KeyboardEvent('keydown', { key: name, bubbles: true, cancelable: true, ...extra })) })
}
function buttons(label: RegExp | string) {
  return [...host.querySelectorAll('button')].filter(button => typeof label === 'string' ? button.textContent?.includes(label) : label.test(button.textContent ?? ''))
}

beforeEach(() => {
  host = document.createElement('div')
  document.body.appendChild(host)
  root = createRoot(host)
  window.HTMLElement.prototype.scrollIntoView = vi.fn()
  window.HTMLElement.prototype.scrollTo = vi.fn() as never
  window.matchMedia = ((query: string) => ({ matches: false, media: query, addEventListener() {}, removeEventListener() {}, addListener() {}, removeListener() {}, onchange: null, dispatchEvent: () => false })) as never
  HTMLDialogElement.prototype.showModal = function () { this.setAttribute('open', '') }
  HTMLDialogElement.prototype.close = function () { this.removeAttribute('open'); this.dispatchEvent(new Event('close')) }
})

afterEach(async () => {
  await act(async () => { root.unmount() })
  host.remove()
  vi.restoreAllMocks()
})

describe('native walkthrough interactions', () => {
  it('navigates the Mac and iPhone captures with back, reset, enlarge and target toggles', async () => {
    await mount(<><MacDemo /><IPhoneDemo /></>)
    for (const section of host.querySelectorAll('.native-walkthrough')) {
      const select = section.querySelector('select')!
      const options = [...select.options].map(option => option.value)
      expect(options.length).toBeGreaterThan(1)
      await act(async () => {
        const setter = Object.getOwnPropertyDescriptor(HTMLSelectElement.prototype, 'value')!.set!
        setter.call(select, options[1])
        select.dispatchEvent(new Event('change', { bubbles: true }))
      })
      expect(select.value).toBe(options[1])
      const hotspot = section.querySelector<HTMLButtonElement>('.native-hotspot')
      if (hotspot) await click(hotspot)
      await click([...section.querySelectorAll('button')].find(button => /Back/.test(button.textContent ?? '')))
      await click([...section.querySelectorAll('button')].find(button => /Enlarge screen/.test(button.textContent ?? '')))
      expect(section.querySelector('.native-viewport--enlarged')).toBeTruthy()
      await click([...section.querySelectorAll('button')].find(button => /Fit screen/.test(button.textContent ?? '')))
      await click([...section.querySelectorAll('button')].find(button => /Clickable areas/.test(button.textContent ?? '')))
      const image = section.querySelector('img.native-capture')!
      await act(async () => { image.dispatchEvent(new Event('error')) })
      expect(section.querySelector('.native-load-error')).toBeTruthy()
      await click([...section.querySelectorAll('button')].find(button => /Reset tour/.test(button.textContent ?? '')))
      expect(select.value).toBe(options[0])
    }
    await click(buttons('See the miner cards')[0])
    await click(buttons('Fleet overview')[0])
    const compact = document.createElement('div')
    const other = createRoot(compact)
    await act(async () => { other.render(<MacDemo compact />) })
    expect(compact.querySelector('img.native-preview')).toBeTruthy()
    await act(async () => { other.unmount() })
  })

  it('steps through the Watch tour, handles load errors and the reset control', async () => {
    vi.spyOn(window, 'requestAnimationFrame').mockImplementation(callback => { callback(0); return 1 })
    await mount(<WatchDemo />)
    const steps = [...host.querySelectorAll<HTMLButtonElement>('[data-watch-step]')]
    expect(steps.length).toBeGreaterThan(1)
    await click(steps[1])
    const hotspot = host.querySelector<HTMLButtonElement>('[data-watch-target]')
    if (hotspot) await click(hotspot)
    await click(buttons('Next screen')[0])
    await click(buttons('Back')[0])
    const image = host.querySelector('img[data-watch-capture]')!
    await act(async () => { image.dispatchEvent(new Event('error')) })
    expect(host.querySelector('.watch-load-error')).toBeTruthy()
    await click(buttons('Reload capture')[0])
    await click(steps.at(-1))
    expect(buttons('Next screen')[0].disabled).toBe(true)
    await click(buttons('Reset tour')[0])
    expect(host.querySelector('[data-watch-capture="watch-fleet"]')).toBeTruthy()
  })
})

describe('terminal demo', () => {
  it('runs commands, keeps history, clears and opens the interactive views', async () => {
    await mount(<TerminalDemo />)
    const input = host.querySelector<HTMLInputElement>('input')!
    const setInput = async (value: string) => act(async () => {
      Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')!.set!.call(input, value)
      input.dispatchEvent(new Event('input', { bubbles: true }))
    })
    const submit = async () => act(async () => { host.querySelector('form')!.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true })) })
    await setInput('hashfleet --help')
    await submit()
    await setInput('definitely-not-a-command')
    await submit()
    await key(input, 'ArrowUp')
    await key(input, 'ArrowUp')
    await key(input, 'ArrowDown')
    await key(input, 'ArrowDown')
    await key(input, 'Enter')
    for (const suggestion of host.querySelectorAll('.terminal-demo__suggestions button')) await click(suggestion)
    await click(host.querySelector('.terminal-demo__suggestions button:last-child'))
    expect(host.textContent).toContain('Panel cleared')
    await setInput('hashfleet watch --demo')
    await submit()
    await act(async () => { await new Promise(resolve => setTimeout(resolve, 50)) })
    await setInput('hashfleet settings --demo')
    await submit()
    await act(async () => { await new Promise(resolve => setTimeout(resolve, 50)) })
    await mount(<TerminalDemo compact />)
    expect(host.querySelector('.terminal-demo--compact')).toBeTruthy()
  })
})

describe('support copy flow', () => {
  it('reports copied, denied and busy states', async () => {
    const writeText = vi.fn().mockResolvedValue(undefined)
    Object.defineProperty(navigator, 'clipboard', { value: { writeText }, configurable: true })
    await mount(<SupportSection />)
    const copyButtons = [...host.querySelectorAll<HTMLButtonElement>('.support-copy')]
    expect(copyButtons.length).toBeGreaterThan(0)
    await click(copyButtons[0])
    expect(writeText).toHaveBeenCalled()
    expect(host.querySelector('.support-copy-status')?.textContent).toContain('copied')
    Object.defineProperty(navigator, 'clipboard', { value: { writeText: vi.fn().mockRejectedValue(new Error('denied')) }, configurable: true })
    window.getSelection = (() => ({ removeAllRanges() {}, addRange() {} })) as never
    document.createRange = (() => ({ selectNodeContents() {} })) as never
    await click(copyButtons[1] ?? copyButtons[0])
    expect(host.textContent).toContain('Automatic copy is unavailable')
    Object.defineProperty(navigator, 'clipboard', { get() { throw new Error('blocked') }, configurable: true })
    await click(copyButtons[0])
    expect(host.textContent).toContain('Automatic copy is unavailable')
  })
})

describe('hash chart', () => {
  it('tracks the hovered point across every range', async () => {
    for (const range of ['15m', '1h', '24h'] as const) {
      await mount(<HashChart range={range} />)
      const svg = host.querySelector('svg')!
      svg.getBoundingClientRect = () => ({ left: 0, width: 600, top: 0, height: 170, right: 600, bottom: 170, x: 0, y: 0, toJSON() {} })
      await act(async () => { svg.dispatchEvent(new MouseEvent('mousemove', { bubbles: true, clientX: 300 })) })
      expect(host.querySelector('circle')).toBeTruthy()
      await act(async () => { svg.dispatchEvent(new MouseEvent('mouseout', { bubbles: true })) })
      await act(async () => { svg.dispatchEvent(new MouseEvent('mouseleave', { bubbles: false })) })
    }
  })
})

describe('full site', () => {
  it('drives tabs, theme, menu, dialogs and keyboard navigation', async () => {
    window.history.replaceState(null, '', '/')
    await mount(<App startAtDemo />)
    const tabs = [...host.querySelectorAll<HTMLButtonElement>('[role="tab"]')]
    expect(tabs).toHaveLength(4)
    await key(tabs[0], 'ArrowRight')
    await key(tabs[1], 'ArrowLeft')
    await key(tabs[0], 'End')
    await key(tabs[3], 'Home')
    await key(tabs[0], 'x')
    for (const tab of tabs) await click(tab)
    await click(host.querySelector('.theme-toggle'))
    expect(document.documentElement.dataset.theme).toBe('light')
    await click(host.querySelector('.theme-toggle'))
    await click(host.querySelector('.mobile-menu'))
    await click(host.querySelector('.main-nav a'))
    await click(host.querySelector('.hero-phone'))
    await click(host.querySelector('.hero-watch'))
    await click(host.querySelector('.hero-terminal'))
    for (const button of host.querySelectorAll('.text-link, .feature-code, .hero-actions .button-primary')) await click(button)

    await click(host.querySelector('.button-nav'))
    expect(host.querySelector('dialog')).toBeTruthy()
    const dialog = host.querySelector('dialog')!
    await key(dialog, 'Tab')
    await key(dialog, 'Tab', { shiftKey: true })
    await key(dialog, 'Escape')
    await click(host.querySelector('.dialog-close'))
    expect(host.querySelector('dialog')).toBeNull()

    const footerButtons = [...host.querySelectorAll<HTMLButtonElement>('.site-footer button')]
    await click(footerButtons.find(button => /Privacy/.test(button.textContent ?? '')))
    expect(host.querySelector('dialog')?.textContent).toContain('Your fleet stays yours')
    await act(async () => { host.querySelector('dialog')!.dispatchEvent(new MouseEvent('click', { bubbles: true })) })
    expect(host.querySelector('dialog')).toBeNull()

    window.location.hash = '#download'
    await act(async () => { window.dispatchEvent(new HashChangeEvent('hashchange')) })
    expect(host.querySelector('dialog')).toBeTruthy()
    window.history.replaceState(null, '', '/')
    await act(async () => { window.dispatchEvent(new HashChangeEvent('hashchange')) })
    expect(host.querySelector('dialog')).toBeNull()
  })
})
