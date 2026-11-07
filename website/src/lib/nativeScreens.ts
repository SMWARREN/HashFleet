import captures from './native-captures.json'

export type NativePlatform = 'mac' | 'iphone'
export type CaptureTarget = { target: string, label: string, x: number, y: number, width: number, height: number }
export type NativeScreen = {
  id: string
  platform: NativePlatform
  label: string
  description: string
  transcript: string
  targets: CaptureTarget[]
}

const target = (id: string, label: string, x: number, y: number, width: number, height: number): CaptureTarget => ({ target: id, label, x, y, width, height })
const macNavigation = [
  target('mac-overview', 'Overview', 1.2, 12.2, 19, 4),
  target('mac-workshop', 'Workshop Gamma', 1.2, 20, 19, 4.8),
  target('mac-office', 'Office Gamma', 1.2, 25, 19, 4.8),
  target('mac-supra', 'Little Supra', 1.2, 30, 19, 4.8),
  target('mac-network', 'Network insights', 1.2, 39, 19, 3.8),
  target('mac-energy', 'Energy & Efficiency', 1.2, 43, 19, 3.8),
  target('mac-achievements', 'Achievements', 1.2, 47, 19, 3.8),
  target('mac-reports', 'Reports & Export', 1.2, 51, 19, 3.8),
  target('mac-backup', 'Backup & Restore', 1.2, 59, 19, 3.8),
  target('mac-settings', 'App settings', 1.2, 63, 19, 3.8),
  target('mac-about', 'About Hash Fleet', 1.2, 67, 19, 3.8),
]
const phoneGear = target('ios-current', 'Open the captured gear menu', 61, 7.1, 18, 5.1)
const phoneDone = target('ios-fleet', 'Done, return to the captured fleet', 78, 8.5, 18, 5.8)

