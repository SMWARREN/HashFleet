# App Intents confirmation compatibility, November 3, 2026

## Reported issue

The current SDK marks `AppIntent.requestConfirmation(result:confirmationActionName:showPrompt:)` deprecated on every platform. Hash Fleet already used the newer dialog-aware overload on iOS 18/macOS 15, but its iOS 17/macOS 14 fallback still emitted the warning.

## Change

- Restart, frequency and fan-speed intents continue to require local device authentication and explicit confirmation.
- On iOS 18/macOS 15/watchOS 11/tvOS 18/visionOS 2 and newer, the existing `requestConfirmation(conditions:actionName:dialog:)` call is retained with unconditional conditions.
- The older-OS branch now uses `IntentParameter.requestConfirmation(for:dialog:)` on the selected miner, passing the same complete target, proposed value and risk dialog. It does not use an empty generic confirmation or suppress compiler diagnostics.
- Parameter confirmation returns a Boolean. `FleetMinerControlConfirmation.requireApproval` converts a negative answer to `CancellationError`, so the executor cannot proceed to its second verification or write after a decline.
- Existing identity revalidation, timeout/cancellation, parameter validation, demo exclusion, exact payload restrictions and no-retry behavior are unchanged.
- The independent Watch target remains read-only and does not link these control intents.

## Executed validation

After the final source edit:

- The real iOS app compiled and all **15 `FleetMinerControlIntentTests` passed**. New cases prove that declining the Boolean confirmation prevents every control action and that approval still requires the second verification before a single write.
- All **4 `FleetWatchSetupSelectionTests` passed** in the same run.
- The native Mac target compiled successfully. It was not launched or installed. The generated compile-only app was archived privately, unregistered and removed so `/Applications/Hash Fleet.app` remained the sole installed/running Mac app.
- Isolated compatibility probes typechecked against the installed iPhoneOS and macOS SDKs with Swift 6, deployment targets iOS 17/macOS 14 and `-warnings-as-errors`.
- Neither actual target build emitted the reported deprecated confirmation diagnostic.

Tests use injected fixture reads/writes, not real miner controls. No miner request, restart, tuning, fan/pool edit, firmware operation, mining-Mac service action or protection change occurred. The older-OS Siri confirmation interface itself was not exercised on physical iOS 17/macOS 14 hardware.

Private evidence under `$JCODE_SCRATCH_DIR/hashfleet-watch-20261103/`: `iphone-confirmation-final.log`, `iPhone-Confirmation-Final.xcresult`, `mac-confirmation-final.log` and `HashFleet-Mac-confirmation-compile-only.zip`.

## Apple API references

- [Deprecated result-based confirmation](https://developer.apple.com/documentation/appintents/appintent/requestconfirmation(result:confirmationactionname:showprompt:))
- [Dialog-aware intent confirmation](https://developer.apple.com/documentation/appintents/appintent/requestconfirmation(conditions:actionname:dialog:))
- [Parameter confirmation and its Boolean result](https://developer.apple.com/documentation/appintents/intentparameter/requestconfirmation(for:dialog:))
