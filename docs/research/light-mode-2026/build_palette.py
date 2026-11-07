"""Build a local-only review board. Never modifies app colors or assets.

Run from any directory with Python 3. Standard library only.
Inventory covers named theme roles, explicit RGB colors and color/style call sites
in App/ and Widgets/. Native semantic colors and artwork are described separately.
"""
from pathlib import Path
import html
import json
import re

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
theme = (ROOT / "App/Design/FleetTheme.swift").read_text()
files = sorted(p for folder in ("App", "Widgets") for p in (ROOT / folder).rglob("*.swift"))
sources = {str(p.relative_to(ROOT)): p.read_text() for p in files}
roles = {}
for name, light, dark in re.findall(r"static let (\w+) = adaptive\(light: (0x[0-9A-F]+|casingGold), dark: (0x[0-9A-F]+|casingGold)\)", theme):
    color = lambda v: "#E9921D" if v == "casingGold" else "#" + v[2:]
    usages = []
    for path, source in sources.items():
        for n, line in enumerate(source.splitlines(), 1):
            if re.search(r"\bFleetTheme\." + name + r"\b", line):
                usages.append({"path": path, "line": n, "code": line.strip()})
    roles[name] = {"light": color(light), "dark": color(dark), "usages": usages}
assert len(roles) == 15, "Review newly added or removed theme roles before regenerating"

explicit = []
callsites = []
for path, source in sources.items():
    for n, line in enumerate(source.splitlines(), 1):
        for match in re.finditer(r"Color\(red: ([\d.]+), green: ([\d.]+), blue: ([\d.]+)\)", line):
            components = [float(x) for x in match.groups()]
            hex_value = "#" + "".join(f"{int(x * 255 + .5):02X}" for x in components)
            explicit.append({"hex": hex_value, "components": components, "path": path, "line": n, "code": line.strip()})
        if re.search(r"Fleet(?:Widget)?Theme\.|Color\(|\.(?:foregroundStyle|foregroundColor|background|fill|stroke|strokeBorder|tint|shadow|opacity|chartForegroundStyleScale)\(", line):
            callsites.append({"path": path, "line": n, "code": line.strip()})

usage = {
    "canvas": "Page background and sheet canvas",
    "surface": "Ordinary cards and data sections",
    "marqueeSurface": "Full-width status strip. Normal colors restored",
    "ink": "Primary text and icons",
    "secondary": "Supporting labels, units and timestamps",
    "accent": "Links, primary actions, selected controls and chart series",
    "charcoal": "Onboarding and live-log dark panels, even in light mode",
    "hashrateSurface": "Fleet total and individual miner hashrate cards",
    "hashrateInk": "Primary text on hashrate cards",
    "hashrateSecondary": "Secondary text on hashrate cards",
    "comparisonBorder": "Solo and both Best Shares outlines: 25% opacity, 0.5 pt",
    "positive": "Online or positive status, chart series",
    "warning": "Warnings and degraded states, chart series",
    "separator": "Dividers and subtle structural lines",
    "buttonInk": "Text on primary action buttons",
}
# These are proposed color roles, not palettes supplied or endorsed by the sources.
current = {k: v["light"] for k, v in roles.items()}
assert set(usage) == set(current), "Every theme role must have a documented purpose"
palettes = [
    {"name": "Current", "tag": "In the app", "note": "Neutral gray, white cards and a charcoal hashrate card.", "colors": current},
    {"name": "A · Warm Graphite", "tag": "Recommended preview", "note": "Warmer background and secondary labels. Keeps the charcoal hero and approved gold.", "colors": dict(current, canvas="#F4F1EB", ink="#242321", secondary="#666058", accent="#875000", hashrateSecondary="#C9C4BD", positive="#326344", warning="#8A5016", separator="#D8D1C5")},
    {"name": "B · Clean Mineral", "tag": "Cooler alternative", "note": "Cool pale-gray surfaces for a more technical instrument-panel feel.", "colors": dict(current, canvas="#F1F3F5", ink="#22272E", secondary="#5C6671", accent="#865000", charcoal="#282D33", hashrateSurface="#282D33", positive="#326B4D", warning="#90551A", separator="#D5DCE2")},
    {"name": "C · Soft Gold", "tag": "Bolder alternative", "note": "Cream surfaces with the gold hashrate card in light mode too. Preview only.", "colors": dict(current, canvas="#F7F3EA", surface="#FFFDF8", ink="#2C271F", secondary="#6B6254", accent="#875000", hashrateSurface="#E9921D", hashrateInk="#201F1E", hashrateSecondary="#49300A", positive="#3C6545", warning="#87521A", separator="#DCD1BF")},
]