export const nativeScreens: NativeScreen[] = [
  {
    id: 'mac-overview', platform: 'mac', label: 'Overview',
    description: 'The actual Mac workspace: a fleet sidebar, one sample hashrate card, the native 1m trend, solo odds, and expanded miner cards.',
    transcript: 'Hash Fleet. Demo · simulated readings. Sample data · no changes are sent to your hardware. SAMPLE FLEET HASHRATE. SHA-256. 3.02 TH/s. 3 sample miners. 51 W. SIMULATED. Hashrate trend, 1m. Solo odds. Your miners, 3 of 3 online. Workshop Gamma, 1.22 TH/s. Office Gamma, 1.16 TH/s. Little Supra, 638 GH/s. Sample. Best 18.40G. Session best 9.20M. The sidebar lists the three miners individually, Analytics & Insights, and Management.',
    targets: macNavigation,
  },
  ...([
    ['mac-workshop', 'Workshop Gamma', '1.22 TH/s', 'gamma-demo.invalid', '53°C'],
    ['mac-office', 'Office Gamma', '1.16 TH/s', 'office-demo.invalid', '56°C'],
    ['mac-supra', 'Little Supra', '638 GH/s', 'supra-demo.invalid', '59°C'],
  ] as const).map(([id, label, rate, host, temperature]): NativeScreen => ({
    id, platform: 'mac', label,
    description: `${label} in the actual Mac detail view, including the native sample summary, retained readings, and hardware-specific availability labels.`,
    transcript: `${label}. DEMO · READ ONLY. ${host}. Sample hashrate ${rate}. Temperature ${temperature}. Retained sample snapshot and simulated history, not live readings. Pool and per-ASIC telemetry are labeled unavailable when the sample firmware does not report them. No browser device controls are executed.`,
    targets: macNavigation,
  })),
  {
    id: 'mac-network', platform: 'mac', label: 'Network insights',
    description: 'The native network screen, not a substitute text-only dashboard. Its demo state does not fetch public services.',
    transcript: 'Network insights. Beyond your fleet. Sample network and pool data. No internet requests. Demo · not live. Load sample data. Connected pool stats. Look up my CKPool statistics. Pool-reported network data. BTC · USD: $80,000, sample data, not live. Network difficulty & hashrate: estimated network hashrate 1000 EH/s, difficulty 140T, sample data, not live. Latest block and Mempool cards retain their sample and non-guarantee labels. Public network data and remote services are not contacted by this walkthrough.', targets: macNavigation,
  },
  {
    id: 'mac-energy', platform: 'mac', label: 'Energy & Efficiency',
    description: 'The actual Energy & Efficiency screen preserves native freshness and missing-data warnings. No invented cost slider or guessed wall-power readings.',
    transcript: 'Energy & Efficiency. Native power and energy cards, freshness labels, stored history, and per-miner information. Aged sample readings remain visibly unavailable for fresh consumption estimates. Estimates are not measured wall power or profit forecasts.', targets: macNavigation,
  },
  {
    id: 'mac-achievements', platform: 'mac', label: 'Achievements',
    description: 'The actual achievements view keeps share records separate from solved-block claims.',
    transcript: 'Achievements. Demo. Native best-share records and milestones. A best share is not proof of a solved block. The sample fleet has zero blocks found.', targets: macNavigation,
  },
  {
    id: 'mac-reports', platform: 'mac', label: 'Reports & Export',
    description: 'The real native report screen. Export controls shown in the capture are not browser downloads or uploads.',
    transcript: 'Fleet report. Read-only fleet summary. Native report preview and sharing controls. No report is generated, stored, uploaded, or exported by this captured-screen walkthrough.', targets: macNavigation,
  },
  {
    id: 'mac-backup', platform: 'mac', label: 'Backup & Restore',
    description: 'The actual local backup screen, with no browser file access or pretend cloud account.',
    transcript: 'Backup & Restore. Native local export and restore workflow. Captured controls are not connected to browser files or a storage service.', targets: macNavigation,
  },
  {
    id: 'mac-settings', platform: 'mac', label: 'App settings',
    description: 'The real App settings categories and native form layout, not the old website’s invented preferences page.',
    transcript: 'App settings. Make Fleet yours. Your readings, your alerts, your way. Notifications and banners: Alert choices and record popups, right here in App settings. Your fleet. Fleet: Appearance, miner order and live readings. Looking for miner controls? Open a miner in Fleet. Across iOS: Widgets, Live Activity, Shortcuts & Controls. Fleet tools: Mining achievements, Temperature alerts, Power alerts, Electricity estimates. The walkthrough does not request permissions, save preferences, enroll notifications, or change miners.', targets: macNavigation,
  },
  {
    id: 'mac-about', platform: 'mac', label: 'About Hash Fleet',
    description: 'The actual native About screen with the same artwork and local-first explanation as the app.',
    transcript: 'About Hash Fleet. Your hash. Your hardware. A native, open-source companion for the independent miner. Direct connection to your miners. No Hash Fleet account or analytics. Miner addresses stay on this device. Use a trusted VPN and never expose a miner API directly to the internet.', targets: macNavigation,
  },
  {
    id: 'ios-fleet', platform: 'iphone', label: 'Fleet overview',
    description: 'The real iPhone home screen. Hash Fleet header, gear menu and add control, demo notices, one summary card, a 1m trend, and solo odds. There is no bottom tab bar.',
    transcript: 'Hash Fleet. Gear menu and Add miner. Demo · simulated readings. Sample data · no changes are sent to your hardware. SAMPLE FLEET HASHRATE. SHA-256. 3.02 TH/s. 3 sample miners. 51 W. SIMULATED. Hashrate trend, 1m. Solo odds. BTC, 3 miners, demo assumptions. Your miners, 3 of 3 online. Little Supra, BM1368. No Fleet, Settings, About bottom tabs.',
    targets: [phoneGear],
  },
  {
    id: 'ios-current', platform: 'iphone', label: 'Gear menu',
    description: 'This is how the real iPhone app reaches App settings and About. The website no longer invents bottom tabs.',
    transcript: 'Native gear menu: App settings. Refresh fleet. About. Feature tour. Switch to light mode. Only the outlined captured navigation links are interactive here.',
    targets: [target('ios-settings', 'App settings', 34, 7.2, 62, 6.5), target('ios-about', 'About', 34, 17.7, 62, 6.4)],
  },
  {
    id: 'ios-settings', platform: 'iphone', label: 'App settings',
    description: 'The actual native sheet has Notifications and banners, Your fleet, and Across iOS sections. Use Fleet to inspect the real preferences.',
    transcript: 'App settings. Done. Make Fleet yours. Your readings, your alerts, your way. Notifications and banners: Alert choices and record popups, right here in App settings. Your fleet. Fleet: Appearance, miner order and live readings. Looking for miner controls? Open a miner in Fleet. Across iOS: Widgets and Live Activity. These are captured native settings, not active browser switches.',
    targets: [phoneDone, target('ios-fleet-settings', 'Fleet preferences', 0, 58.5, 100, 9)],
  },
  {
    id: 'ios-fleet-settings', platform: 'iphone', label: 'Fleet preferences',
    description: 'The real form includes miner order, color mode, compact miner cards, live readings, and local telemetry storage. No unrelated global Restart button.',
    transcript: 'Preferences. Miner order: Sort by Name, Direction Ascending. Appearance: Color mode Dark, Compact miner cards off. These preferences never change miner settings. Live readings: Realtime miner readings on. This does not enable continuous background monitoring. Telemetry storage: Store telemetry history on, Keep data for 30 days.',
    targets: [target('ios-settings', 'Back to App settings', 4, 8.8, 11, 5.3)],
  },
  {
    id: 'ios-miners', platform: 'iphone', label: 'Miner cards (scrolled)',
    description: 'A real scrolled fleet capture: expanded miner cards with best shares, session best, temperature, reported power, and fan readings. The top card is partially offscreen, as captured.',
    transcript: 'Expanded Office Gamma card, 1.16 TH/s, 56°C, 19.2 W, fan 65%. Workshop Gamma, BM1370, Sample, 1.22 TH/s, Best 18.40G, Session best 9.20M, 53°C, 19.2 W, fan 65%. Fleet tools: Network insights, Energy, Achievements, Reports, Backup. Show me around.',
    targets: [phoneGear, target('ios-office', 'Inspect Office Gamma', 3, 13.4, 77, 12)],
  },
  {
    id: 'ios-office', platform: 'iphone', label: 'Office Gamma detail',
    description: 'The real native miner detail, including its exact sample summary and availability notices. The retained timestamp is part of the capture, not current telemetry.',
    transcript: 'Office Gamma. DEMO · READ ONLY. office-demo.invalid. Sample hashrate 1.16 TH/s. 2× BM1370. Accepted 13,206. Rejected 3. Rejected share rate 0.02%. Last known ASIC hashrate. Per-ASIC domain telemetry is not reported by this firmware. Pool connection: Primary pool selected. Transport not reported. Simulated hashrate history, 1m.',
    targets: [target('ios-miners', 'Back to miner cards', 4, 7, 11, 5.1)],
  },
  {
    id: 'ios-about', platform: 'iphone', label: 'About Hash Fleet',
    description: 'The actual iPhone About sheet. The original native artwork and privacy explanation stay intact.',
    transcript: 'About Hash Fleet. Done. Your hash. Your hardware. A native, open-source companion for the independent miner. Built for Bitaxe and other open-source devices running ESP-Miner. Private by design. Direct connection to your miners. No Hash Fleet account or analytics. Miner addresses stay on this device. Use a trusted VPN. Never expose its API directly to the internet.',
    targets: [phoneDone],
  },
]

export function captureFor(id: string) {
  const capture = captures.captures.find(item => item.id === id)
  if (!capture) throw new Error(`Missing native capture: ${id}`)
  return capture
}

export function screensFor(platform: NativePlatform) {
  return nativeScreens.filter(screen => screen.platform === platform)
}
