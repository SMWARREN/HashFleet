"""Derive UI roles from the two exact single-miner images. No app writes."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
samples = {m['mode']: {s['name']: s['meanHex'] for s in m['samples']}
           for m in json.loads((ROOT / 'extracted.json').read_text())}
d, l = samples['dark'], samples['light']

def rgb(h):
    return [int(h[i:i+2], 16) for i in (1, 3, 5)]

def blend(a, b, amount):
    return '#' + ''.join(f'{int(x * (1-amount) + y * amount + .5):02X}' for x, y in zip(rgb(a), rgb(b)))

def luminance(h):
    v = [x / 255 for x in rgb(h)]
    v = [x / 12.92 if x <= .04045 else ((x+.055)/1.055)**2.4 for x in v]
    return sum(x*w for x, w in zip(v, (.2126, .7152, .0722)))

def contrast(a, b):
    low, high = sorted((luminance(a), luminance(b)))
    return (high+.05)/(low+.05)

roles = {}
def role(name, light, dark, recipe):
    roles[name] = dict(light=light, dark=dark, derivation=recipe)

bright_gold = blend(d['casingGold'], d['displayGlow'], .36)
panel_secondary = blend(l['metalHighlight'], l['ivoryBackdrop'], .60)
hero_secondary = blend(d['bronzeEdge'], d['bladeShadow'], .45)
light_canvas = blend(l['ivoryBackdrop'], l['metalHighlight'], .20)
role('canvas', light_canvas, d['bladeShadow'], 'Light: ivory backdrop + 20% metallic midtone. Dark: blade shadow.')
role('surface', l['ivoryBackdrop'], d['hubGraphite'], 'Direct regional means: light ivory backdrop, dark fan hub.')
role('raised', l['litBackdrop'], d['fanHighlight'], 'Direct regional means: light lit backdrop, dark blade highlight.')
role('ink', d['bladeShadow'], l['ivoryBackdrop'], 'Direct sampled graphite and ivory, neither pure black nor pure white.')
role('secondary', blend(d['hubGraphite'], l['metalHighlight'], .35), panel_secondary, 'Light: graphite + 35% metallic midtone. Dark: metallic midtone + 60% ivory.')
role('accent', d['bronzeEdge'], bright_gold, 'Light: sampled bronze. Dark: casing gold + 36% display glow, lifted to pass on raised graphite.')
role('charcoal', d['hubGraphite'], d['fanHighlight'], 'Branded dark inset for onboarding/live logs, with dedicated panel text.')
role('panelInk', l['ivoryBackdrop'], l['ivoryBackdrop'], 'Sampled ivory on dark insets in either mode.')
role('panelSecondary', panel_secondary, panel_secondary, 'Metallic midtone + 60% ivory, opaque rather than fragile white opacity.')
role('panelAccent', bright_gold, bright_gold, 'Casing gold + 36% display glow, valid on both dark inset levels.')
role('hashrateSurface', l['frontGold'], d['casingGold'], 'Direct gold material sample from the matching mode artwork.')
role('hashrateInk', d['bladeShadow'], d['bladeShadow'], 'Sampled deep graphite on gold.')
role('hashrateSecondary', hero_secondary, hero_secondary, 'Bronze + 45% blade shadow. Unmodified bronze failed 4.5:1 on gold.')
role('marqueeSurface', blend(l['ivoryBackdrop'], l['frontGold'], .24), blend(d['hubGraphite'], d['bronzeEdge'], .26), 'Light: ivory + 24% casing gold. Dark: graphite + 26% bronze.')
role('marqueeInk', d['bronzeEdge'], l['ivoryBackdrop'], 'Sampled bronze on pale gold, sampled ivory on deep bronze.')
role('marqueeSecondary', blend(d['bronzeEdge'], d['hubGraphite'], .25), panel_secondary, 'Light: bronze + 25% graphite. Dark: opaque silver-ivory.')
role('comparisonBorder', l['bronzeEdge'], d['displayGlow'], 'Direct bronze/glow samples. Decorative outlines use 25% opacity, not control boundaries.')
role('positive', '#356447', '#A5CAA5', 'Functional sage companion, NOT extracted from the gold/gray artwork. Retains recognizable success/online semantics with text.')
role('warning', blend(d['bronzeEdge'], l['bronzeEdge'], .60), blend(d['displayGlow'], l['ivoryBackdrop'], .50), 'Light: blend of sampled bronzes. Dark: sampled glow + 50% ivory. Always accompanied by warning wording/symbols.')
role('separator', blend(l['metalHighlight'], light_canvas, .55), blend(d['hubGraphite'], l['metalHighlight'], .50), 'Low-emphasis structural separators from metal and surface blends. Not interactive outlines.')
role('controlBorder', d['metalHighlight'], l['metalHighlight'], 'Sampled metallic midtones for visible control boundaries, checked at 3:1.')
role('chartFourth', d['metalHighlight'], blend(l['metalHighlight'], l['ivoryBackdrop'], .30), 'Metallic data series replacing unrelated hardcoded slate blue.')
role('buttonInk', l['ivoryBackdrop'], d['bladeShadow'], 'Sampled ivory on bronze actions, sampled graphite on bright-gold actions.')

checks = []
for mode in ('light', 'dark'):
    c = {name: value[mode] for name, value in roles.items()}
    pairs = [(fg, bg, 4.5) for fg in ('ink', 'secondary', 'accent', 'positive', 'warning') for bg in ('canvas', 'surface', 'raised')]
    pairs += [(fg, 'charcoal', 4.5) for fg in ('panelInk', 'panelSecondary', 'panelAccent')]
    pairs += [(fg, 'hashrateSurface', 4.5) for fg in ('hashrateInk', 'hashrateSecondary')]
    pairs += [(fg, 'marqueeSurface', 4.5) for fg in ('marqueeInk', 'marqueeSecondary', 'positive', 'warning')]
    pairs += [('buttonInk', 'accent', 4.5)]
    pairs += [(fg, bg, 3) for fg in ('controlBorder', 'chartFourth') for bg in ('canvas', 'surface', 'raised')]
    for fg, bg, minimum in pairs:
        ratio = contrast(c[fg], c[bg])
        checks.append(dict(mode=mode, foreground=fg, background=bg, ratio=ratio, minimum=minimum))
        assert ratio >= minimum, (mode, fg, bg, ratio, minimum)

output = dict(roles=roles, contrastChecks=checks, blendSpace='encoded sRGB, rounded to nearest 8-bit value; contrast computed after linearization')
(ROOT / 'roles.json').write_text(json.dumps(output, indent=2) + '\n')
for name, value in roles.items():
    print(f"static let {name} = adaptive(light: 0x{value['light'][1:]}, dark: 0x{value['dark'][1:]})")
print(f'{len(checks)} text and non-text contrast checks passed')
