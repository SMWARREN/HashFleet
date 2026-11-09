import { isValidElement } from 'react'
import type { ChangeEvent, KeyboardEvent, ReactElement, ReactNode } from 'react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import DashboardPreview from './DashboardPreview'
import AnsiOutput from './AnsiOutput'
import captures from '../lib/cli-dashboard-captures.json'

// This bounded hook harness executes the production component's returned handlers.
// It models state/ref commits only, not a browser, React scheduling or assistive technology.
const hooks = vi.hoisted(() => ({
  values: [] as unknown[], cursor: 0,
  refs: [] as { current: unknown }[], refCursor: 0,
  dependencies: [] as (readonly unknown[] | undefined)[], effectCursor: 0,
  effects: [] as (() => void)[],
}))
vi.mock('react', async importOriginal => ({
  ...await importOriginal<typeof import('react')>(),
  useState: <T,>(initial: T | (() => T)) => {
    const index = hooks.cursor++
    if (!(index in hooks.values)) hooks.values[index] = typeof initial === 'function' ? (initial as () => T)() : initial
    return [hooks.values[index], (next: T | ((previous: T) => T)) => {
      hooks.values[index] = typeof next === 'function' ? (next as (previous: T) => T)(hooks.values[index] as T) : next
    }]
  },
  useRef: <T,>(initial: T) => {
    const index = hooks.refCursor++
    hooks.refs[index] ??= { current: initial }
    return hooks.refs[index]
  },
  useEffect: (effect: () => void, dependencies?: readonly unknown[]) => {
    const index = hooks.effectCursor++
    const previous = hooks.dependencies[index]
    if (!previous || !dependencies || dependencies.some((value, offset) => !Object.is(value, previous[offset]))) hooks.effects.push(effect)
    hooks.dependencies[index] = dependencies
  },
}))

type Props = {
  children?: ReactNode, className?: string, value?: string | number,
  'aria-label'?: string, 'aria-pressed'?: boolean,
  ref?: { current: HTMLElement | null },
  onClick?: () => void,
  onChange?: (event: ChangeEvent<HTMLSelectElement>) => void,
  onKeyDown?: (event: KeyboardEvent<HTMLElement>) => void,
}
type Element = ReactElement<Props>
function elements(node: ReactNode): Element[] {
  if (Array.isArray(node)) return node.flatMap(elements)
  if (!isValidElement<Props>(node)) return []
  return [node, ...elements(node.props.children)]
}
function text(node: ReactNode): string {
  if (Array.isArray(node)) return node.map(text).join('')
  if (isValidElement<Props>(node)) return text(node.props.children)
  return typeof node === 'string' || typeof node === 'number' ? String(node) : ''
}

function mount(settings = false, attached = true, hasAncestors = true) {
  const onExit = vi.fn()
  const entry = { offsetTop: 42 }
  const output = { scrollTop: 0 }
  const viewport = {
    focus: vi.fn(), scrollBy: vi.fn(), scrollTop: 19,
    closest: vi.fn((selector: string) => {
      if (!hasAncestors) return null
      return selector === '.terminal-demo__entry' ? entry : output
    }),
  }
  let tree: ReactNode
  function find(predicate: (element: Element) => boolean): Element {
    const found = elements(tree).find(predicate)
    if (!found) throw new Error('Missing expected dashboard element')
    return found
  }
  function render() {
    hooks.cursor = 0
    hooks.refCursor = 0
    hooks.effectCursor = 0
    tree = DashboardPreview({ settings, onExit })
    const ref = find(element => element.props.className === 'cli-dashboard__viewport').props.ref
    if (!ref) throw new Error('Missing viewport ref')
    ref.current = attached ? viewport as unknown as HTMLElement : null
    const effects = hooks.effects.splice(0)
    for (const effect of effects) effect()
  }
  function key(value: string, modifiers: Partial<KeyboardEvent<HTMLElement>> = {}) {
    const target = viewport as unknown as HTMLElement
    const event = { key: value, target, currentTarget: target, altKey: false, metaKey: false, ctrlKey: false, shiftKey: false, preventDefault: vi.fn(), ...modifiers }
    const handler = find(element => element.props.className === 'cli-dashboard__viewport').props.onKeyDown
    if (!handler) throw new Error('Missing keyboard handler')
    handler(event as KeyboardEvent<HTMLElement>)
    render()
    return event
  }
  function click(label: string) {
    const handler = find(element => element.type === 'button' && text(element).trim() === label).props.onClick
    if (!handler) throw new Error(`Missing click handler: ${label}`)
    handler()
    render()
  }
  function select(miner: number) {
    const handler = find(element => element.type === 'select').props.onChange
    if (!handler) throw new Error('Missing miner selector handler')
    handler({ target: { value: String(miner) } } as ChangeEvent<HTMLSelectElement>)
    render()
  }
  function expectFrame(id: string) {
    const expected = (captures.frames as Record<string, number[]>)[id].map(index => captures.lines[index]).join('\n')
    expect(find(element => element.type === AnsiOutput).props.value).toBe(expected)
  }
  render()
  return { onExit, viewport, output, key, click, select, expectFrame,
    announcement: () => text(find(element => element.type === 'output')),
    selectedMiner: () => find(element => element.type === 'select').props.value,
    pressed: (label: string) => find(element => element.type === 'button' && text(element).trim() === label).props['aria-pressed'],
  }
}

