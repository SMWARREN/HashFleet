# Light-mode palette review · 2026-09-09

Open `index.html` for current swatches, three side-by-side proposal previews, the full role matrix, extra colors, and visual references. This is a local review document, not a new app screen or an applied redesign.

## Recommendation

**A · Warm Graphite** is the smallest coherent refinement: a slightly warmer off-white canvas, white cards, charcoal hashrate cards, the approved icon gold for decorative accents, and a shaded gold for readable small text/actions. B · Clean Mineral is cooler and more technical. C · Soft Gold previews the gold hashrate card in light mode too.

All alternatives preserve the existing dark-mode palette and app artwork. The user has not selected or authorized applying one of these proposals. Only the requested restoration, tighter Pause spacing and Best Shares outlines have been applied to the app.

## What was researched

Primary evidence was preferred over generic “2026 trends” search results.

- [Apple Design Awards announcement, June 2, 2026](https://www.apple.com/newsroom/2026/06/apple-reveals-winners-of-the-2026-apple-design-awards/): Tide Guide won Visuals and Graphics, Moonlitt won Interaction, Guitar Wiz won Inclusivity.
- [Apple's full 2026 winners and finalists](https://developer.apple.com/design/awards/): Structured is a 2026 Inclusivity finalist. Its [current iPhone App Store screenshots](https://apps.apple.com/us/app/structured-daily-planner-todo/id1499198946) provide the light-mode reference, viewed September 9, 2026. This does not establish the screenshot's creation date. Do not confuse an App Store Awards label inside marketing art with the separately verified Design Awards finalist status.
- Tide Guide's actual WWDC26 image shows layered blue cards, cyan charts and strong white labels. Useful principle: a related surface family creates depth while one accent emphasizes data. Its blue hex values were not copied into Hash Fleet.
- Moonlitt's WWDC26 image shows translucent controls over blue photographic content. Useful principle: controls can stay restrained. Photographic or translucent surfaces behind dense mining data are not recommended here.
- Guitar Wiz's WWDC26 image uses purple layered surfaces and colored note markers. Apple specifically highlights Dynamic Type, Increased Contrast and Differentiate Without Color. Mining status must also retain text and symbols, not just colored dots.
- Structured provides white task surfaces and color-coded grouping. Borrow semantic grouping rather than its surrounding pink marketing background.
- [Envato's February 5, 2026 mobile color article](https://elements.envato.com/learn/color-scheme-trends-in-mobile-app-design): calm neutrals, expressive accents and high-contrast accessibility are relevant directions. This is secondary trend/template commentary, not proof that every 2026 app uses those patterns.
- [W3C contrast guidance](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html): 4.5:1 for ordinary text, 3:1 for qualifying large text. Opaque text-role pairs were calculated directly in linearized sRGB.

### Sources not treated as current palette authority

The retrieved Gummble “15 Best Finance App Designs in 2026” roundup included retired Mint and historical Robinhood confetti, alongside web products. Its title alone was insufficient proof of current mobile visuals. Oura's first-party redesign article was actually published November 5, 2025, so it was not labeled a 2026 redesign. Apple's HIG color page and Material's color-role pages returned JavaScript shells through the text fetcher, so their unread body content was not quoted as verified guidance. The Monzo 2026 annual report confirmed a current product context but was not used to infer mobile hex values from marketing-page colors.

## Inventory coverage and limitations

`inventory.json` records every adaptive `FleetTheme` role with both mode values, all explicit numeric RGB declarations in App/ and Widgets/, and the scanned Swift color/style call sites with source paths and line numbers. The HTML shows the entire named light palette and all explicit RGB declarations. Widgets, onboarding peach, the fourth chart series, About's native orange, coin fallback colors, white/black opacity overlays and semantic system styles are included or described separately.

This is not an exhaustive enumeration of every rendered pixel. Native semantic styles, opacity composites, materials, disabled states, system controls and raster artwork do not reduce to one fixed light-mode hex. App icon, brand art and bundled coin assets remain unchanged. No asset palette extraction was substituted for UI token inventory.

The generator guards the current 15-role schema and requires a documented purpose for each role. Re-run it after source changes to refresh call-site line numbers. It is a scoped Swift-source inventory, not a Swift compiler or a complete accessibility audit.

## Reproduce

```sh
python3 docs/research/light-mode-2026/build_palette.py
```

This produces `index.html`, `inventory.json` and `palettes.json` beside the script. No dependencies, app writes, miner commands, analytics or uploads. The board's illustrative readings are explicitly sample data. Apple-hosted reference images need internet access, while the palette previews and swatches work offline.

`palettes.json` records exact unrounded contrast ratios for 15 text/background pairs per palette, 60 total. All must meet 4.5:1. This does not claim that every material, chart, native control or state passes. The subtle comparison border is decorative, not an interactive boundary. Bright icon gold on white is unsuitable for ordinary small text, so all options retain a darker gold for that role.

## Review-board acceptance

- Generator passed all 60 opaque text-pair checks. Minimums: current 4.804:1, A 5.513:1, B 5.253:1, C 5.024:1. Regenerating all three output files produced identical SHA-256 values.
- `node docs/research/light-mode-2026/verify_board.mjs` passed at actual 1480, 390 and 320 px viewports. It verifies `innerWidth`, page scroll width, all four preview bounds, and four reference entries. Node 22+ and locally installed Chrome are required. Set `JCODE_SCRATCH_DIR` to an existing scratch directory. `CHROME_PATH` can override the default macOS Chrome path.
- Desktop and 390 px screenshots were visually inspected. No clipped headings or horizontally cropped preview cards. Tables intentionally scroll within their own wrappers on narrow displays.
- Evidence: `$JCODE_SCRATCH_DIR/hashfleet-palette-layout.json` and `hashfleet-palette-verified-{1480,390,320}.png`. The verifier uses an isolated profile and explicitly closes its browser. It completed with exit 0.
- Initial CLI-only Chrome captures produced images but timed out during teardown. The nominal 390 px screenshot was cropped from a wider layout, so those captures were not accepted as mobile evidence. CDP viewport emulation and the explicit inner-width assertion replaced that flawed check. No app CSS change was needed.
- This is a static research-board review, not acceptance of an applied native palette. The installed app's separate 11 native preference tests and 3 UI tests are recorded in `../../APPEARANCE-ACCEPTANCE-2026-09-09.md`.
