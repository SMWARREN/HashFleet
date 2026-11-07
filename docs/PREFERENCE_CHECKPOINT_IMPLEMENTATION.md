# Preference Checkpoint Implementation

## Problem
Demo mode was leaking preference mutations back to the user's real settings. When a user entered demo mode, explored settings, then exited, their original preferences were lost. Additionally, if the app was force-closed or crashed mid-demo and relaunched, the demo-mutated preferences would persist.

## Solution
Implemented a preference checkpoint/restore mechanism that preserves user settings across demo entry/exit and app relaunch.

## Architecture

### Checkpoint Storage
- **Key**: `app.hashfleet.demo.preference-checkpoint.v1`
- **Format**: JSON dictionary of UserDefaults key-value pairs
- **Scope**: Preferences and temperature alerts only - device fleet completely untouched

### Checkpointed Preferences
**FleetPreferences keys:**
- appearance (dark/light/system)
- sort order
- ascending flag
- compact cards toggle
- external data enabled
- realtime monitoring
- block notifications
- best share notifications
- tour seen/suppressed flags
- dashboard coins selection
- system appearance migration flag

**Temperature Alert Preferences:**
- All keys matching `app.hashfleet.temperature-alert.v1.*` prefix

### Implementation Points

#### 1. loadDemo() - Checkpoint Creation
```swift
func loadDemo() {
    guard !isDemo else { return }
    // ... existing setup ...
    
    // Checkpoint preferences before demo mode
    checkpointPreferences()
    
    // ... load demo content ...
}
```

#### 2. clearDemo() - Checkpoint Restoration
```swift
func clearDemo() {
    guard isDemo else { return }
    // ... existing teardown ...
    
    // Restore preferences from checkpoint
    restorePreferencesFromCheckpoint()
    
    // ... restore devices ...
}
```

#### 3. FleetStore.init() - Mid-Demo Recovery
```swift
init(defaults: UserDefaults = .standard, ...) {
    self.defaults = defaults
    // ... assign stored properties ...
    
    // If a checkpoint exists from a mid-demo relaunch, restore it
    Self.restorePreferencesFromCheckpointIfNeeded(defaults: defaults)
    
    preferences = FleetPreferences(defaults: defaults)
    // ... create other properties ...
}
```

### Key Design Decisions

**Static recovery method for init**
- `restorePreferencesFromCheckpointIfNeeded` is static to allow calling before `self` is fully initialized
- Ensures preferences are restored before FleetPreferences/FleetTemperatureAlertPreferences read UserDefaults

**Direct UserDefaults mutation**
- Checkpoint stores/restores UserDefaults values directly
- Observable preference objects read updated values on next access
- No need to rebind or recreate observable instances

**Automatic checkpoint cleanup**
- Checkpoint is deleted immediately after restoration
- Prevents stale checkpoints from interfering with normal launches

## Device Fleet Safety

The checkpoint mechanism **never** touches:
- `app.hashfleet.devices.v1` (canonical device storage key)
- Device names, addresses, or configurations
- Fleet backup data
- Snapshot cache

Existing demo mode already had device preservation via `savedDevices`/`devices` swap. The checkpoint is **additive** and preference-scoped only.

## Test Coverage

**FleetDemoPreferenceCheckpointTests.swift** covers:
1. `testLoadDemoClearDemoPreservesRealPreferences` - Full demo cycle preserves settings
2. `testMidDemoRelaunchRestoresPreferencesOnInit` - Crash recovery works
3. `testCheckpointDoesNotAffectDeviceFleet` - Device storage untouched
4. `testCheckpointIncludesTemperatureAlertPreferences` - Temp alerts preserved
5. `testClearDemoWithoutLoadDemoIsNoOp` - Defensive against misuse

## Edge Cases Handled

✅ **Mid-demo force-close** - Checkpoint restored on next launch
✅ **Repeated demo entry** - Guard prevents double-checkpoint
✅ **clearDemo without loadDemo** - No-op, preferences unchanged
✅ **Temperature alert mutations** - Included in checkpoint
✅ **Missing checkpoint** - Silently skipped, no error

## Future Considerations

**Preference key exhaustiveness**
- If new preference keys are added to FleetPreferences or new temperature alert patterns, update `checkpointPreferences()` key list
- Consider code review reminder or runtime assertion for complete coverage

**Checkpoint versioning**
- Current key includes `.v1` for future schema migrations if needed
- If preference structure changes significantly, add migration logic

## Validation Steps

**Manual testing required:**
1. Set preferences to known values
2. Enter demo mode, mutate preferences
3. Exit demo mode, verify original values restored
4. Enter demo again, mutate, force-close app
5. Relaunch, verify preferences restored (not demo values)
6. Verify device fleet unchanged throughout

**Automated testing:**
- Add FleetDemoPreferenceCheckpointTests.swift to Xcode project target
- Run full test suite to verify no regressions