beforeEach(() => {
  hooks.values = []
  hooks.refs = []
  hooks.dependencies = []
  hooks.effects = []
})

describe('dashboard production handlers in an offline state harness', () => {
  it('focuses the attached viewport and aligns its terminal entry on initial commit', () => {
    const demo = mount()
    expect(demo.viewport.focus).toHaveBeenCalledExactlyOnceWith({ preventScroll: true })
    expect(demo.output.scrollTop).toBe(42)
    expect(demo.viewport.scrollTop).toBe(0)
    demo.expectFrame('fleet:name:0:0')
    expect(demo.announcement()).toBe('Gamma / desk · fleet')
  })
  it.each([false, true])('tolerates missing viewport ancestors with attached=%s', attached => {
    const demo = mount(false, attached, false)
    expect(demo.output.scrollTop).toBe(0)
    demo.key('d')
    demo.key('ArrowDown')
    expect(demo.viewport.scrollBy).toHaveBeenCalledTimes(attached ? 1 : 0)
  })
  it.each(['Tab', 'PageUp', 'PageDown', '?', 'c', '5', '0'])('leaves unsupported or browser navigation key %s untouched', key => {
    const demo = mount()
    expect(demo.key(key).preventDefault).not.toHaveBeenCalled()
    demo.expectFrame('fleet:name:0:0')
    expect(demo.onExit).not.toHaveBeenCalled()
    expect(demo.viewport.scrollBy).not.toHaveBeenCalled()
  })
  it('leaves Shift+Tab untouched', () => {
    expect(mount().key('Tab', { shiftKey: true }).preventDefault).not.toHaveBeenCalled()
  })
  it.each(['descendant', 'alt', 'meta'])('ignores %s events before handling recognized shortcuts', kind => {
    const demo = mount()
    const modifiers = kind === 'descendant' ? { target: {} as HTMLElement } : { altKey: kind === 'alt', metaKey: kind === 'meta' }
    expect(demo.key('q', modifiers).preventDefault).not.toHaveBeenCalled()
    expect(demo.onExit).not.toHaveBeenCalled()
    demo.expectFrame('fleet:name:0:0')
  })
  it.each([['q', false], ['Q', false], ['c', true]] as const)('exits for key %s with ctrl=%s', (key, ctrlKey) => {
    const demo = mount()
    expect(demo.key(key, { ctrlKey }).preventDefault).toHaveBeenCalledOnce()
    expect(demo.onExit).toHaveBeenCalledOnce()
  })
  it.each([
    ['ArrowRight', 2], [']', 2], ['ArrowDown', 2], ['j', 2],
    ['ArrowLeft', 0], ['[', 0], ['ArrowUp', 0], ['k', 0],
  ] as const)('moves selected miner with %s', (key, miner) => {
    const demo = mount()
    demo.select(1)
    expect(demo.key(key).preventDefault).toHaveBeenCalledOnce()
    expect(demo.selectedMiner()).toBe(miner)
    demo.expectFrame(`fleet:name:0:${miner}`)
    expect(demo.viewport.scrollBy).not.toHaveBeenCalled()
  })
  it('clamps miner navigation at both boundaries', () => {
    const demo = mount()
    demo.key('ArrowLeft')
    expect(demo.selectedMiner()).toBe(0)
    demo.select(3)
    demo.key('ArrowRight')
    expect(demo.selectedMiner()).toBe(3)
  })
  it('cycles sort order, follows its miner ordering and toggles pause via real shortcuts', () => {
    const demo = mount()
    demo.key('s')
    demo.key('ArrowLeft')
    demo.expectFrame('fleet:hashrate:0:2')
    demo.key(' ')
    demo.expectFrame('fleet:hashrate:1:2')
    demo.key(' ')
    demo.key('s')
    demo.expectFrame('fleet:temperature:0:2')
    demo.key('s')
    demo.expectFrame('fleet:name:0:2')
  })
  it('toggles details with enter/d and returns via escape or b', () => {
    const demo = mount()
    demo.key('Enter')
    demo.expectFrame('details:0:1')
    demo.key('d')
    demo.expectFrame('fleet:name:0:0')
    demo.key('d')
    demo.key('Escape')
    demo.expectFrame('fleet:name:0:0')
    demo.key('e')
    demo.key('b')
    demo.expectFrame('fleet:name:0:0')
  })
  it('toggles the logo without changing the selected miner', () => {
    const demo = mount()
    demo.select(2)
    demo.key('l')
    demo.expectFrame('logo')
    demo.key('l')
    demo.expectFrame('fleet:name:0:2')
  })
  it('selects all supported numeric detail and settings pages and rejects out-of-range keys', () => {
    const demo = mount()
    for (let section = 1; section <= 4; section++) {
      expect(demo.key(String(section)).preventDefault).toHaveBeenCalledOnce()
      demo.expectFrame(`details:0:${section}`)
    }
    expect(demo.key('5').preventDefault).not.toHaveBeenCalled()
    demo.key('e')
    for (let category = 1; category <= 5; category++) {
      demo.key(String(category))
      demo.expectFrame(`settings:0:${category}`)
    }
    expect(demo.key('6').preventDefault).not.toHaveBeenCalled()
  })
  it('wraps settings categories with left/right while brackets change the miner', () => {
    const demo = mount(true)
    demo.expectFrame('settings:0:1')
    demo.key('ArrowLeft')
    demo.expectFrame('settings:0:5')
    demo.key('ArrowRight')
    demo.expectFrame('settings:0:1')
    demo.key(']')
    demo.expectFrame('settings:1:1')
    demo.key('[')
    demo.expectFrame('settings:0:1')
  })
  it.each(['Enter', 'd'])('announces preview-only settings instead of applying changes for %s', key => {
    const demo = mount(true)
    expect(demo.key(key).preventDefault).toHaveBeenCalledOnce()
    expect(demo.announcement()).toBe('Native demo mode is preview only. Use the installed CLI to edit and review changes.')
    demo.expectFrame('settings:0:1')
  })
  it.each([
    ['d', 'ArrowDown', 40], ['d', 'j', 40], ['d', 'ArrowUp', -40], ['d', 'k', -40],
    ['e', 'ArrowDown', 40], ['e', 'j', 40], ['e', 'ArrowUp', -40], ['e', 'k', -40],
  ] as const)('scrolls page %s using %s without changing miner', (screen, key, top) => {
    const demo = mount()
    demo.key(screen)
    expect(demo.key(key).preventDefault).toHaveBeenCalledOnce()
    expect(demo.viewport.scrollBy).toHaveBeenCalledExactlyOnceWith({ top })
    expect(demo.selectedMiner()).toBe(0)
  })
  it.each([['d', ' '], ['d', 's'], ['e', ' '], ['e', 's']] as const)('does not handle fleet-only key %s/%s on another page', (screen, key) => {
    const demo = mount()
    demo.key(screen)
    expect(demo.key(key).preventDefault).not.toHaveBeenCalled()
    demo.expectFrame(`${screen === 'd' ? 'details' : 'settings'}:0:1`)
  })
  it.each(['b', 'd', 'e'])('announces snapshot reload on screen %s', screen => {
    const demo = mount()
    demo.key(screen)
    expect(demo.key('r').preventDefault).toHaveBeenCalledOnce()
    expect(demo.announcement()).toBe('Sample snapshot reloaded. These are captured demo readings, not a live fleet.')
  })
  it('executes native button and select handlers with matching frames and pressed states', () => {
    const demo = mount()
    demo.select(3)
    demo.click('Pause space')
    demo.expectFrame('fleet:name:1:3')
    demo.click('Resume space')
    demo.click('Sort: name s')
    demo.expectFrame('fleet:hashrate:0:3')
    demo.click('Details d')
    expect(demo.pressed('Details d')).toBe(true)
    demo.click('3 Hardware')
    demo.expectFrame('details:3:3')
    demo.click('Settings e')
    expect(demo.pressed('Settings e')).toBe(true)
    demo.click('4 Display')
    demo.expectFrame('settings:3:4')
    demo.click('Logo l')
    demo.expectFrame('logo')
    demo.click('Logo l')
    demo.expectFrame('fleet:hashrate:0:3')
    demo.click('Details d')
    demo.click('Fleet')
    expect(demo.pressed('Fleet')).toBe(true)
    demo.click('Quit q')
    expect(demo.onExit).toHaveBeenCalledOnce()
  })
  it('resets scroll only when a screen, miner or selected page changes', () => {
    const demo = mount()
    demo.viewport.scrollTop = 90
    demo.key(' ')
    expect(demo.viewport.scrollTop).toBe(90)
    demo.select(1)
    expect(demo.viewport.scrollTop).toBe(0)
    demo.key('e')
    demo.viewport.scrollTop = 90
    demo.key('2')
    expect(demo.viewport.scrollTop).toBe(0)
    expect(demo.viewport.focus).toHaveBeenCalledOnce()
  })
})
