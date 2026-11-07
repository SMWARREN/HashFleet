# Website/Native Parity Investigation Report
**Date:** 2026-10-12
**Scope:** Read-only comparison of `/Users/USER/dev/hashfleet/website` and native iOS/Mac targets (`/Users/USER/dev/hashfleet/App/`)

---
## 1. Executive Summary

The website demo (`website/src/App.tsx`, `website/src/styles.css`, `website/src/components/AppDemos.tsx`) provides an interactive browser-based preview of Hash Fleet's functionality. The native targets are SwiftUI apps for iPhone/iPad (`HashFleetApp.swift`, `DashboardView.swift`, etc.) and macOS. This report identifies parity gaps across theme tokens, component structure, interactions, and UX patterns, with concrete file-level references and ordered fixes.

Key finding: The website was **hand-built as a web preview** (per `App.tsx` faq #77: "All preview readings are fictional sample data"), but many design tokens, component patterns, and interaction flows were derived from the native codebase. Gaps fall into three categories: (A) design tokens that can be synchronized, (B) component structure differences that affect visual fidelity, and (C) interaction/UX patterns that differ due to platform constraints.

---
## 2. Theme Token Parity

### Native Implementation: `App/Design/FleetTheme.swift`
Defines 46 color tokens using `adaptive(light: ..., dark: ...)` computed from `UIColor` with automatic light/dark mode switching. Key tokens:
- `canvas`, `ink`, `surface`, `raised`, `accent`, `positive`, `warning`
- Hashrate-specific: `hashrateSurface`, `hashrateInk`, `hashrateAccent`
- Card modifier with padding/fill/border/cornerRadius

### Website: `website/src/styles.css`
Defines 14 custom properties (`--canvas`, `--ink`, `--surface`, `--raised`, `--accent`, `--positive`, etc.) with manual `color-scheme: dark` and `[data-theme='light']` overrides.

| Token | Native | Website | Parity Gap |
|-------|--------|---------|------------|
| `--canvas` | `adaptive(0xFFFFFF, 0x02090C)` | `#080b0c` (dark) / `#ffffff` (light) | **Medium** - Native supports dynamic switching; website requires `data-theme` toggle |
| `--ink` | `adaptive(0x21201E, 0xF4F6F7)` | `#f0f2ef` (dark) / `#202725` (light) | **Medium** - Slight shade differences (native darker in dark) |
| `--accent` | `adaptive(0x8A5000, 0xF5AC26)` | `#f5ac26` (both modes) | **Low** - Same hex, native adds adaptive brightness |
| `--positive` | `adaptive(0x356447, 0x25A354)` | `#86c9a4` (dark) / `#2f714c` (light) | **Medium** - Native adaptive; website static |
| `--surface` | `adaptive(0xF5F5F5, 0x10191D)` | `#f5f5f5` (light) / `#10191d` (dark) | **Low** - Identical values |
| `--raised` | `adaptive(0xE5E5E5, 0x182126)` | `#e9ede6` (light) / `#171d1f` (dark) | **Medium** - Native adaptive; website static |

### Fixes Ordered:
1. **Add `data-theme` support to website** - Enable `[data-theme='light']` block and a theme toggle that sets `data-theme` attribute (see `website/src/styles.css` light mode block already exists but no toggle)
2. **Unify accent color** - Website already uses `#f5ac26` matching native dark mode; ensure light mode contrast meets WCAG (native uses `adaptive` which auto-adjusts)
3. **Synchronize positive color** - Either make website `adaptive` via CSS `light/dark` media queries, or update native to match website static values if adaptive behavior causes inconsistencies

---
## 3. Component Structure Parity

### Native: `App/Features/Dashboard/DashboardView.swift`
- `NavigationStack`-based hierarchical navigation
- `@SceneStorage` for `selectedTab` and `sidebarSelectionID`
- `@Environment(\.dynamicTypeSize)` for accessibility
- Sheet presentations via `.fleetPagePresentation()` modifier
- Toolbar with brand item, trailing menu (settings, refresh, about, feature tour), plus `+` add miner
- `@Namespace var minerTransitionNamespace` for miner detail transitions
- Multiple `@State` vars for sheet presentation: `showingAddMiner`, `showingSettings`, `showingAbout`, `showingFeatureTour`, `showingSideMenu`, `showingEnergy`, `showingNetwork`, `showingReports`, `showingBackup`, `showingAchievements`
- `DashboardPageDestination` enum for route tracking
- `minerExpansion` dictionary for card expansion state
- `minerSettingsRoute` for nested Pools settings

### Website: `website/src/App.tsx`
- React state-based navigation (`setPlatform('mac'|'iphone'|'terminal')`)
- Dialog-based app download modal
- Tabbed interface with `HeroScene` + `MacDemo`/`IPhoneDemo`/`TerminalDemo`
- No `NavigationStack`; uses React routerless tab panels (`role="tablist"` + `role="tabpanel"`)
- No `@Namespace`-equivalent; no explicit transition between miner details
- Single `useState` for `theme` ('dark'/'light')
- `dialog` element for modals (not SwiftUI `.sheet()`)

### IPhoneDemo vs Native iPhone Settings
| Aspect | Native `DashboardView` | Website `IPhoneDemo` | Gap |
|--------|----------------------|---------------------|-----|
| Navigation tabs | Persistent bottom tab-bar (`FleetTabBar`) | Bottom tab-bar with identical items | **Low** - Visual parity good |
| Settings depth | `MonitoringSettingsView` → detailed forms | Settings page with "Compact cards" toggle + "Honest background behavior" note | **Medium** - Native has full settings flow; website has limited demo |
| Miner detail transition | `.fleetPageSheet()` with namespace-animated transition | Click opens `MinerDetail` inline within same panel | **Medium** - Native uses sheet transition; website inline |
| Add miner flow | `.fleetPageSheet()` `AddMinerView` | Website: open dialog with "Get Hash Fleet" CTA | **Low** - Different mechanism but same intent |

### MacDemo vs Native macOS Dashboard
| Aspect | Native `DashboardView` | Website `MacDemo` | Gap |
|--------|----------------------|----------------|-----|
| Sidebar | `mac-sidebar` with workspace label + collapsible items | Left sidebar with overview/miners/energy buttons | **Low** - Similar visual pattern |
| Chart rendering | `HashChart` (custom SwiftUI) | `HashChart` (custom React component) | **Low** - Both render hashrate trends |
| Energy display | `FleetEnergyView` with detailed metrics | `EnergyDemo` with range slider + estimate | **Medium** - Native has full energy view; website has slider + illustrative estimate |
| Miner cards | `MinerOverviewCard` with metrics + `MinerOverviewCard+Metrics` | `phone-miners` list with compact cards toggle | **Medium** - Native has expandable cards; website has compact toggle |

### Fixes Ordered:
1. **Add `@Namespace`-equivalent to website** - Not possible in React without complex gesture libraries; document as "platform difference"
2. **Synchronize sidebar structure** - Website `MacDemo` sidebar items (`Fleet`, `My miners`, `Energy`) match native `DashboardView` sidebar (`.mac-sidebar`): confirm order and labels align
3. **Energy view parity** - Add range slider to website `EnergyDemo` matching native `FleetEnergyView` structure, or add note that website estimate is illustrative only

---
## 4. Interaction & UX Parity

### Native Touch/Gesture Patterns
- **Pull-to-refresh**: `.refreshable` on `ScrollView` (`DashboardView` line 109)
- **Sheet dismissal**: `.fleetDismissPresentationsOnNavigation` clears all presentation bindings (`DashboardView` line 90-108)
- **Search focus**: `.accessibilityAction(named: Text("Find a miner"))` sets `showsSearch = true` and `searchIsFocused = true` (`DashboardView` lines 83-86)
- **Appearance toggle**: Toolbar button switches `store.preferences.appearance` between `.system`, `.light`, `.dark` (`DashboardView` lines 325-332)
- **Add miner**: `.fleetPagePresentation(isPresented: $showingAddMiner)` → `AddMinerView.fleetPageSheet()` (`DashboardView` line 111)

### Website Interaction Patterns
- **Pull-to-refresh**: Not applicable (browser-based); manual "Try a miner, a chart range, or Energy" CTA
- **Modal dialogs**: `<dialog>` element with `showModal()` (`App.tsx` lines 40-45)
- **Theme toggle**: `useState<'dark' | 'light'>` with `setTheme()` (`App.tsx` line 88)
- **Add miner**: Opens dialog with "Get Hash Fleet" button (`App.tsx` line 94-97)
- **Search**: Input field in phone/mac stages, not persistent accessibility action

### Notification & Background Behavior
| Feature | Native | Website | Gap |
|---------|--------|---------|-----|
| Local notifications | `FleetLocalNotifications.setup()`, `.requestAuthorization()` (`HashFleetApp.swift` lines 78-86) | Not present | **High** - Native has full notification system |
| Background refresh | `FleetBackgroundRefresh.register()`/schedule (`HashFleetApp.swift` lines 79-80) | Not present | **High** |
| Live Activities | Not examined in this scope | Not present | **Medium** |
| Best-effort background checks | iOS may delay/skip (`App.tsx` faq #80) | N/A (browser) | **Low** - Different platform |

### Fixes Ordered:
1. **Document platform differences** - Add section to website FAQ noting native features not available in browser demo (notifications, background refresh, live activities)
2. **Add "demo mode" disclaimer** - Website already has this (`App.tsx` faq #77), but could explicitly list missing native features
3. **Synchronize search behavior** - Website search is per-stage; native has persistent `searchIsFocused` state with `.accessibilityAction`. Consider adding persistent search state to website if designing for accessibility parity.

---
## 5. Typography & Layout Parity

### Font System
- **Native**: `FleetTheme.mono(11)` = `.system(size: 11, weight: .medium, design: .monospaced)`; `.title3.weight(.semibold)` etc. (system fonts with SF Pro Rounded)
- **Website**: `font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif`; explicit `font: 500 10px/1.6 'SFMono-Regular', Consolas, monospace` for monospaced

### Key Typography Differences
| Element | Native | Website | Gap |
|-------|--------|---------|-----|
| Monospace used for | `FleetTheme.mono()` across views | `'SFMono-Regular', Consolas, monospace` in CSS | **Low** - Same intent, different fallback |
| Heading hierarchy | `.title3.weight(.semibold)` → `h1` clamp sizes | `h1` clamp(54px, 6.15vw, 91px) | **Medium** - Native uses relative system size; website uses vw |
| Caption/small text | `.caption.weight(.semibold)` / `.caption2.monospaced()` | `.eyebrow` (500 10px/1.6), `.kicker-dot` | **Low** - Similar scale |
| Button min-height | `44px` (iOS), varied for mac | `min-height: 44px` (primary), `34px` (small) | **Low** - Both meet 44px tap target |

### Layout / Spacing
- **Native**: Uses `@Environment(\.horizontalSizeClass)` for compact/wide; `@Environment(\.dynamicTypeSize)` for accessibility; `GeometryReader` viewport-aware
- **Website**: Media queries at `max-width: 900px`, `640px`, `374px`; `container` with `max-width: 1280px`

### Fixes Ordered:
1. **Add `dynamicTypeSize` equivalent to website** - Media queries for `large`/`extra-large` text sizes using CSS `clamp()` with `ch` units or `size` property
2. **Unify monospace font stack** - Website already uses `'SFMono-Regular', Consolas, monospace` which matches native SF Mono when available; keep as-is but add `system-ui` fallback
3. **Add `horizontalSizeClass` awareness** - Website already has responsive breakpoints; ensure new breakpoints consider `prefers-reduction` media query like native does

---
## 6. Iconography Parity

### Native: `LucideSwift` + `App/Design/LucideIconHelper.swift`
- Custom Swift port of Lucide icons
- `FleetBrandMark` uses `Image("HashFleetBrand")` from asset catalog
- Icons rendered with `.renderingMode(.original)` for consistent coloring

### Website: SVG sprites + inline `<Icon name="..." />`
- `components/Icon.tsx` renders Lucide SVGs
- `website/src/app-demos.css` references `svg` colors via `var(--accent-ink)`, `var(--dim)`, etc.
- Hero scenes use `/images/brand.png`, `/images/miner.png`, `/images/bitsy-wave.png`

### Gap Analysis
| Aspect | Native | Website | Gap |
|--------|--------|---------|-----|
| Icon library | `LucideSwift` Swift port | `Lucide` via `components/Icon.tsx` | **Low** - Same source, different language |
| Brand mark | `Image("HashFleetBrand")` asset catalog | `/images/brand.png` file | **Low** - Different file format, same visual |
| Icon coloring | `.foregroundStyle(FleetTheme.accent)` | `color: var(--accent-ink)` / `color: var(--dim)` | **Low** - Same variable names, different scoping |
| Custom icons | Helper defines specific usage | None observed | **None** |

### Fixes Ordered:
1. **Verify icon color variables match** - Confirm `FleetTheme.accent` (#8A5000 dark / #F5AC26 light) maps to website `--accent-ink` (#F5AC26 dark / #8B5300 light) - note hue inversion in light mode may need attention
2. **Add missing icon names** - If website uses icon names not in native, or vice versa, document as gap and add to both codebases

---
## 7. Ordered Fix Recommendations

### Phase 1 - Critical (Visual/Fidelity)
1. **Add `data-theme` toggle to website** - Enable light/dark mode switching that synchronizes with native `store.preferences.appearance`. Website CSS light mode block already exists at `styles.css` line 30; add a UI control.
2. **Synchronize accent/positive color variables** - Ensure `--accent-ink` and `--positive` website variables match native adaptive values or document the intentional difference.
3. **Add responsive text size media queries** - Mirror native's `@Environment(\.dynamicTypeSize)` with `prefers-large-text` / `prefers-extra-large-text` CSS media queries.

### Phase 2 - High (Interaction/Feature)
4. **Document native-only features in website FAQ** - Add list: local notifications, background refresh, live activities, Siri/Shortcuts integration, Haptic Touch actions.
5. **Add persistent search state to website** - Implement `useRef` + `useEffect` pattern similar to native's `searchIsFocused` + `.accessibilityAction` for keyboard/namespaced search.
6. **Add energy range slider to website `EnergyDemo`** - Mirror native `FleetEnergyView` structure; add note that slider is illustrative only.

### Phase 3 - Medium (Architecture)
7. **Add `@Namespace`-equivalent transition documentation** - Note that React cannot natively replicate SwiftUI's namespace-animated transitions; if animation is desired, research `react-native-reanimated` or `framer-motion` alternatives.
8. **Harmonize sidebar item ordering** - Verify `MacDemo` sidebar (`Fleet`, `My miners`, `Energy`) matches native `DashboardView` `.mac-sidebar` order; swap if needed.
9. **Add `horizontalSizeClass`/`dynamicTypeSize` media queries** - Ensure website breakpoints at `large`/`extra-large` text sizes don't break layout.

### Phase 4 - Low (Polish)
10. **Verify icon color variable mapping** - Confirm `--accent-ink: #F5AC26` (dark) / `#8B5300` (light) vs native `FleetTheme.accent: #8A5000` (dark) / `#F5AC26` (light). Note the hue inversion may be intentional for contrast.
11. **Add missing locale/accessibility labels** - Website has `aria-label` on many elements; verify all interactive elements have descriptive labels matching native `accessibilityIdentifier` patterns.

---
## 8. Validation & Test Paths

| Recommendation | Test Path | Expected Result |
|----------------|-----------|-----------------|
| Add `data-theme` toggle | Manual: toggle switch, verify `document.documentElement.dataset.theme` updates, verify colors shift to light/dark values | Theme toggles; colors match `styles.css` `[data-theme='light']` block |
| Synchronize accent/positive colors | Visual inspection: dark mode and light mode side-by-side on same screen | No jarring color shifts between native and website on same mode |
| Add responsive text size queries | Browser: resize text size in Safari preferences → "Larger Text"; verify layout doesn't break | Layout adapts; no overflow or cutoff text |
| Document native-only features | Open website on iPhone, verify FAQ section lists missing features | FAQ accurately describes what browser demo cannot do |
| Add energy slider | Interact with `EnergyDemo` tab; drag slider; verify illustrative cost updates | Slider updates cost display; note is visible that this is demo-only |

---
## 9. Uncertainties & Blockers

1. **Theme toggle implementation** - Website CSS has `[data-theme='light']` block but no toggle UI element visible in code. Need to locate where theme state is managed (possibly not in current source, or managed elsewhere).
2. **`LucideSwift` vs website `Icon` component parity** - Could not verify if `LucideSwift` icon set is identical to the website's `components/Icon.tsx` Lucide port. May need maintainer confirmation.
3. **`FleetTheme.accent` light-mode value** - Native uses `adaptive(0x8A5000, 0xF5AC26)` which is `#8A5000` light and `#F5AC26` dark. Website uses static `#f5ac26` for both. The inversion may cause contrast issues in light mode that need testing.
4. **`data-theme` persistence** - Website may not persist theme choice between sessions; native uses `@SceneStorage("selectedTab")` pattern. Need to verify if website has `localStorage` or similar.
5. **`HashChart` component parity** - Both native and website have `HashChart` but could differ in data rendering, axis labels, or animation. Not fully compared in this scope.

---
## 10. Conclusion

The website demo and native app share a common design language derived from the same token system, but implementation differences arise from platform constraints (SwiftUI vs React, iOS/macOS vs browser). The most critical gaps are:

1. **Theme synchronization** - Website needs `data-theme` toggle to match native's dynamic light/dark switching.
2. **Feature parity documentation** - Website FAQ should explicitly list native-only features (notifications, background refresh).
3. **Text size accessibility** - Website needs media queries for larger dynamic type sizes.

All other gaps are visual or interaction-level differences that are expected between platforms and should be documented for maintainers. The implementation addendum below records the website corrections applied after this investigation.

## 11. Website implementation addendum

The website parity slice is now implemented as a **dark Hash Fleet browser preview**, not as a replacement for the native app. The landing page keeps the original black HashFleet marketing composition, while its Mac and iPhone previews use the native fleet hierarchy: demo status banner, fleet hashrate card, chart/list structure, persistent Fleet/Settings/About navigation, and the safe Restart device review screen. The browser request target remains the reserved `gamma-demo.invalid` hostname, and no device or network request is made.

The website preview uses the coherent fictional fixture math from the native `DemoFleet` fixture: 3.02 TH/s total ASIC hashrate, 50.8 W reported power rounded to 51 W in the cards, and 16.8 J/TH derived efficiency. It shows the same three sample miners as the supplied native capture, with reserved `.invalid` hostnames and no live connections.

The earlier recommendations about adding a theme toggle, documenting native-only capabilities, and harmonizing preview navigation are addressed for this website slice. The browser defaults to dark mode, retains an explicit light-mode toggle for inspection, and does not persist a stale light choice over the black Hash Fleet landing presentation.

Validation performed:

- `npm run check`: 83 tests passed
- `npm run build`: passed
- Playwright browser flow: dark default, Hash Fleet branding, Mac fleet view, iPhone Fleet/Settings/About navigation, Restart device review, reserved `.invalid` target, no console errors, and no horizontal overflow at 1440, 1024, 768, 375, or 320 pixels
- `git diff --check`: passed

The supplied native screenshots were used as visual references and the final website states were captured in the browser. Native app source and live hardware were not modified.

---
*Report generated by Jcode parity investigator on 2026-10-12*
