import { useId, useState } from 'react'
import { chartValues } from '../lib/demo'
import type { ChartRange } from '../lib/demo'

export default function HashChart({ range = '1h', mini = false }: { range?: ChartRange, mini?: boolean }) {
  const id = useId().replace(/:/g, '')
  const values = chartValues(range)
  const [hovered, setHovered] = useState<number | null>(null)
  const points = values.map((value, index) => [index / (values.length - 1) * 600, 155 - value * 1.32])
  const line = points.map(([x, y], index) => `${index === 0 ? 'M' : 'L'}${x.toFixed(2)},${y.toFixed(2)}`).join(' ')
  return <div className={`hash-chart ${mini ? 'hash-chart--mini' : ''}`}>
    <div className="chart-plot">
      {!mini && <div className="chart-y-axis" aria-hidden="true"><span>4</span><span>2</span><span>0</span></div>}
      <svg viewBox="0 0 600 170" preserveAspectRatio="none" role="img" aria-label={`Illustrative ${range} sample hashrate chart, not recorded history`} onMouseLeave={() => setHovered(null)} onMouseMove={event => {
        const rect = event.currentTarget.getBoundingClientRect()
        setHovered(Math.max(0, Math.min(values.length - 1, Math.round((event.clientX - rect.left) / rect.width * (values.length - 1)))))
      }}>
        <defs><linearGradient id={`chart-${id}`} x1="0" y1="0" x2="0" y2="1"><stop offset="0%" stopColor="var(--chart-accent, #f5ac26)" stopOpacity="0.20" /><stop offset="100%" stopColor="var(--chart-accent, #f5ac26)" stopOpacity="0" /></linearGradient></defs>
        {[35, 80, 125].map(y => <line key={y} x1="0" x2="600" y1={y} y2={y} stroke="currentColor" strokeOpacity="0.08" strokeDasharray="3 6" />)}
        <path d={`${line} L600,170 L0,170 Z`} fill={`url(#chart-${id})`} />
        <path d={line} fill="none" stroke="var(--chart-accent, #f5ac26)" strokeWidth="2.5" vectorEffect="non-scaling-stroke" strokeLinejoin="round" />
        {hovered !== null && <g><line x1={points[hovered][0]} x2={points[hovered][0]} y1="0" y2="170" stroke="var(--chart-accent, #f5ac26)" strokeOpacity="0.3" /><circle cx={points[hovered][0]} cy={points[hovered][1]} r="4" fill="var(--chart-accent, #f5ac26)" /></g>}
      </svg>
    </div>
    {!mini && <div className="chart-axis"><span>{range === '24h' ? '24 hours ago' : range === '1h' ? '60 minutes ago' : '15 minutes ago'}</span><span>Illustrative trend · TH/s</span><span>Now</span></div>}
  </div>
}
