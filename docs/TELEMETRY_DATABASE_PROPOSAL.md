# Miner Telemetry Database Proposal

## Current Limitations

**What We Store Now:**
- ✅ Last 360 hashrate points (in-memory only, lost on app close)
- ✅ Latest snapshot per miner (session + cached last reading)
- ✅ Latest block/share observations only
- ❌ Historical telemetry (temp, power, fan speed over time)
- ❌ Long-term hashrate trends (beyond current session)
- ❌ Uptime/downtime events
- ❌ Pool switches and their timestamps

**What We're Polling But Not Saving:**
Every 30 seconds per miner we get:
- Hashrate (GH/s)
- Power consumption (watts)
- Chip temperature (°C)
- VR temperature (°C)
- Fan speed (%) & RPM
- Accepted/rejected shares
- Pool info
- Uptime
- Voltage, frequency
- Best difficulty

**Currently this data vanishes** when you close the app or restart your phone.

## Proposal: SQLite Telemetry Database

### Schema

```sql
-- Main telemetry readings table
CREATE TABLE miner_readings (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    miner_id TEXT NOT NULL,           -- UUID
    timestamp INTEGER NOT NULL,        -- Unix timestamp
    hashrate REAL,                     -- GH/s
    power REAL,                        -- watts
    temp REAL,                         -- °C
    vr_temp REAL,                      -- °C
    fan_speed INTEGER,                 -- %
    fan_rpm INTEGER,
    voltage INTEGER,                   -- mV
    frequency INTEGER,                 -- MHz
    core_voltage INTEGER,              -- mV
    shares_accepted INTEGER,
    shares_rejected INTEGER,
    uptime_seconds INTEGER,
    active_pool_index INTEGER,
    is_fallback_pool BOOLEAN,
    
    -- Performance indices
    INDEX idx_miner_time (miner_id, timestamp),
    INDEX idx_timestamp (timestamp)
);

-- Achievement events (blocks, best shares)
CREATE TABLE achievement_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    miner_id TEXT NOT NULL,
    event_type TEXT NOT NULL,         -- 'block_found', 'best_share', 'temperature_alert'
    timestamp INTEGER NOT NULL,
    
    -- Event-specific data (JSON)
    block_height INTEGER,              -- for block_found
    difficulty TEXT,                   -- for best_share
    alert_threshold REAL,              -- for temperature_alert
    metadata TEXT,                     -- JSON for extensibility
    
    INDEX idx_miner_events (miner_id, event_type, timestamp)
);

-- Uptime/downtime tracking
CREATE TABLE connectivity_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    miner_id TEXT NOT NULL,
    timestamp INTEGER NOT NULL,
    event_type TEXT NOT NULL,         -- 'online', 'offline', 'error'
    error_message TEXT,
    
    INDEX idx_miner_connectivity (miner_id, timestamp)
);

-- Pool changes
CREATE TABLE pool_switches (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    miner_id TEXT NOT NULL,
    timestamp INTEGER NOT NULL,
    from_pool TEXT,
    to_pool TEXT,
    pool_index INTEGER,
    is_fallback BOOLEAN,
    
    INDEX idx_miner_pool_switches (miner_id, timestamp)
);
```

### Storage Location
- iOS: Application Support directory
- Size limit: 100MB initial cap with pruning
- Retention: Default 30 days, configurable (7/30/90/365/forever)

### Data Retention Policies

**Default Policy: 30 Days**
```swift
enum TelemetryRetention: String, CaseIterable {
    case week = "7 days"
    case month = "30 days" // default
    case quarter = "90 days"
    case year = "365 days"
    case forever = "Keep all data"
}
```

**Auto-pruning:**
- Runs on app launch
- Deletes readings older than retention period
- Always keeps achievement events (or separate retention policy)
- Vacuum database to reclaim space

### Write Strategy

**Sampling Rate:**
- **High frequency (live monitoring):** Every reading (every 30s per miner)
- **Medium (HTTP only):** Every poll (every 5min per miner)
- **Low (battery saver):** Every 15min

**Batch Writes:**
```swift
// Buffer 10 readings in memory, flush to DB
// Reduces write amplification on SQLite
var pendingWrites: [MinerReading] = []

func recordReading(_ reading: MinerReading) {
    pendingWrites.append(reading)
    if pendingWrites.count >= 10 {
        flushToDatabase()
    }
}
```

**Background Writes:**
- Use background task to flush on app backgrounding
- Ensure data survives force-quit

## What This Enables

### 1. Historical Charts
Show hashrate/temp/power over any time range:
- Last 24 hours (already have in-memory)
- Last 7 days ⭐ NEW
- Last 30 days ⭐ NEW
- Last 3 months ⭐ NEW
- All time ⭐ NEW