def luminance(hex_value):
    rgb = [int(hex_value[i:i+2], 16) / 255 for i in (1, 3, 5)]
    linear = [x / 12.92 if x <= .04045 else ((x + .055) / 1.055) ** 2.4 for x in rgb]
    return sum(x * w for x, w in zip(linear, (.2126, .7152, .0722)))

def contrast(a, b):
    a, b = sorted((luminance(a), luminance(b)))
    return (b + .05) / (a + .05)

pairs = [(fg, bg) for fg in ("ink", "secondary", "accent", "positive", "warning") for bg in ("canvas", "surface")]
pairs += [("buttonInk", "accent"), ("hashrateInk", "hashrateSurface"), ("hashrateSecondary", "hashrateSurface"), ("ink", "marqueeSurface"), ("secondary", "marqueeSurface")]
for p in palettes:
    c = p["colors"]
    p["contrast"] = [{"foreground": a, "background": b, "ratio": contrast(c[a], c[b])} for a, b in pairs]
    assert all(row["ratio"] >= 4.5 for row in p["contrast"]), p["name"]
    p["minimumContrast"] = min(row["ratio"] for row in p["contrast"])

inventory = {"reviewDate": "2026-09-09", "scope": "App and Widgets Swift color roles and call sites. Not every raster pixel or system-material composite.", "themeRoles": roles, "explicitRGB": explicit, "colorCallsites": callsites}
(HERE / "inventory.json").write_text(json.dumps(inventory, indent=2) + "\n")
(HERE / "palettes.json").write_text(json.dumps(palettes, indent=2) + "\n")

def swatch(color):
    return f'<span class="swatch" style="background:{color}" aria-hidden="true"></span><code>{color}</code>'

def preview(p):
    c = p["colors"]
    variables = ";".join(f"--{k}:{v}" for k, v in c.items())
    chips = "".join(f'<div class="chip">{swatch(c[k])}<small>{k}</small></div>' for k in ("canvas", "surface", "ink", "secondary", "accent", "hashrateSurface", "positive", "warning"))
    return f'''<article class="option"><div class="option-title"><span class="eyebrow">{p['tag']}</span><h3>{p['name']}</h3><p>{p['note']}</p></div>
    <div class="phone" style="{variables}"><div class="statusbar">9:41 <span>▰ ▰ ▰</span></div><header><b>Hash Fleet</b><span class="sun" aria-label="Light appearance">☀</span></header>
    <div class="demo">SAMPLE DATA · COLOR STUDY</div><div class="ticker"><span><i></i> Gamma · 1.21 TH/s · 54°C</span><span aria-label="Pause">Ⅱ</span></div>
    <div class="screen"><section class="hero"><small>FLEET HASHRATE</small><div class="big">2.48 <span>TH/s</span></div><div class="hero-meta">2 of 2 online <span>42 W</span></div></section>
    <section class="card"><div class="row"><b>Gamma</b><span class="online">● Online</span></div><div class="metric">1.21 <small>TH/s</small></div><div class="row secondary"><span>Temperature</span><span>54°C</span></div><div class="rule"></div><div class="row"><span class="secondary">Pool</span><span class="link">Bitcoin · Solo</span></div></section>
    <section class="card outlined"><div class="row"><b>Best Shares</b><span class="link">↗</span></div><div class="shares"><div><small>ALL TIME</small><b>1.82 G</b></div><div><small>SESSION</small><b>624 M</b></div></div></section>
    <div class="row small"><span class="warning">△ 1 update available</span><span class="secondary">Just now</span></div><div class="cta">Add miner</div></div></div>
    <p class="contrast">Text-pair minimum <b>{p['minimumContrast']:.2f}:1</b> · 15 pairs checked</p><div class="chips">{chips}</div></article>'''

rows = []
for name, value in roles.items():
    paths = sorted(set(x["path"] for x in value["usages"]))
    details = "".join(f"<li><code>{html.escape(x)}</code></li>" for x in paths)
    rows.append(f'<tr><th scope="row"><code>{name}</code></th><td>{swatch(value["light"])}</td><td>{html.escape(usage[name])}<details><summary>{len(paths)} source files</summary><ul>{details}</ul></details></td></tr>')
