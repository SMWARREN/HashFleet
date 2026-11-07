import { describe, expect, it } from 'vitest'
import { chartRanges, chartValues, demoMiners, energyEstimate, summarizeFleet } from './demo'

describe('sample fleet boundaries', () => {
  it('matches the native three-ASIC DemoFleet with reserved hostnames', () => {
    expect(demoMiners).toHaveLength(3)
    expect(demoMiners.filter(miner => miner.algorithm === 'SHA-256')).toHaveLength(3)
    expect(demoMiners.every(miner => miner.host.endsWith('.invalid'))).toBe(true)
    expect(new Set(demoMiners.map(miner => miner.id)).size).toBe(3)
  })
  it('never adds RandomX rates to the SHA-256 aggregate', () => {
    const summary = summarizeFleet(demoMiners)
    expect(summary.sha256).toBeCloseTo(3.02)
    expect(summary.randomX).toBe(0)
    expect(summary.reportedPower).toBeCloseTo(50.8)
    expect(summary.missingPower).toBe(0)
  })
  it('keeps the native ASIC readings complete rather than fabricating unavailable values', () => {
    expect(demoMiners.every(miner => miner.power !== null)).toBe(true)
    expect(demoMiners.every(miner => miner.temperature !== null)).toBe(true)
  })
  it('handles an empty fleet', () => {
    expect(summarizeFleet([])).toEqual({ sha256: 0, randomX: 0, reportedPower: 0, missingPower: 0, shares: 0 })
  })
  it('has distinct deterministic samples for each illustrative chart range', () => {
    for (const range of chartRanges) {
      expect(chartValues(range)).toHaveLength(32)
      expect(chartValues(range).every(Number.isFinite)).toBe(true)
    }
    expect(chartValues('15m')).not.toEqual(chartValues('24h'))
  })
  it('estimates a day of ASIC energy, not mining profit', () => {
    expect(energyEstimate(0.12)).toBeCloseTo(0.146304)
    expect(energyEstimate(0)).toBe(0)
    expect(energyEstimate(-1)).toBe(0)
  })
})
