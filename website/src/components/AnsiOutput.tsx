import { useMemo } from 'react'
import { ansiRuns } from '../lib/ansi'

export default function AnsiOutput({ value }: { value: string }) {
  const runs = useMemo(() => ansiRuns(value), [value])
  return <>{runs.map(({ text, ...style }, index) => <span key={index} style={style}>
    {text.split(/(▀+|▄+)/).map((part, partIndex) => {
      if (!/^[▀▄]+$/.test(part)) return part
      const foreground = style.color ?? 'currentColor'
      const background = style.backgroundColor ?? 'transparent'
      const [top, bottom] = part[0] === '▀' ? [foreground, background] : [background, foreground]
      return <span className="ansi-pixels" key={partIndex} style={{ backgroundImage: `linear-gradient(to bottom, ${top} 50%, ${bottom} 50%)` }}>{part}</span>
    })}
  </span>)}</>
}