explicit_rows = "".join(f'<tr><td>{swatch(x["hex"])}</td><td><code>{html.escape(x["path"])}:{x["line"]}</code><br><small>{html.escape(x["code"])}</small></td></tr>' for x in explicit)
matrix_rows = "".join('<tr><th scope="row">'+name+'</th>'+''.join('<td>'+swatch(p['colors'][name])+'</td>' for p in palettes)+'</tr>' for name in roles)
apple = "https://www.apple.com/newsroom/2026/06/apple-reveals-winners-of-the-2026-apple-design-awards/"
image_base = "https://www.apple.com/newsroom/images/2026/06/apple-reveals-winners-of-the-2026-apple-design-awards/article/Apple-WWDC26-Apple-Design-Awards-"
structured_image = "https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/3b/cb/e6/3bcbe6b7-7c2d-47c4-6e5b-b7e825edb38e/_U00232_treatment__U00281_U0029.jpg/600x1300bb.jpg"
references = [
    ("Structured", "2026 Inclusivity finalist", "A light-mode reference: white canvas, colored task groups and dark labels. Borrow the clear separation of semantic color from the background, not the pink marketing frame.", "https://apps.apple.com/us/app/structured-daily-planner-todo/id1499198946", structured_image),
    ("Tide Guide", "2026 Visuals and Graphics winner", "Actual 2026 Apple screenshot: layered blue surfaces and cyan data lines. Borrow depth and controlled chart emphasis, not its aquatic palette.", apple, image_base + "Tide-Guide_inline.jpg.large.jpg"),
    ("Moonlitt", "2026 Interaction winner", "Actual 2026 Apple screenshot: translucent controls over a blue photographic scene. Borrow restrained controls. Do not put translucent or photographic backgrounds behind dense mining metrics.", apple, image_base + "Moonlitt-Moon-Phase-Tracker_inline.jpg.large.jpg"),
    ("Guitar Wiz", "2026 Inclusivity winner", "Actual 2026 Apple screenshot: dark purple layered cards and distinct colored notes. Apple highlights Differentiate Without Color and Increased Contrast support. Keep text and symbols with mining status colors.", apple, image_base + "Guitar-Wiz_inline.jpg.large.jpg"),
]
reference_cards = "".join(f'<article class="reference"><a href="{url}"><img loading="lazy" src="{image}" alt="{name} mobile interface reference" width="300" height="430"></a><span class="eyebrow">{award}</span><h3>{name}</h3><p>{note}</p><a href="{url}">Original source ↗</a></article>' for name, award, note, url, image in references)