### 2. Advanced Analytics
- Average hashrate by hour of day (find patterns)
- Temperature trends over time
- Power efficiency over time
- Pool performance comparison (uptime, accepted rate)

### 3. Detailed Reports
Enhanced PDF/CSV exports with:
- Custom date ranges
- All tracked metrics over time
- Downtime/uptime summary
- Achievement timeline

### 4. Downtime Tracking
- "Workshop Gamma was offline for 2h 15m on Jan 20"
- Uptime percentage per miner
- Connection reliability metrics

### 5. Pool Performance
- Time spent on each pool
- Pool-specific hashrate/rejection rates
- Automatic pool switch detection

## Privacy & Storage

**User Control:**
- Setting to enable/disable telemetry storage
- Clear all data button
- Export before clear
- Choose retention period

**Size Management:**
- Show storage usage in Settings
- "Telemetry Database: 45.2 MB (24 days)"
- Warning at 90MB, auto-prune at 100MB

**What's NOT Stored:**
- Private pool addresses (reference only by pool index or public preset)
- Passwords or auth tokens (already not stored)
- Network traffic

## Implementation Plan

### Phase 1: Core Database (Week 1)
- SQLite setup with Core Data or GRDB
- Basic schema (readings table only)
- Write on every successful poll
- Read for existing charts (replace in-memory)

### Phase 2: Retention & Pruning (Week 2)
- Retention policy setting
- Auto-pruning on launch
- Storage size display
- Clear data functionality

### Phase 3: Historical Charts (Week 3)
- Extended time range picker (7d/30d/90d/all)
- Database-backed chart data
- Performance optimization (aggregate queries)

### Phase 4: Achievement Log (Week 4)
- Store all events (not just latest)
- Achievement timeline view
- Export achievements

### Phase 5: Advanced Analytics (Future)
- Downtime tracking
- Pool performance comparison
- Hour-of-day patterns
- Efficiency trends

## Technical Considerations

**Library Choice:**
- **Option A: Core Data** - Apple's built-in ORM, heavy but integrated
- **Option B: GRDB** - Lightweight Swift SQLite wrapper, performant
- **Option C: SQLite.swift** - Thin Swift wrapper

**Recommendation: GRDB**
- Fast, type-safe
- Good migration support
- Lightweight (~200KB)
- Active maintenance

**Migration Path:**
- Start with readings table only
- Add tables incrementally
- Zero-downtime migrations

**Performance:**
- Index on (miner_id, timestamp) for range queries
- Batch inserts (10 readings at a time)
- Read queries use aggregates (AVG, MAX, MIN)
- Widget reads from cache, not DB directly

## Example Queries

**Average hashrate last 7 days:**
```swift
let sevenDaysAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
let avgHashrate = try db.read { db in
    try MinerReading
        .filter(Column("miner_id") == minerId)
        .filter(Column("timestamp") >= sevenDaysAgo.timeIntervalSince1970)
        .average(Column("hashrate"))
}
```

**Uptime percentage:**
```swift
let onlineEvents = connectivity_events
    .filter(event_type == 'online')
    .count()

let totalEvents = connectivity_events.count()
let uptimePercent = (onlineEvents / totalEvents) * 100
```

**Peak temperature this month:**
```swift
let monthAgo = Date().addingTimeInterval(-30 * 24 * 60 * 60)
let peakTemp = try db.read { db in
    try MinerReading
        .filter(Column("miner_id") == minerId)
        .filter(Column("timestamp") >= monthAgo.timeIntervalSince1970)
        .max(Column("temp"))
}
```

## Export Format Enhancement

**CSV with time-series data:**
```csv
Timestamp,Miner,Hashrate_GHs,Power_W,Temp_C,Fan_%,Shares_Accepted,Pool
2024-01-15 14:30:00,Workshop Gamma,1218.5,19.2,53,65,12486,solo.ckpool.org
2024-01-15 14:30:30,Workshop Gamma,1220.1,19.3,54,66,12498,solo.ckpool.org
...
```

**PDF enhancement:**
- Summary stats section (avg/min/max over report period)
- Chart images (hashrate, temp trends)
- Achievement timeline
- Uptime/downtime summary

## Questions

1. **Default enabled or opt-in?** - Suggest default enabled with clear Settings toggle
2. **Retention default?** - Suggest 30 days (balance history vs storage)
3. **Sampling rate?** - Every reading or downsample to every 5min?
4. **Widget integration?** - Show "X days of data" badge?

## Next Steps

1. Add GRDB dependency to Package.swift
2. Create database schema and models
3. Wire up write path in recordSuccessfulInfo()
4. Add Settings UI for retention policy
5. Replace in-memory history with DB queries
6. Extend chart time ranges

Ready to implement?
