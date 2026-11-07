# Native motion research: dashboard search

**Scope.** Read-only review of `App/Features/Dashboard/DashboardView.swift` and `FleetStatusTicker.swift` in HashFleet. The project deployment target is iOS 17.0. Existing working-tree changes were left untouched. This report is the only file written.

## Evidence from current implementation

- `DashboardView` already has the intended state model: `showsSearch`, `searchText`, `searchIsFocused`, and `@Environment(\.accessibilityReduceMotion)`. The scroll observer currently maps upward travel to `showsSearch = true` and downward travel to hiding only when the query is empty and the field is not focused (`DashboardView.swift:62-68`).
- The conditional principal toolbar item is the correct visual slot for a compact, centered field. The current field is one line, has a 44 pt minimum height, a clear button with a 44 pt target, and the accessible label/identifier `Find a miner` / `dashboard.search` (`DashboardView.swift:81-103, 129-148`). Keep the principal item as the single source of truth rather than duplicating a search field in content.
- Existing card expansion uses `withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2))`, which is a good policy baseline (`DashboardView.swift:270-273`). The hero reading uses `.contentTransition(.numericText())` (`DashboardView.swift:392-398`), while the ticker has a continuously rendered marquee at 30 fps and an explicit static layout for Reduce Motion, VoiceOver, and accessibility sizes (`FleetStatusTicker.swift:105-116, 167-201`). Do not add another continuous animation around the search or make the ticker more energetic.

## Recommendation: iOS 17-compatible placement and behavior

1. **Placement:** retain `ToolbarItem(placement: .principal)` with the field centered between the leading fleet icon and trailing add button. Give the field a finite horizontal budget, for example `frame(maxWidth: 260)` on regular widths, and allow the navigation bar to shrink it rather than pushing either edge control off-screen. Keep `.lineLimit(1)` and a short placeholder (`Find a miner`).
2. **Reveal/hide contract:** reveal after a meaningful upward content movement, not on the first pixel of a drag. Hide only after meaningful downward movement, and only when `searchText.isEmpty && !searchIsFocused`. A focused field or non-empty query must remain available. If the observer reports noisy direction changes, debounce/coalesce state changes at the boundary instead of animating every sample.
3. **iOS 17 compatibility:** `ToolbarItem` with `.principal`, `@FocusState`, `@Environment(\.accessibilityReduceMotion)`, `withAnimation`, and `transition` are iOS 17-safe. Do not make the iOS 17 target depend on newer scroll APIs in new code. If the existing `onGeometryChange` use is retained, verify its availability against the project's actual SDK/availability checks; an iOS 17 fallback is a named-coordinate-space `GeometryReader` + `PreferenceKey` offset observer.

## Two restrained animations (optional third)

1. **Toolbar field enter/exit:** use a short opacity + horizontal scale transition, approximately 180-220 ms, with an ease-out reveal and ease-in removal. Anchor at `.center` so the field stays centered. Under Reduce Motion, use no interpolation: switch the principal content immediately (or opacity-only if product requires continuity). Do not use bounce, spring overshoot, blur, rotation, or a large slide from the screen edge.
2. **Focus affordance:** on focus, animate only a subtle accent stroke/fill change on the field container, approximately 120-160 ms. This gives lively feedback without moving miner readings. Under Reduce Motion, apply the color/border state immediately.
3. **Optional low-cost status cue:** when the search becomes visible, a single SF Symbol magnifying-glass tint/opacity emphasis may settle once. Avoid `symbolEffect` loops, pulsing, shimmer, or per-reading animation. The ticker is already the motion-heavy area and should remain unchanged.

Do not animate `searchText` filtering with list-wide insertion/removal effects. Filtering should update immediately or with a very short non-spatial opacity change, preserving card positions as much as possible. Never use the search reveal animation to imply that hashrate, power, or freshness values changed.

## Reduce Motion and VoiceOver policy

- `accessibilityReduceMotion == true`: no spring, bounce, continuous loop, marquee, or positional transition for search. State changes remain immediate and all content stays readable. Existing ticker behavior is the desired precedent.
- VoiceOver: the field must expose one concise label, `Find a miner`, and its value. The clear button must remain a separately discoverable 44 pt control with `Clear search`. Do not hide the field solely because visual scrolling moved down while it is focused. The `.accessibilityAction(named: "Find a miner")` shortcut should continue to reveal and focus it.
- Dynamic Type: keep the one-line field at ordinary sizes, but never clip or truncate user-entered text in the editable control. At accessibility sizes, prioritize the text field and 44 pt hit targets over decorative animation; verify the toolbar still gives the leading/trailing controls usable space.
- Preserve reading integrity: no animation may obscure, rapidly shift, or visually compete with the hero hashrate, miner status, or freshness text. Motion must be subordinate to search affordance.

