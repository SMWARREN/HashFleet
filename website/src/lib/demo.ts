export type DemoMiner = {
  id: string
  name: string
  model: string
  host: string
  algorithm: 'SHA-256' | 'RandomX'
  rate: number
  unit: 'TH/s' | 'kH/s'
  temperature: number | null
  power: number | null
  shares: number
  uptime: string
}

// The same fictional browser-only examples used by the native DemoFleet fixture.
// The reserved .invalid hosts keep this preview disconnected from real hardware.
export const demoMiners: DemoMiner[] = [
  { id: 'workshop-gamma', name: 'Workshop Gamma', model: 'Bitaxe · BM1370', host: 'gamma-demo.invalid', algorithm: 'SHA-256', rate: 1.218, unit: 'TH/s', temperature: 53, power: 19.2, shares: 12486, uptime: '2d 20h' },
  { id: 'office-gamma', name: 'Office Gamma', model: 'Bitaxe · BM1370', host: 'office-demo.invalid', algorithm: 'SHA-256', rate: 1.164, unit: 'TH/s', temperature: 56, power: 19.2, shares: 13206, uptime: '2d 20h' },
  { id: 'little-supra', name: 'Little Supra', model: 'Bitaxe · BM1368', host: 'supra-demo.invalid', algorithm: 'SHA-256', rate: 0.638, unit: 'TH/s', temperature: 59, power: 12.4, shares: 13926, uptime: '2d 20h' },
]

export function summarizeFleet(miners: DemoMiner[]) {
  return {
    sha256: miners.filter(miner => miner.algorithm === 'SHA-256').reduce((sum, miner) => sum + miner.rate, 0),
    randomX: miners.filter(miner => miner.algorithm === 'RandomX').reduce((sum, miner) => sum + miner.rate, 0),
    reportedPower: miners.reduce((sum, miner) => sum + (miner.power ?? 0), 0),
    missingPower: miners.filter(miner => miner.power === null).length,
    shares: miners.reduce((sum, miner) => sum + miner.shares, 0),
  }
}

export type ChartRange = '15m' | '1h' | '24h'
export const chartRanges: ChartRange[] = ['15m', '1h', '24h']

export function chartValues(range: ChartRange): number[] {
  const patterns = {
    '15m': [65, 62, 67, 64, 69, 66, 68, 71, 68, 73, 69, 75, 72, 74, 70, 77, 74, 79, 75, 78, 75, 81, 77, 80, 78, 84, 80, 83, 81, 86, 83, 87],
    '1h': [45, 51, 48, 56, 52, 58, 55, 62, 59, 57, 64, 60, 66, 63, 65, 68, 63, 70, 66, 73, 69, 76, 72, 75, 70, 79, 75, 83, 79, 86, 83, 87],
    '24h': [29, 45, 40, 48, 43, 58, 48, 51, 49, 65, 62, 51, 68, 61, 71, 66, 59, 75, 70, 68, 74, 77, 69, 81, 72, 76, 82, 78, 86, 80, 84, 87],
  }
  return patterns[range]
}

export function energyEstimate(rate: number, watts = 50.8) {
  return Math.max(0, rate) * watts / 1000 * 24
}
