# Crash Troubleshooting Guide

If the app still crashes when clicking miner detail, follow these steps to diagnose:

## Quick Checks

1. **Force quit and relaunch**
   - Double-tap home button / swipe up
   - Swipe up on HashFleet to close
   - Reopen from home screen

2. **Check iOS version**
   - Settings → General → About → Software Version
   - App requires iOS 18.0+
   - Report your version if crash persists

3. **Check storage**
   - Settings → General → iPhone Storage
   - Low storage can cause crashes
   - Ensure >1GB available

4. **Restart device**
   - Hold power + volume down
   - Slide to power off
   - Wait 30 seconds, power on

## If Crash Persists

### Capture Crash Details

1. **What you see**:
   - App closes immediately?
   - Screen freezes then closes?
   - Error message shown?

2. **When it happens**:
   - Every time you tap a miner?
   - Only specific miners?
   - Only after certain actions?

3. **Device info**:
   - iPhone model: ___________
   - iOS version: ___________
   - Free storage: ___________

### Get Crash Logs

1. **Settings → Privacy & Security → Analytics & Improvements → Analytics Data**
2. **Look for**: `HashFleet-2026-09-12-*.ips`
3. **Tap the newest one → Share button → Save to Files**
4. **Share the file** with the developer

### Temporary Workaround

If only certain miners crash:
- Note which miners work vs crash
- Use working miners only
- Report the pattern

If all miners crash:
- Stay on dashboard
- Use quick actions from miner cards (gear icon → settings)
- Report that detail view is completely broken

## Additional Info to Report

- [ ] Does demo mode crash? (Explore demo → tap miner)
- [ ] Do real miners crash? (Add miner → tap card)
- [ ] Did it work before? When did it start crashing?
- [ ] Any recent iOS updates?
- [ ] Any other apps crashing?

## Developer Investigation

If you report a crash, the developer will need:

1. ✅ Exact steps to reproduce
2. ✅ When it crashes (timing)
3. ✅ Device/iOS info
4. ✅ Crash log file (if possible)

**Current Status**: Build `06dcb32` deployed to your device. All investigation shows it should work. If crash persists, it's a new issue not found in logs.
