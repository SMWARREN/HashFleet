# Naming and scope: recommendation

Status: **recommendation only, nothing renamed.** A rename touches the bundle ID, App Store
listing, and any existing installs, so it is the owner's call.

## What prompted this

> "Might want to think of not making just for bitaxes, all open source miners. I don't know if
> the name needs changing maybe to The Fleet or something."

Two separate questions are tangled here. They should be decided separately:

1. **Scope**: should the app support more than Bitaxe? (Yes, and it mostly already can.)
2. **Name**: does "Hash Fleet" limit that? (Partly. But the cost of renaming is real.)

## Scope: the app is less Bitaxe-locked than it looks

An audit of every `Bitaxe` reference found 18 occurrences. Almost all are **cosmetic copy**, not
protocol coupling:

| Kind | Where | Real constraint? |
| --- | --- | --- |
| Marketing/UI copy | AboutView, FleetOnboardingView, AddMinerView, MiningSetupView | No |
| Display naming | `MinerDisplayName.automatic()` returns `"Bitaxe · <asic>"` and falls back to `"Bitaxe"` for **any** device | **Yes, a real bug for non-Bitaxe hardware** |
| Firmware feed | `FleetStore+Firmware` points at the official ESP-Miner repo | Partly, it is informational only |
| Compatibility | `MiningHardwareCompatibility` keys off reported **ASIC model**, not vendor | No, already vendor-neutral |

The transport is plain ESP-Miner/AxeOS HTTP JSON. That firmware family already covers Bitaxe,
NerdQAxe, NerdOCTAXE, NMAxe and several compatible boards. **Supporting "all AxeOS-family
open-source miners" is mostly a copy and display-name change, not an architecture change.**

Genuinely different hardware (Avalon Nano, Braiins, LuxOS Antminer, CGMiner-compatible rigs)
would need a new transport adapter. That is a real project, not a rename.

### Recommended scope wording

Claim **"open-source miners running AxeOS / ESP-Miner"** rather than "all open source miners".
It is accurate today, it is broader than "Bitaxe", and it does not promise Avalon or Antminer
support the code cannot deliver. This codebase is deliberately careful about not overstating
compatibility (see `MiningHardwareCompatibility.unverified`); the marketing copy should hold the
same line.

## Name: do not rename to "The Fleet"

I checked the competitive landscape. The category is crowded and every competitor is explicitly
multi-vendor:

- **HashGrid** (hashgrid.app) - BitAxe, Avalon, Hammer, Antminer
- **HashLink** - Bitaxe, NerdAxe, Avalon, Braiins OS
- **Kratos** - any CGMiner-compatible
- **BTC Miner Monitor** - Bitaxe, NerdAxe, NerdQaxe, NerdOctaxe
- **HashWatcher**, **HashMonitor**, **MinerWatch** - similar

Observations that matter for the decision:

1. **"The Fleet" is worse, not better.** It is generic, has no mining association, and is close to
   unsearchable. Every competitor above leads with a hash/mine/miner token precisely because that
   is what users search for. "Fleet" alone describes the *grouping*, not the *domain*.
2. **"Axe" is not as narrow as it feels.** In this community "Axe" reads as the AxeOS/Bitaxe
   *firmware family*, which is exactly the scope being recommended above. It is narrower than
   "Bitcoin miner" but wider than "Bitaxe".
3. **Renaming has real cost.** Bundle ID `app.hashfleet` is embedded in the widget group, the
   BGTaskScheduler identifier, and every persisted `UserDefaults` key (`app.hashfleet.*`). Changing
   the bundle ID means a new App Store listing and orphaned installs. Changing only the *display*
   name is cheap; changing identity is not.

### Recommendation

**Keep the bundle identifier. Consider only a display-name and subtitle change, and only if the
scope actually broadens past AxeOS.**

If a rename does happen later, prefer a name that keeps a domain token:

- `Hash Fleet` with subtitle "Open-source miner monitor" (cheapest, honest, no code change)
- `Hashfleet` / `Fleet Miner` (keeps domain scent, still available-looking, but new listing)
- ~~`The Fleet`~~ (not recommended: no domain scent, poor discoverability)

### What is being done now

Only the scope half, which is safe and reversible:

- Display naming stops asserting "Bitaxe" for hardware that never said it was one.
- User-facing copy broadens to open-source AxeOS-family miners.
- No rename, no bundle-ID change, no scheme change.
