# Acceptance Test: Miner Detail Navigation

**Issue**: User reported "App crashes when clicking on miner detail"

**Build**: commit `5039459` deployed to device `YOUR_DEVICE_ID` at 2026-09-12 09:44

## Test Steps

1. **Launch app** on iPhone
   - [ ] App launches without crash
   - [ ] Onboarding screen displays

2. **Load demo miners**
   - [ ] Tap "Explore demo" button
   - [ ] Dashboard loads with demo miner cards
   - [ ] No crashes during load

3. **Navigate to miner detail**
   - [ ] Tap on any miner card
   - [ ] **CRITICAL**: Detail view loads (navigation succeeds)
   - [ ] Detail view shows miner name, telemetry, controls
   - [ ] No crash during navigation
   - [ ] No crash during detail view render

4. **Navigate back**
   - [ ] Tap back button
   - [ ] Returns to dashboard
   - [ ] No crashes

5. **Repeat with different miner**
   - [ ] Tap different miner card
   - [ ] Detail view loads again
   - [ ] No crashes

## Expected Result

✅ All steps complete without crash
✅ Miner detail view displays correctly
✅ Navigation is stable and repeatable

## Actual Result

**Status**: AWAITING USER TEST

**Notes**: 
- Found old platform mismatch crash from Sept 11 (already fixed)
- Found Widget XPC crashes (unrelated to main app navigation)
- Code review shows no crash risks
- Fresh build deployed successfully

**User must confirm**: Does the app still crash when clicking miner detail?
