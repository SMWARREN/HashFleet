"""User-requested neutral bases with the existing logo and functional accents."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
previous = json.loads((ROOT.parent / 'logo-palette-2026/roles.json').read_text())
roles = {}
def role(name, light, dark, reason):
    roles[name] = dict(light=light, dark=dark, derivation=reason)

role('canvas', '#FFFFFF', '#000000', 'Explicit user preference: start light mode with white and dark mode with black.')
role('surface', '#F5F5F5', '#21201E', 'Neutral light cards and sampled blade graphite. No cream or brown surface tint.')
role('raised', '#E5E5E5', '#373737', 'Visible neutral silver and sampled fan-hub gray on individual miner cards, distinct from fleet summary surfaces and white/black canvas.')
role('ink', '#21201E', '#FFFFFF', 'Sampled graphite on light surfaces, neutral white on dark surfaces.')
role('secondary', '#595959', '#BDBDBD', 'Neutral secondary gray, replacing the previous warm metallic text blend.')
role('accent', '#8A5000', '#E9931E', 'Contrast-safe shaded gold for small light-mode actions, sampled casing gold in dark mode.')
role('charcoal', '#111111', '#111111', 'Graphite insets in both modes, with dedicated high-contrast panel text.')
role('panelInk', '#FFFFFF', '#FFFFFF', 'White text on graphite insets.')
role('panelSecondary', '#BDBDBD', '#BDBDBD', 'Neutral silver-gray on graphite insets.')
role('panelPositive', '#A5CAA5', '#A5CAA5', 'Sage status on black-backed panels in either appearance.')
role('panelAccent', '#E9931E', '#E9931E', 'Sampled casing gold, readable on both graphite levels.')
role('hashrateSurface', '#111111', '#F5F5F5', 'Opposite-mode contrasting neutral hashrate panels, replacing broad orange fields.')
role('hashrateInk', '#FFFFFF', '#111111', 'High-contrast primary reading without contours or shadows.')
role('hashrateSecondary', '#BDBDBD', '#595959', 'Distinct neutral units and captions with body-text contrast.')
role('hashrateAccent', '#E9931E', '#8A5000', 'Restrained orange accents with body-text contrast on the corresponding panel.')
role('hashrateSkeleton', '#262626', '#E0E0E0', 'Static decorative loading placeholder, not text or live telemetry.')
role('marqueeSurface', '#FFFFFF', '#000000', 'No separate marquee background: it blends into the page canvas in each mode.')
role('marqueeInk', '#21201E', '#FFFFFF', 'Graphite and white ticker text.')
role('marqueeSecondary', '#595959', '#BDBDBD', 'Neutral secondary ticker text.')
role('comparisonBorder', '#E9931E', '#FED028', 'Casing gold and sampled display glow, used only as subtle decorative outlines.')
role('positive', '#356447', '#A5CAA5', 'Functional sage online/success companion, not a logo sample. Status wording remains.')
role('warning', '#864705', '#FEE48B', 'Retained contrast-safe warning gold with labels and symbols.')
role('separator', '#CCCCCC', '#606060', 'Neutral low-emphasis structural separators, not interactive boundaries.')
role('controlBorder', '#897869', '#A19489', 'Retain sampled metal for visible control boundaries, checked at 3:1.')
role('chartFourth', '#897869', '#BDB2A7', 'Retain metallic chart series so brand material colors are not discarded.')
role('buttonInk', '#FFFFFF', '#21201E', 'White on shaded-gold actions and graphite on bright-gold actions.')

def luminance(hex_value):
    values = [int(hex_value[i:i+2], 16) / 255 for i in (1, 3, 5)]
    linear = [v / 12.92 if v <= .04045 else ((v + .055) / 1.055) ** 2.4 for v in values]
    return sum(v * w for v, w in zip(linear, (.2126, .7152, .0722)))

checks = []
requirements = [dict(check) for check in previous['contrastChecks']]
for check in requirements:
    if check['background'] == 'hashrateSurface':
        check['minimum'] = 7 if check['foreground'] == 'hashrateInk' else 4.5
for mode in ['light', 'dark']:
    requirements.append(dict(mode=mode, foreground='hashrateAccent', background='hashrateSurface', minimum=4.5))
    for foreground in ['panelPositive']:
        requirements.append(dict(mode=mode, foreground=foreground, background='charcoal', minimum=4.5))
for check in requirements:
    mode, fg, bg = (check[key] for key in ('mode', 'foreground', 'background'))
    low, high = sorted(luminance(roles[name][mode]) for name in (fg, bg))
    ratio = (high + .05) / (low + .05)
    assert ratio >= check['minimum'], (mode, fg, bg, ratio)
    checks.append(dict(check, ratio=ratio, passes=True))
(ROOT / 'roles.json').write_text(json.dumps(dict(roles=roles, contrastChecks=checks), indent=2) + '\n')
passed = sum(check['passes'] for check in checks)
print(f'{len(roles)} role pairs: {passed}/{len(checks)} contrast checks pass; {len(checks) - passed} exceptions')
