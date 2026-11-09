import captures from './watch-captures.json'

export type WatchScreenId = 'watch-fleet' | 'watch-miner' | 'watch-status' | 'watch-discovery' | 'watch-add'
export type WatchScreen = {
  id: WatchScreenId
  label: string
  description: string
  transcript: string
  target?: { id: WatchScreenId, label: string, x: number, y: number, width: number, height: number }
}

export const watchScreens: WatchScreen[] = [
  { id: 'watch-fleet', label: 'Fleet at a glance', description: 'The real Watch app in demo mode. A compact fleet snapshot, with the sample-data notice kept visible.', transcript: 'Hash Fleet. Demo data. No miners are contacted. 3.94 TH/s. 3 of 3 current. 62.9 W. These are captured fictional readings, not live measurements. The time shown is the original capture time.' },
  { id: 'watch-miner', label: 'A closer look', description: 'Inspect a captured miner detail screen. The app keeps the observation time beside the freshness label.', transcript: 'Demo Gamma. Current. Observed just now. November 3, 2026 at 8:08 PM, the original captured device-local time. Readings. Hashrate 1.02 TH/s. The capture is not being refreshed by this website.', target: { id: 'watch-fleet', label: 'Back to the captured fleet', x: 4, y: 4, width: 22, height: 18 } },
  { id: 'watch-status', label: 'More miner details', description: 'A second native capture, taken farther down the same miner detail screen. Mining state and its example local address stay readable.', transcript: 'Demo Gamma, lower detail screen. Mining: Running. Address: http://192.168.0.101. This address belongs to the native demo fixture. The website never requests it.', target: { id: 'watch-fleet', label: 'Back to the captured fleet', x: 4, y: 4, width: 22, height: 18 } },
  { id: 'watch-discovery', label: 'Local setup', description: 'The native empty-state capture explains what happens when no compatible miners are found. The browser does not run a network scan.', transcript: 'Hash Fleet. No compatible miners found. Check the Watch’s Wi-Fi and that your miners are reachable, then scan again. Add miner. Only the outlined Add miner area opens the next captured screen. No scan is run here.', target: { id: 'watch-add', label: 'Open the captured Add miner screen', x: 4, y: 84, width: 92, height: 15 } },
  { id: 'watch-add', label: 'Add by local address', description: 'The real Watch setup screen, without an iPhone. The pictured form is a capture, not an input connected to your network.', transcript: 'Add miner. Use the miner’s Wi-Fi address only on your home network. Only local addresses work. Add miner is disabled while the captured form is empty. No address is stored or contacted by this walkthrough.', target: { id: 'watch-discovery', label: 'Back to the captured local setup', x: 4, y: 4, width: 22, height: 18 } },
]

export function watchCaptureFor(id: WatchScreenId) {
  const capture = captures.captures.find(item => item.id === id)
  if (!capture) throw new Error(`Missing Watch capture: ${id}`)
  return capture
}
