# Mining Achievements & History Proposal

## Current State

We're already tracking and storing:

**Block Found Events**
- Stored in: `blockObservations: [String: MinerBlockFoundObservation]`
- Persisted to: `app.hashfleet.block-observations.v1`
- Detected in: `FleetStore+Monitoring.swift` lines 163-187
- Contains: device, previous/current block height, timestamp

**Best Share Events**
- Stored in: `bestShareObservations: [String: MinerBestShareObservation]`
- Persisted to: `app.hashfleet.best-share-observations.v1`
- Detected in: `FleetStore+Monitoring.swift` lines 148-161
- Contains: device, previous/current best difficulty, timestamp

**Current Usage**
- In-app celebration banners (FleetBestShareCelebrationBanner, FleetBlockFoundCelebrationBanner)
- Push notifications (if enabled)
- Session-only display (cleared on app restart)

## What's Missing

Users can't see:
1. **Historical achievements** - "When did I find my last block?"
2. **All-time stats** - "How many blocks have I found total?"
3. **Per-miner records** - "Which miner has the best share?"
4. **Timeline view** - "Show me all my milestones this month"

## Proposal: Achievements Screen

### Location
New tab or section in Dashboard showing:

### Achievement Categories

**1. Blocks Found**
- Total count across all miners
- Last block found (timestamp, which miner, block height)
- Blocks per miner breakdown
- Timeline view (all blocks with dates)

**2. Best Shares**
- Current best difficulty across fleet
- Per-miner best shares
- Personal records timeline
- Difficulty progression chart

**3. Milestones**
- First block found
- Total uptime across fleet
- Longest running streak
- Temperature records (highest safely managed)

### Data Structure Needed

Currently we only keep **latest** observation per miner. To show history we need:

```swift
// Instead of: [String: MinerBlockFoundObservation]
// Store: [String: [MinerBlockFoundEvent]]

struct MinerAchievementHistory: Codable {
    var blockEvents: [MinerBlockFoundEvent] = []
    var bestShareEvents: [MinerBestShareEvent] = []
    var temperatureAlerts: [MinerTemperatureAlertEvent] = []
    
    // Computed properties
    var totalBlocks: Int { blockEvents.count }
    var lastBlock: MinerBlockFoundEvent? { blockEvents.last }
    var allTimeBestShare: MinerBestShareEvent? { 
        bestShareEvents.max { $0.difficulty < $1.difficulty }
    }
}
```

### Storage Key
`app.hashfleet.achievements.v1` - append-only event log

### Privacy Considerations
- Stored locally only (already the case)
- Export includes achievements in CSV/PDF
- User can clear history

### UI Mockup

```
┌─────────────────────────────────┐
│ 🏆 Mining Achievements          │
├─────────────────────────────────┤
│ Blocks Found                    │
│ ├─ Total: 3                     │
│ ├─ Last: 2 days ago             │
│ │  Workshop Gamma · #850234     │
│ └─ View Timeline →              │
│                                 │
│ Best Shares                     │
│ ├─ Fleet Record: 18.4G          │
│ │  Workshop Gamma               │
│ ├─ Office Gamma: 9.2M           │
│ └─ Little Supra: 2.1M           │
│                                 │
│ Fleet Stats                     │
│ ├─ Total Runtime: 247 days      │
│ ├─ Active Since: Jan 15, 2024   │
│ └─ Miners Tracked: 3            │
└─────────────────────────────────┘
```

## Implementation Phases

**Phase 1: Data Collection** ✅ (Already done!)
- Events are detected and stored
- Persisted to UserDefaults

**Phase 2: Append History (Next)**
- Change from "latest only" to "append events"
- Add achievement history structure
- Migrate existing observations

**Phase 3: Display UI**
- Achievements tab/section
- Timeline views
- Charts/graphs

**Phase 4: Export Enhancement**
- Add achievements section to PDF reports
- Include in CSV export
- Share individual milestones

## Questions

1. **Retention limit?** - Keep all events or cap at X per miner?
2. **Celebrations** - Keep current banner behavior or add to achievements screen?
3. **Notifications** - Link "View Achievement" from notification to achievements screen?

## Export Format Preview

**CSV Addition:**
```csv
Section,Metric,Value,Timestamp,Miner
Achievement,Block Found,850234,2024-01-15 14:32:10,Workshop Gamma
Achievement,Best Share,18.4G,2024-01-20 08:15:42,Workshop Gamma
```

**PDF Addition:**
New section after fleet summary showing top achievements and recent milestones.