document = '''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Hash Fleet · Light-mode palette review</title><style>
:root{color-scheme:light;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;color:#242321;background:#f8f7f4}*{box-sizing:border-box}body{margin:0}main{max-width:1480px;padding:52px 36px 80px;margin:auto}a{color:#875000;text-underline-offset:4px}h1{font-size:clamp(32px,4vw,58px);letter-spacing:-2px;line-height:1.05;margin:16px 0}h2{font-size:30px;letter-spacing:-.8px;margin:0 0 12px}h3{font-size:21px;margin:8px 0 12px}p{line-height:1.6;margin:8px 0 16px;color:#615b52}code{font-family:ui-monospace,monospace;font-size:12px;overflow-wrap:anywhere}small{font-size:12px}.eyebrow{font-size:11px;letter-spacing:1.4px;font-weight:700;text-transform:uppercase;color:#70675b}.intro{max-width:900px}.notice{margin:24px 0 30px;padding:18px 22px;border:1px solid #ddd5c9;border-radius:16px;background:#fff}.notice p{margin:0}.options{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:24px}.option{min-width:0}.option-title{min-height:156px}.option-title p{font-size:14px}.phone{border:1px solid #d0cdc7;border-radius:32px;overflow:hidden;background:var(--canvas);color:var(--ink);box-shadow:0 14px 30px #2423210d}.statusbar{display:flex;justify-content:space-between;font-size:11px;font-weight:600;padding:18px 20px 8px}.phone header{display:flex;align-items:center;justify-content:space-between;padding:10px 18px;font-size:23px;letter-spacing:-.8px}.sun{color:var(--accent);font-size:22px}.demo{font-size:9px;letter-spacing:1px;color:var(--secondary);padding:6px 18px 12px}.ticker{background:var(--marqueeSurface);display:flex;justify-content:space-between;align-items:center;gap:0;padding:12px 12px;font-size:10px;white-space:nowrap}.ticker i{display:inline-block;background:var(--positive);width:5px;height:5px;border-radius:50%;margin-right:5px}.screen{padding:14px 12px 18px}.hero{padding:20px 16px;background:var(--hashrateSurface);color:var(--hashrateInk);border-radius:22px}.hero small{font-size:9px;letter-spacing:1.2px;color:var(--hashrateSecondary)}.big{font-size:40px;letter-spacing:-1.5px;font-weight:650;margin:8px 0 16px}.big span{font-size:18px;font-weight:400;letter-spacing:0}.hero-meta{display:flex;justify-content:space-between;color:var(--hashrateSecondary);font-size:10px}.card{margin-top:12px;padding:16px;background:var(--surface);border-radius:22px}.row{display:flex;justify-content:space-between;align-items:center;gap:8px;font-size:11px}.row b{font-size:14px}.online{color:var(--positive);font-size:9px}.metric{font-size:27px;font-weight:650;margin:15px 0}.metric small{font-size:12px;font-weight:400;color:var(--secondary)}.secondary{color:var(--secondary)}.rule{height:1px;background:var(--separator);margin:13px 0}.link{color:var(--accent)}.outlined{border:.5px solid #E9921D40}.shares{display:flex;gap:30px;margin-top:18px}.shares div{display:grid;gap:7px}.shares small{font-size:8px;letter-spacing:1px;color:var(--secondary)}.shares b{font-size:21px}.small{margin:14px 3px;font-size:9px}.warning{color:var(--warning)}.cta{color:var(--buttonInk);background:var(--accent);border-radius:14px;padding:12px;text-align:center;font-size:12px;font-weight:600}.contrast{font-size:11px;margin-top:18px}.chips{display:grid;grid-template-columns:1fr 1fr;gap:12px}.chip{display:grid;grid-template-columns:20px 1fr;align-items:center;gap:5px}.chip small{grid-column:2;font-size:10px;color:#70675b}.swatch{display:inline-block;width:20px;height:20px;border:1px solid #0002;border-radius:6px;vertical-align:middle;margin-right:6px;flex-shrink:0}section.chapter{margin-top:64px}.table-wrap{overflow-x:auto;border:1px solid #dedbd4;border-radius:16px;background:#fff}table{width:100%;border-collapse:collapse;text-align:left;font-size:13px}th,td{padding:15px 18px;border-bottom:1px solid #e9e5de;vertical-align:top}th{font-weight:600}td code{font-size:11px}thead th{background:#f0ede7}tr:last-child td,tr:last-child th{border-bottom:0}details{margin-top:8px;color:#70675b}summary{cursor:pointer;font-size:11px}li{margin:6px 0;line-height:1.5}ul{padding-left:20px}.references{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:24px}.reference{min-width:0}.reference img{width:100%;height:360px;object-fit:contain;background:#eeeae3;border-radius:18px;margin:10px 0 20px}.reference p{font-size:13px}.reference a{font-size:13px}.columns{display:grid;grid-template-columns:1fr 1fr;gap:32px}.foot{font-size:12px;margin-top:48px;border-top:1px solid #dedbd4;padding-top:24px}@media(max-width:1120px){.options,.references{grid-template-columns:repeat(2,minmax(0,1fr))}.phone{max-width:360px;margin:auto}.option-title{min-height:125px}}@media(max-width:620px){main{padding:28px 18px 50px}h1{letter-spacing:-1px}.options,.references,.columns{grid-template-columns:1fr}.option-title{min-height:0}.option{margin-top:18px}.phone{width:100%;max-width:360px}.chips{margin:0 auto;max-width:360px}.contrast{text-align:center}th,td{padding:12px}.reference img{height:380px}.notice{padding:16px}section.chapter{margin-top:42px}}@media(prefers-reduced-motion:reduce){*{scroll-behavior:auto}}
</style></head><body><main><div class="intro"><span class="eyebrow">HASH FLEET · DESIGN REVIEW · 09 SEPTEMBER 2026</span><h1>Same gold.<br>A better light-mode balance.</h1><p>The current colors, three coordinated directions, and real 2026 mobile-app references. These are our proposed Hash Fleet palettes, not copied hex values or recommendations made specifically for us by the referenced apps.</p></div>
<div class="notice"><p><b>Preview only.</b> No proposed palette has been applied. The app keeps its layered graphite dark mode. Its marquee is back to <b>black in dark mode and white in light mode</b>, with closer Pause spacing and subtle Best Shares borders.</p></div>
<div class="options">''' + "".join(preview(p) for p in palettes) + '''</div>
<section class="chapter"><h2>My recommendation: A · Warm Graphite</h2><div class="columns"><p>Warm the canvas slightly, keep white cards above it, retain the charcoal hashrate card, and use the icon gold as an accent rather than small text. This preserves the depth you asked for without turning light mode into beige-on-beige or every card into a colored panel.</p><p><b>Keep meaning stable.</b> Green means online or positive. Amber means caution, accompanied by words or a symbol. Coin icons keep their own identities. Dark mode and the approved app artwork stay unchanged in every proposal.</p></div></section>
<section class="chapter"><h2>Every current theme role</h2><p>Exact light-mode values from <code>App/Design/FleetTheme.swift</code>. Expand a row for source files. The JSON inventory includes line numbers and code, plus the corresponding dark-mode values.</p><div class="table-wrap"><table><thead><tr><th>Role</th><th>Light value</th><th>Used for</th></tr></thead><tbody>''' + "".join(rows) + '''</tbody></table></div></section>
<section class="chapter"><h2>All proposal values</h2><p>The previews above emphasize eight colors. This matrix includes every existing theme role so implementation would not silently miss text, outlines or button colors.</p><div class="table-wrap"><table><thead><tr><th>Role</th>''' + "".join('<th>'+p['name']+'</th>' for p in palettes) + '''</tr></thead><tbody>''' + matrix_rows + '''</tbody></table></div></section>
<section class="chapter"><h2>Colors outside the main theme</h2><p>Explicit RGB declarations in app and widget code, converted to the nearest 8-bit sRGB hex. Repeated colors are retained so every declaration remains traceable. These have not been recolored by this proposal.</p><div class="table-wrap"><table><thead><tr><th>Color</th><th>Declaration</th></tr></thead><tbody>''' + explicit_rows + '''</tbody></table></div>
<div class="columns"><div><h3>Dynamic and composited colors</h3><p>Native <code>.primary</code>, <code>.secondary</code>, system orange, tint, materials and disabled controls are resolved by iOS. They do not have one trustworthy fixed hex across appearance, accessibility settings and backgrounds. White/black opacity overlays, badge fills at 9%, default card outlines at 4.5%, and comparison outlines at 25% also depend on what is behind them. The inventory retains those call sites rather than inventing a flat palette value.</p></div><div><h3>Separate surfaces and artwork</h3><p>Widgets still have their own older cream/orange palette. Onboarding uses peach, and live logs use translucent white text on charcoal. The fourth chart series uses slate blue. About uses system orange. These need an explicit follow-up decision if you choose a palette. AppIcon, HashFleetBrand and five bundled coin images are artwork, not flat UI colors. Their pixel palettes remain untouched.</p></div></div></section>
<section class="chapter"><h2>Real mobile apps, checked in 2026</h2><p>Apple's June 2, 2026 awards confirm these winners and finalists. Screenshots are linked to their publishers. Structured's image is the current App Store listing viewed September 9, not a claim that the screenshot itself was created that day. The other three are Apple's dated WWDC26 images.</p><div class="references">''' + reference_cards + '''</div></section>
<section class="chapter"><h2>What the research supports</h2><ul><li><a href="''' + apple + '''">Apple Design Awards · June 2, 2026</a>: cohesive themes, readable data, platform-appropriate controls and accessibility. There is no universal “2026 palette.”</li><li><a href="https://elements.envato.com/learn/color-scheme-trends-in-mobile-app-design">Envato · February 5, 2026</a>: calm neutrals, expressive accents and high contrast are relevant directions. This is trend commentary and template marketing, not an accessibility standard.</li><li><a href="https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html">W3C contrast guidance</a>: 4.5:1 for ordinary text, 3:1 for qualifying large text. All 15 tested text-role pairs per proposal exceed 4.5:1. Decorative outlines are intentionally subtle and are not the sole signifier of a control.</li></ul><p><b>Contrast caveat:</b> the icon gold <code>#E9921D</code> against white is only ''' + f"{contrast('#E9921D', '#FFFFFF'):.2f}:1" + '''. Keep it for fills, artwork and decoration. Use shaded gold for small links and actions. These checks cover opaque color pairs, not every native UI state, translucent material, chart or image.</p><p>Read <a href="README.md">research notes</a>, <a href="inventory.json">the complete source inventory</a>, or <a href="palettes.json">all proposal values and contrast measurements</a>.</p></section>
<p class="foot">Local review document. Sample miner readings are illustrative, not live telemetry. No analytics, forms, uploads or app-setting writes. Reference images load from Apple and link to their original sources. Regenerate with <code>python3 docs/research/light-mode-2026/build_palette.py</code>.</p></main><script>window.addEventListener('load',()=>{document.documentElement.dataset.layoutOverflow=String(document.documentElement.scrollWidth>innerWidth);document.documentElement.dataset.previewCount=String(document.querySelectorAll('.phone').length)});</script></body></html>'''
(HERE / "index.html").write_text(document + "\n")
print(f"Wrote board, {len(roles)} theme roles, {len(explicit)} explicit RGB declarations, {len(callsites)} color/style call sites")
print("All 60 proposal text/background checks pass 4.5:1")
