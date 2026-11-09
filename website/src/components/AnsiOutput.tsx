import { useMemo } from 'react'
import { ansiRuns } from '../lib/ansi'

// Repeated identical content has no separate identity. Count only its occurrences,
// so inserting unrelated runs or pixel groups does not change existing keys.
function contentKey(content: string, occurrences: Map<string, number>): string {
  const occurrence = occurrences.get(content) ?? 0
  occurrences.set(content, occurrence + 1)
  return JSON.stringify([content, occurrence])
}

export default function AnsiOutput({ value }: Readonly<{ value: string }>) {
  const runs = useMemo(() => ansiRuns(value), [value])
  const runOccurrences = new Map<string, number>()
  return <>{runs.map(({ text, ...style }) => {
    const key = contentKey(JSON.stringify([text, style.color, style.backgroundColor, style.fontWeight, style.opacity]), runOccurrences)
    const pixelOccurrences = new Map<string, number>()
    return <span key={key} style={style}>
      {text.split(/(▀+|▄+)/).map(part => {
        if (!/^[▀▄]+$/.test(part)) return part
        const foreground = style.color ?? 'currentColor'
        const background = style.backgroundColor ?? 'transparent'
        const [top, bottom] = part.startsWith('▀') ? [foreground, background] : [background, foreground]
        return <span className="ansi-pixels" key={contentKey(part, pixelOccurrences)} style={{ backgroundImage: `linear-gradient(to bottom, ${top} 50%, ${bottom} 50%)` }}>{part}</span>
      })}
    </span>
  })}</>
}
