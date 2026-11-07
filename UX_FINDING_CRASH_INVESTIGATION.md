# UX Finding: Reported Crash on Miner Detail Navigation

**Severity**: UNCONFIRMED (Cannot reproduce)  
**Status**: Investigation complete, awaiting user validation  
**Date**: 2026-09-12  
**Build**: `ac22ee8`

---

## Finding Summary

User reported "App crashes when clicking on miner detail" but crash cannot be reproduced in current build.

---

## Evidence

### Crash Log Analysis

**Widget Crashes Found** (Not related to navigation):
- `ExcUserFault_HashFleetWidgets-2026-09-11-230521.ips`
- `ExcUserFault_HashFleetWidgets-2026-09-12-014646.ips`
- **State**: Widget extension XPC connection failure
- **Impact**: Does not affect main app navigation
- **User Experience**: User may have seen system error dialog, misattributed to navigation

**Historical Main App Crashes**:
- `HashFleet-2026-09-11-172706.ips` and similar from Sept 11
- **State**: Crashed (SIGKILL - platform mismatch)
- **Cause**: Build configuration error during development
- **Status**: Already resolved in current build
- **User Experience**: App terminated immediately

**Current Build**:
- **State**: No crashes found
- Zero crash logs since latest deployment
- Code review shows no crash risks
- Successfully builds and deploys to device

---

## User Experience Impact

### If Crash Actually Exists

**State Progression**:
1. User on dashboard viewing miner cards
2. User taps miner card → NavigationLink triggers
3. **Crashed** → App terminates, returns to home screen
4. User must relaunch app
5. Returns to dashboard (state loss)

**Severity**: HIGH
- Blocks primary workflow (viewing miner details)
- Complete feature unavailability
- Loss of navigation state
- Poor user trust

### If Crash is Misattribution

**State**: Recovered-after-reload
- User saw Widget crash dialog
- Main app actually works fine
- User assumed navigation caused it

**Severity**: LOW
- Confusion rather than actual bug
- No feature impact

---

## Recommended Fixes

### Immediate (Completed ✅)

1. ✅ **Deploy fresh build** - Eliminates old platform crashes
   - Deployed to device `YOUR_DEVICE_ID`
   - Commit: `ac22ee8`

2. ✅ **Document acceptance test** - Clear validation steps
   - Created: `ACCEPTANCE_TEST_MINER_DETAIL.md`
   - Covers: launch → demo → navigation → verification

3. ✅ **Create troubleshooting guide** - User self-service
   - Created: `TROUBLESHOOTING_CRASH.md`
   - Covers: device-specific scenarios, crash reporting

### If Crash Confirmed by User

4. **Add crash protection** (Pending user confirmation):
   ```swift
   // In DashboardView+MinerCards.swift
   NavigationLink {
       Group {
           if let device = store.devices.first(where: { $0.id == device.id }) {
               MinerDetailView(
                   device: device,
                   store: store,
                   insights: insights,
                   liveConnectionError: store.liveConnectionErrors[device.id],
                   isLive: store.liveConnectedDeviceIDs.contains(device.id)
               )
           } else {
               ContentUnavailableView(
                   "Miner Not Found",
                   systemImage: "exclamationmark.triangle",
                   description: Text("This miner may have been removed.")
               )
           }
       }
   }
   ```

5. **Add error boundary** (If specific crash identified):
   - Wrap navigation in ErrorBoundary view
   - Show fallback UI instead of crash
   - Log error details for diagnosis

6. **Add state preservation** (For crash recovery):
   - Save navigation state before transition
   - Restore detail view on relaunch if crashed
   - Show "Recovered from crash" notice

### Monitoring (Recommended)

7. **Add crash analytics**:
   - Integrate Sentry or similar
   - Track navigation crashes specifically
   - Monitor crash-free rate for detail view

8. **Add navigation telemetry**:
   - Log successful detail navigations
   - Track navigation timing
   - Identify slow/problematic transitions

---

## Validation Checklist

### User Must Validate

- [ ] Launch app on physical device
- [ ] Tap "Explore demo"
- [ ] Tap any miner card
- [ ] Confirm: Does detail view load?
- [ ] If crashes: Follow `TROUBLESHOOTING_CRASH.md`
- [ ] Report: Crash exists or works fine

### Developer Can Validate ✅

- [x] Crash logs analyzed
- [x] Code reviewed for crash risks
- [x] Fresh build deployed
- [x] Simulator testing (no crashes)

---

## Current State Assessment

**State**: Pending-interrupt (waiting for user test)

**Confidence**: High that it works
- All evidence shows current build is safe
- Historical crashes already fixed
- Code patterns are correct

**Risk**: Medium
- Cannot confirm without physical device test
- User may experience device-specific issue
- Widget crashes may recur (unrelated but confusing)

---

## Next Steps

1. **User**: Run `ACCEPTANCE_TEST_MINER_DETAIL.md` on iPhone
2. **If works**: Close issue, no crash exists
3. **If crashes**: Collect troubleshooting info, implement fixes 4-8
4. **Consider**: Add crash analytics regardless for future monitoring

---

## Technical Details

**Files Reviewed**:
- `App/Features/Miner/MinerDetailView.swift` - No crash risks
- `App/Features/Dashboard/DashboardView+MinerCards.swift` - Safe navigation
- `App/Design/FleetMotion.swift` - Availability-gated transitions

**Build Info**:
- Scheme: HashFleet
- Configuration: Debug
- Device: iPhone (YOUR_DEVICE_ID)
- Installation: `/var/containers/Bundle/Application/DEDB9CE7-D43F-4937-A171-63D380D8BCC1/`

**Documentation**:
- Investigation: `CRASH_INVESTIGATION_SUMMARY.md`
- Acceptance Test: `ACCEPTANCE_TEST_MINER_DETAIL.md`
- Troubleshooting: `TROUBLESHOOTING_CRASH.md`
- UX Finding: This file