## Exact acceptance tests

1. **Reveal:** with VoiceOver off and an empty query, launch on a dashboard with miners. Pull/scroll upward past the chosen reveal threshold. Assert `dashboard.search` exists in the principal toolbar, is visually centered, is one line, and `Find a miner` is visible.
2. **Hide:** with an empty, unfocused field visible, scroll downward past the chosen hide threshold. Assert the field is removed and the `HashFleet` title is restored. Small direction jitter below the threshold must not toggle it.
3. **Query persistence:** enter `ant` and submit. Scroll downward through the dashboard. Assert the field remains visible, text remains `ant`, and filtered miner results remain correct. Clear the query, dismiss focus, then scroll down and assert it can hide.
4. **Focus persistence:** reveal the field, focus it, then scroll down/interactively dismiss the keyboard. Assert the field is not hidden while focused; after focus is lost and the query is empty, a later downward threshold may hide it.
5. **Responsive controls:** test narrow iPhone width, regular iPhone width, landscape, and Dynamic Type accessibility sizes. Assert the field remains centered within available space, stays one line at normal sizes, and leading icon, text field, clear button, and add button each have at least 44 pt hit targets with no overlap.
6. **Reduce Motion:** enable Settings > Accessibility > Motion > Reduce Motion. Repeat reveal/hide and focus tests. Assert no spring/bounce/slide/continuous search animation occurs, state changes complete immediately, and all miner readings remain readable. Existing ticker must remain in its static readable layout.
7. **VoiceOver:** enable VoiceOver and swipe through the toolbar. Assert the search control is announced once as `Find a miner`, the clear action is announced when applicable, and the visual hide rule never removes a focused/queried field from the accessibility flow.
8. **Reading stability:** while a refresh updates hashrate/power/freshness, reveal and hide search repeatedly. Assert no reading is obscured, no ticker cadence changes, and no search motion is mistaken for a metric update.

## GitHub examples and package decision

These are reference implementations, not dependencies to add:

- [Apple `sample-food-truck`](https://github.com/apple/sample-food-truck): official WWDC22 SwiftUI multiplatform sample, MIT licensed, 11 commits, and explicitly documented for Xcode 14.3+. Useful for studying native toolbar/navigation and responsive SwiftUI layout. It is a sample, not a maintained production library, and its older toolchain means APIs must be checked against iOS 17.
- [Apple `sample-backyard-birds`](https://github.com/apple/sample-backyard-birds): official WWDC23 SwiftData/SwiftUI sample, MIT licensed, Xcode 15+, with richer state-driven UI patterns. Useful as a current-era Apple style reference, but it is a sample app and not an animation package or support commitment.
- [Point-Free `swiftui-navigation`](https://github.com/pointfreeco/swiftui-navigation): MIT licensed and contains state-driven SwiftUI examples, but the repository README says it is deprecated in favor of Swift Navigation. Treat it as an architectural example only, not a new dependency for this search interaction.

**Recommendation:** use native SwiftUI equivalents already available in the app: `ToolbarItem(.principal)`, `withAnimation`/`Animation.easeInOut`, `AnyTransition.opacity.combined(with: .scale(scale: 0.98, anchor: .center))`, `@FocusState`, and `accessibilityReduceMotion`. These avoid package licensing, transitive dependency, minimum-OS, and maintenance risk, while directly satisfying this small interaction. Do not add a GitHub animation package for the toolbar field. If a package is considered later, require an active release/issue history, an explicit license, iOS 17 support, no global appearance side effects, and a documented Reduce Motion strategy before adoption.

## Trending-source caveat

The reviewed [GitHub Swift daily trending page](https://github.com/trending/swift?since=daily) was mostly macOS tooling, including Atoll, IINA, CodexBar, and SwiftUI Whisky. It is useful for observing repository activity and implementation patterns, but it is not evidence that a project is an appropriate iOS animation dependency. No trending project should be adopted for this toolbar interaction without confirming iOS 17 support, license, maintenance, accessibility behavior, and package impact. For HashFleet, borrow only the native patterns above and keep the implementation dependency-free.

## Primary references

- Apple SwiftUI `EnvironmentValues.accessibilityReduceMotion`: <https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducemotion>
- Apple SwiftUI `Animation`: <https://developer.apple.com/documentation/swiftui/animation>
- Apple Human Interface Guidelines, Motion: <https://developer.apple.com/design/human-interface-guidelines/motion>
- Local installed SwiftUI SDK (`iPhoneSimulator26.5.sdk`) confirms public `accessibilityReduceMotion` and `ToolbarItemPlacement` declarations. The app itself remains targeted to iOS 17.0, so deployment availability must govern implementation choices.
