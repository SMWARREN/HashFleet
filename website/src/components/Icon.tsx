import type { CSSProperties } from 'react'

export type IconName = 'arrow' | 'arrow-up' | 'mac' | 'phone' | 'watch' | 'terminal' | 'grid' | 'bolt' | 'chart' | 'shield' | 'code' | 'wifi' | 'check' | 'chevron' | 'close' | 'menu' | 'settings' | 'globe' | 'cpu' | 'thermometer' | 'copy' | 'plus' | 'search' | 'bell' | 'external' | 'sun' | 'moon' | 'download' | 'info'
const paths: Record<IconName, string> = {
  arrow: 'M4 12h15m-6-6 6 6-6 6',
  'arrow-up': 'M5 19 19 5M5 5h14v14',
  mac: 'M3 4h18v12H3zM8 21h8M12 16v5',
  phone: 'M7 2h10a1 1 0 0 1 1 1v18a1 1 0 0 1-1 1H7a1 1 0 0 1-1-1V3a1 1 0 0 1 1-1Zm3 17h4',
  watch: 'M8 6V2h8v4M8 18v4h8v-4M8 6h8a3 3 0 0 1 3 3v6a3 3 0 0 1-3 3H8a3 3 0 0 1-3-3V9a3 3 0 0 1 3-3Zm4 3v3l2 1m5-4h2',
  terminal: 'M4 6l6 6-6 6m9 0h7',
  grid: 'M3 3h7v7H3zM14 3h7v7h-7zM3 14h7v7H3zM14 14h7v7h-7z',
  bolt: 'm13 2-9 12h7l-1 8 10-13h-8z',
  chart: 'M3 3v18h18M7 15l4-5 4 3 5-7',
  shield: 'M12 2 3 6v6c0 5 9 10 9 10s9-5 9-10V6l-9-4Zm-4 10 3 3 5-6',
  code: 'm8 5-6 7 6 7m8-14 6 7-6 7M14 3l-4 18',
  wifi: 'M2 8a16 16 0 0 1 20 0M5 12a11 11 0 0 1 14 0m-10 4a5 5 0 0 1 6 0M12 20h.01',
  check: 'm5 12 4 4L19 6',
  chevron: 'm9 5 7 7-7 7',
  close: 'm6 6 12 12M6 18 18 6',
  menu: 'M4 6h16M4 12h16M4 18h16',
  settings: 'M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8Zm0-6v3m0 14v3M2 12h3m14 0h3M5 5l2 2m10 10 2 2M5 19l2-2M17 7l2-2',
  globe: 'M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0ZM3 12h18M12 3c5 6 5 12 0 18-5-6-5-12 0-18Z',
  cpu: 'M6 6h12v12H6zM9 9h6v6H9zM9 2v4m6-4v4m-6 12v4m6-4v4M2 9h4m-4 6h4m12-6h4m-4 6h4',
  thermometer: 'M9 14V5a3 3 0 0 1 6 0v9a5 5 0 1 1-6 0Zm3-5v9',
  copy: 'M9 9h12v12H9zM5 15H3V3h12v2',
  plus: 'M12 5v14M5 12h14',
  search: 'M16 10a6 6 0 1 1-12 0 6 6 0 0 1 12 0Zm-1 5 6 6',
  bell: 'M5 17h14l-2-4V8a5 5 0 0 0-10 0v5l-2 4Zm5 3h4',
  external: 'M14 3h7v7m0-7L10 14M10 3H3v18h18v-7',
  sun: 'M16 12a4 4 0 1 1-8 0 4 4 0 0 1 8 0ZM12 2v2m0 16v2M2 12h2m16 0h2M5 5l1 1m12 12 1 1M5 19l1-1M18 6l1-1',
  moon: 'M21 13A9 9 0 0 1 11 3a9 9 0 1 0 10 10Z',
  download: 'M12 3v12m-5-5 5 5 5-5M4 16v5h16v-5',
  info: 'M12 10v7m0-11h.01M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z',
}

export default function Icon({ name, size = 20, style, className = '' }: { name: IconName, size?: number, style?: CSSProperties, className?: string }) {
  return <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.65" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" className={className} style={style}><path d={paths[name]} /></svg>
}
