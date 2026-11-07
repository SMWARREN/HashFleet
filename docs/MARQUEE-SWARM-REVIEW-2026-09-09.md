# Marquee Performance & Frame Pacing Audit · 2026-09-09

## Overview
This document records the read-only performance audit of the dashboard status marquee (`FleetStatusTicker.swift`, `FleetStatusTickerModel.swift`, and `DashboardView.swift`) in HashFleet. It addresses user observations of intermittent marquee pauses following copy width adjustments, distinguishes code-confirmed mechanisms from hypotheses requiring trace evidence, and outlines a proper local frame pacing diagnostic architecture.

---

## Findings: Code-Confirmed vs. Hypotheses

### 1. Code-Confirmed Findings

- **Viewport Geometry and Visibility Toggling (`FleetStatusTicker.swift:53-59`, `DashboardView.swift:27, 39`)**
  - In `DashboardView`, an outer `GeometryReader` passes `viewport: viewport.frame(in: .global)` down to `FleetStatusTicker`.
  - Inside `FleetStatusTicker`, an `onGeometryChange(for: Bool.self)` modifier continuously evaluates `frame.intersects(viewport)` and writes to `@State private var isVisible`.
  - `shouldCycle` evaluates `!usesStaticLayout && !isPaused && scenePhase == .active && isVisible`.
  - When `shouldCycle` changes (`.onChange(of: shouldCycle, initial: true)`), `marqueeClock.setRunning(running, at: .now)` is called.
  - *Potential boundary behavior, not reproduced*: `intersects(viewport)` can change during scrolling near the viewport edge. Only Boolean changes invoke the geometry action. Pausing while genuinely offscreen is intentional. No trace establishes visibility flapping as the reported in-view stall.

- **Width Preference & Rebase Epoch Adjustments (`FleetStatusTicker.swift:261-264, 274-293`, `FleetStatusTickerModel.swift:203-223`)**
  - `FleetMarqueeTrack` measures the first copy's rendered width via `FleetMarqueeWidthPreferenceKey`.
  - When width changes by > 0.5pt, `applyGeometryChange` calls `clock.preserveOffset` or `clock.reset(at: .now)`.
  - `preserveOffset` computes the existing physical offset at `date` (`.now`), truncates against the new travel distance, and re-anchors `startedAt = date.addingTimeInterval(-newElapsed)`.
  - *Continuity*: `preserveOffset` evaluates the old offset at the rebase instant and continues elapsed time from that instant. A later draw tick alone does not introduce a hold. Native regression tests cover running/paused continuity. Layout changes can still alter which glyph occupies a pixel, but a hardware trace is needed to attribute the reported symptom.

- **TimelineView Frame Invalidation Schedule (`FleetStatusTicker.swift:244-255`)**
  - `TimelineView(.animation(paused: !clock.isRunning || !canScroll))` invalidates the view on every display tick via `context.date`.
  - While `.transaction { $0.animation = nil }` correctly prevents the horizontal offset from inheriting parent ease/spring transitions, the horizontal offset recalculation and view rendering execute on the main actor / main thread.

- **Main-Thread Contention via `@Observable FleetStore` (`DashboardView.swift:27-64`)**
  - `DashboardView` reads multiple observable properties from `store` (`store.devices`, `store.snapshots`, `store.hashrateReading`, celebration triggers).
  - Mutations to observable properties read by `DashboardView.body` can invalidate it. Unrelated properties do not automatically invalidate every observer.
  - *Mechanism*: Re-evaluating `DashboardView` and its child hierarchies (such as `FleetHeroCard`, `FleetChainCard`, `LazyVGrid` miner cards) takes main-thread execution time. Any tick where the main run loop is occupied by view evaluation or layout blocks `TimelineView` from scheduling or rendering the marquee offset for that display frame.

- **Numeric Bounce Preservation (`FleetTheme.swift:79-82`, `FleetStatusTicker.swift:330`)**
  - Ticker items explicitly apply `.fleetNumericUpdate(item.text, reduceMotion: reduceMotion)` which uses `.contentTransition(.numericText())` with a 0.55s easeInOut animation.
  - This existing number bounce effect is intentionally retained per product requirements.

### 2. Hypotheses Requiring Hardware Trace Confirmation

- **Display Server / ProMotion Hitching (Unconfirmed without Instruments Trace)**
  - *Hypothesis*: The device display server or ProMotion dynamically steps refresh rates (e.g. from 120Hz to 60Hz or 80Hz) when overall screen motion is low or scroll views are static, causing apparent unevenness in linear translations.
  - *Required Evidence*: Requires an Instruments profile using the **Core Animation** and **SwiftUI View Body** templates on a physical iOS device to measure display server commit cadences, target timestamp variations, and commit-phase hitch rates.

- **Thermal or Energy Throttling (Unconfirmed without Instruments Trace)**
  - *Hypothesis*: Extended live monitoring may induce thermal throttling that drops frames.
  - *Required Evidence*: Requires Instruments Time Profiler / Energy Log metrics.

---

## Diagnostic Architecture: Local CADisplayLink Frame Pacing

When implementing local diagnostics to investigate pacing and pauses, the distinction between main-thread display readiness and GPU render throughput must remain explicit.

### Critical Measurement Boundary: Main Run Loop vs. GPU
- **What CADisplayLink measures here**: Callback cadence and gaps relative to the scheduled target interval (`targetTimestamp - timestamp`). A slow callback is evidence of scheduling delay, not proof of a missed rendered frame or presentation deadline.
- **What CADisplayLink does NOT measure**: Actual hardware GPU composition rates, display server buffer swapping, or hardware display scanout (FPS). Claims of true GPU rendered FPS cannot be derived from `CADisplayLink`.

### Shipped diagnostic implementation

See `App/Design/FleetPerformanceMonitor.swift` rather than copying a sample display-link target. It uses a weak proxy to avoid a target retain cycle, ignored per-frame accumulators, bounded per-screen history, lifecycle suspension, and one-Hz UI publishing. Tests cover adaptive cadence, percentile math, invalid samples, per-screen isolation, and same-name nested screen lifetimes. The probe does not replace an Instruments trace.

## Prioritized Recommendations

1. **Isolate Viewport Detection**:
   Avoid running `onGeometryChange` with global coordinate frame checks on every scroll subpixel. Consider throttling or using threshold-based visibility hysteresis so transient micro-scrolls do not toggle `isVisible`.
2. **Retain Tested Width Continuity**:
   Preserve the existing rebasing tests. Do not increase thresholds or change clock semantics without a reproducible discontinuity.
3. **Preserve Numeric Bounce**:
   Retain `.fleetNumericUpdate` with `.contentTransition(.numericText())` across all ticker item updates.
4. **Profile on Device with Instruments**:
   Use Core Animation / Core Animation FPS Instruments trace on physical hardware to definitively quantify hitch types (Commit Hitch vs. Render Hitch).
