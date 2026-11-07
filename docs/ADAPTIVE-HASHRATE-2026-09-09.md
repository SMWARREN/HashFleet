# Adaptive Hashrate and Dashboard Palette

## Current visual contract

The dashboard uses three deliberate surfaces instead of one warm panel:

- **Fleet summary hero**: `FleetTheme.charcoal` in both appearances, with `panelInk`, `panelSecondary`, and `panelAccent`. This keeps the primary fleet reading dark as requested.
- **Hashrate trend card**: `FleetTheme.surface` with `ink`, `secondary`, and `accent` roles. The chart line uses the normal theme accent and its area uses a low-opacity neutral ink gradient, so light mode does not become a yellow or orange slab.
- **Solo odds card**: `FleetTheme.soloSurface` in both appearances. Its time-window control uses a separate `FleetTheme.charcoal` surface with panel text and accent roles, avoiding the light-mode white control slab while preserving readable selection states.
- **Miner detail hashrate cards**: continue to use the opposite-surface `hashrate*` tokens where a high-contrast dedicated hashrate panel is part of the detail layout.

The dashboard remains responsive on iPhone: its page gutter is 12 points, the trend card uses a 16-point radius, and the fleet artwork is rendered at 72 by 50 points. Card content receives its own larger internal padding so the cards can stretch wider without pinning text to the walls.

## Theme roles

| Role | Light mode | Dark mode | Used by |
| --- | --- | --- | --- |
| `charcoal` | `#111111` | `#111111` | Fleet hero and Solo time-window control |
| `surface` | `#F5F5F5` | `#10191D` | Dashboard trend card |
| `soloSurface` | `#21201E` | `#21201E` | Solo odds comparison card |
| `panelInk` | `#FFFFFF` | `#F4F6F7` | Text on charcoal and Solo surfaces |
| `panelSecondary` | `#BDBDBD` | `#BFC6CC` | Secondary text on dark panels |
| `panelAccent` | `#E9931E` | `#F5AC26` | Dark-panel headings and selected controls |
| `ink` | `#21201E` | `#F4F6F7` | Trend card primary text and chart fill |
| `secondary` | `#595959` | `#BFC6CC` | Trend card secondary text |
| `accent` | `#8A5000` | `#F5AC26` | Trend line and neutral-card controls |

The `hashrateSurface`, `hashrateInk`, `hashrateSecondary`, `hashrateAccent`, and `hashrateSkeleton` roles remain tested for the dedicated miner-detail presentation. They are not used to paint the dashboard trend card, which intentionally stays neutral.

## Verification evidence

- The simulator test build for the revised dashboard completed successfully.
- `FleetPageCaptureUITests/testCapture11_LightAppearanceKeyViews` passed 1/1 and captured the real light dashboard at `48_light_dashboard_demo.png`. The capture shows the dark hero, larger fleet artwork, neutral trend fill, dark Solo control, and expanded card interiors.
- A real dark dashboard capture was produced at `05_dashboard_demo_top.png`. The broader capture then failed at its existing chart-selection timestamp assertion after tapping the chart, so chart interaction acceptance remains separate from this visual pass.
- The palette role suite previously passed 15/15 after the opposite-surface token update. The latest layout changes do not alter those token values.

## Scope

- `App/Design/FleetTheme.swift`
- `App/Design/FleetAdaptiveLayout.swift`
- `App/Features/Dashboard/DashboardCards.swift`
- `App/Features/Dashboard/FleetChainCard.swift`
- `App/Features/Dashboard/FleetChartSelection.swift`
- `App/Features/Dashboard/FleetHistoryCard.swift`
- `App/Features/Dashboard/FleetHistoryCard+Chart.swift`
- `App/Features/Dashboard/FleetHistoryCard+Display.swift`
- `AppTests/FleetPreferencesTests.swift`
