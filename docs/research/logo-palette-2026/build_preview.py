"""Build a self-contained-layout comparison page using actual native screenshots."""
import html
import json
from pathlib import Path

root = Path(__file__).resolve().parent
palette = json.loads((root / 'roles.json').read_text())
roles = palette['roles']
rows = ''.join(
    '<tr><th>' + html.escape(name) + '</th>' + ''.join(
        f'<td><span class="swatch" style="background:{role[mode]}"></span><code>{role[mode]}</code></td>'
        for mode in ('light', 'dark')) + '<td>' + html.escape(role['derivation']) + '</td></tr>'
    for name, role in roles.items())
checks = palette['contrastChecks']
minimum = min(c['ratio'] for c in checks if c['minimum'] == 4.5)
page = '''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Hash Fleet · Single-miner palette</title><style>
*{box-sizing:border-box}body{margin:0;background:#EBE3DA;color:#21201E;font:16px/1.55 system-ui,sans-serif}main{max-width:1120px;margin:auto;padding:40px 24px}h1{font-size:clamp(32px,5vw,58px);line-height:1.08;letter-spacing:-.04em;margin:12px 0 20px}h2{line-height:1.2}.eyebrow{font-size:12px;letter-spacing:.14em;text-transform:uppercase;color:#743A03;font-weight:700}.lede{max-width:780px;color:#5C5854}.examples{display:grid;grid-template-columns:1fr 1fr;gap:24px;margin:32px 0}figure{margin:0;padding:24px;border-radius:24px;background:#FDF7EE;min-width:0}figure.dark{background:#21201E;color:#FDF7EE}figure img{display:block;width:100%;max-width:360px;height:auto;margin:20px auto 0;border-radius:24px}figcaption strong{display:block;font-size:24px}figcaption span{font-size:14px}section{background:#FDF7EE;border-radius:24px;padding:24px;margin:24px 0}.table-scroll{overflow:auto}table{border-collapse:collapse;width:100%;font-size:14px}th,td{text-align:left;vertical-align:top;padding:12px 8px;border-bottom:1px solid #CABFB6}td:nth-child(2),td:nth-child(3){white-space:nowrap}code{font-size:12px}.swatch{display:inline-block;width:18px;height:18px;border:1px solid #897869;border-radius:5px;vertical-align:middle;margin-right:8px}a{color:#743A03}li{margin:8px 0}@media(max-width:650px){main{padding:24px 16px}.examples{grid-template-columns:1fr}figure,section{padding:20px}th,td{padding:10px 6px}}
</style><main><div class="eyebrow">Hash Fleet · Logo-derived appearance · September 2026</div>
<h1>One miner. Two native modes.</h1><p class="lede">Colors sampled from the exact single-miner dark logo and the supplied ivory-background version. The original artwork is preserved. These are screenshots of the running SwiftUI app in its labeled, read-only demo, not generated mockups.</p>
<div class="examples"><figure><figcaption><strong>Ivory & bronze</strong><span>Warm canvas, ivory cards, readable bronze actions and a gold hashrate card.</span></figcaption><img src="screenshots/light-dashboard.png" alt="Actual Hash Fleet light-mode dashboard with the ivory single-miner logo at top left"></figure>
<figure class="dark"><figcaption><strong>Graphite & gold</strong><span>Layered graphite, ivory text, luminous gold actions and a bronze ticker.</span></figcaption><img src="screenshots/dark-dashboard.png" alt="Actual Hash Fleet dark-mode dashboard with the dark single-miner logo at top left"></figure></div>
<section><h2>Color decisions</h2><ul><li>No pure-white or pure-black custom canvas, card, ticker or text tokens. Native iOS chrome, shadows and the unchanged artwork can still contain black or white.</li><li>Raw gold is used for the hashrate surface, not small text on ivory. Bronze makes light-mode actions readable.</li><li>Dark action gold is a documented blend of the casing and display glow. It remains legible even on the brightest graphite surface.</li><li>Sage is a functional online/success companion, not a claimed logo extraction. Status labels and symbols preserve meaning without color alone.</li></ul><p>CHECK_SUMMARY</p></section>
<section><h2>Exact UI roles</h2><div class="table-scroll"><table><thead><tr><th>Role</th><th>Light</th><th>Dark</th><th>Provenance / purpose</th></tr></thead><tbody>ROLE_ROWS</tbody></table></div></section>
<section><h2>Reproducible evidence</h2><p>Regional sRGB means, median values, nearest actual pixels, source hashes and sample rectangles are recorded in <a href="extracted.json">extracted.json</a>. Exact blend recipes and contrast calculations are in <a href="roles.json">roles.json</a>. See <a href="README.md">the acceptance notes</a> for native test evidence and limits.</p></section></main></html>'''
page = page.replace('ROLE_ROWS', rows).replace('CHECK_SUMMARY',
    f'{len(checks)} specified contrast checks pass. Lowest tested normal-text contrast: {minimum:.2f}:1 (minimum 4.5:1). Control-boundary and fourth-chart-series roles are checked at 3:1. Decorative low-opacity outlines are not presented as accessible control boundaries.')
(root / 'index.html').write_text(page)
print('Built index.html from roles.json and native screenshot references')
