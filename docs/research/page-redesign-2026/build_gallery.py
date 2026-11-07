#!/usr/bin/env python3
"""Package original screenshots and generated concepts without modifying image pixels."""
from pathlib import Path
import argparse, hashlib, html, json, shutil, subprocess

ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent
BOARDS = [
 ('detail', 'Miner detail', '1789040845424', 'Telemetry hierarchy proposal. Preserve missing, stale and zero states.'),
 ('fleet', 'Welcome, Add Miner, Fleet, History', '1789041401900', 'History is a dashboard state, not a separate existing route. Chart units and probabilities must come from source models.'),
 ('forms', 'Settings hub, General, Cooling, Display', '1789041904073', 'Demo remains read only. Firmware encoding ranges are not hardware-safe ranges.'),
 ('tuning', 'Manual tuning, Pools, Guided setup, Custom JSON', '1789041983117', 'No tuning presets are implemented. Pool drafts must preserve the exact full-slot semantics. Custom JSON always retains typed review.'),
 ('diagnostics', 'Diagnostics, Live console, Compatibility, Endpoints', '1789042700676', 'Diagnostics is currently an inline disclosure. Use the refinement board for compatibility. Endpoint paths and capabilities must follow MinerEndpoint.swift, not image text.'),
 ('controls', 'Advanced tools, Request editor, Confirmation, Siri', '1789042786344', 'Hardware commands authenticate and confirm before sending. Typed APPLY remains for raw JSON, voltage, credentials, pool routing and uploads. Native quick review still requires risk acknowledgment and a final send tap.'),
 ('system', 'Settings, Preferences, Widgets, Live Activity', '1789043626454', 'Widget and Live Activity columns are superseded by the refinement board. Pool icon demo previews appearance only, not routing. Final colors must use existing neutral theme tokens.'),
 ('network', 'Network insights, CKPool, Pool icon demo, About', '1789043719434', 'Example statistics are synthetic, not live readings or financial promises. Provider disclosure remains mandatory.'),
 ('states', 'Launch, Frame pacing, Offline, Firmware upload', '1789043806534', 'Launch is exploratory only. Preserve the existing black logo launch unless separately approved. Frame pacing remains off by default.'),
 ('refinements', 'Widgets, Live Activity, Compatibility, Web upload', '1789045079832', 'Preferred aggregate-only previews. Correction required before implementation: compatibility field coverage is derived from system info, not solely ASIC. Remove the image’s FROM /API/SYSTEM/ASIC subtitle. Use existing navigation back affordances.')
]
# IDs represent existing route families or explicit states, never one route per scroll image.
PAGES = [
 ('launch','Launch overlay',['04'],'states','State, not a new account/onboarding flow.'),
 ('dashboard','Fleet dashboard',['01','05','06','07','08','10','11','48'],'fleet','Empty/demo/light and history states share one route.'),
 ('add','Add Miner sheet',['02','03'],'fleet','Address input and discovery remain user initiated.'),
 ('miner','Miner detail',['18','19','20','21','22'],'detail','Diagnostics and advanced tools disclosures are inline states. Diagnostics concept also appears on its own board.'),
 ('miner-settings','Settings & pools',['23','24'],'forms','Easy and Expert share one route.'),
 ('general','General',['25'],'forms','Hostname and on-device statistics interval.'),
 ('cooling','Cooling',['26'],'forms','Automatic/manual fan controls and firmware-dependent fields.'),
 ('display','Display',['27'],'forms','Display settings depend on firmware support.'),
 ('pools','Pools',['28'],'tuning','Exact primary/fallback slot drafts, no immediate pool switching.'),
 ('guided','Guided Pool Setup',['29','30'],'tuning','Choosing a preset prepares a draft, never sends it.'),
 ('tuning','Manual tuning',['31'],'tuning','Frequency and core voltage, without invented safe presets.'),
 ('advanced','Advanced tools',['32'],'controls','Routes to endpoint and custom JSON tools.'),
 ('json','Custom JSON',['51'],'tuning','Unknown keys preserved in local JSON object. Format, paste/import and stage for review.'),
 ('catalog','Endpoint explorer',['35'],'diagnostics','Read/write catalog, capability unverified unless actually probed.'),
 ('read','Read endpoint editor',['36'],'diagnostics','Generic endpoint template. This screenshot shows System info, not every endpoint response.'),
 ('patch','JSON PATCH editor',['32b'],'controls','Exact request review, not immediate send.'),
 ('restart','Restart request editor',['37'],'controls','Same endpoint template, bodyless hardware command variant.'),
 ('confirm','Write confirmation sheet',['38','54','55'],'controls','Loopback fixture screenshots, not a live miner. Includes optional native power-user review.'),
 ('firmware','Upload firmware',['52'],'states','File selection followed by high-risk typed review, maximum 16 MiB.'),
 ('web','Upload web interface',['53'],'refinements','Distinct POST /api/system/OTAWWW upload variant.'),
 ('compatibility','Check compatibility',['33','34'],'refinements','GET system info and ASIC only. Never claim write support based on a read.'),
 ('console','Live console',['39'],'diagnostics','Logs and Telemetry states. Demo does not connect.'),
 ('network','Network insights',['14','15'],'network','Public provider data, timestamps and honest estimation.'),
 ('ckpool','CKPool lookup',['16','17'],'network','Public account lookup, never wallet access.'),
 ('icons','Pool icon demo',['12','13'],'network','Appearance preview only, no routing changes.'),
 ('settings','Settings tab',['40','49'],'system','Root monitoring/system navigation.'),
 ('preferences','Fleet preferences',['41'],'system','Appearance, sorting, readings and optional public data.'),
 ('widgets','Widgets',['42'],'refinements','Explicit sharing opt-in, aggregate saved snapshots only.'),
 ('activity','Live Activity',['43'],'refinements','User started, no background miner control.'),
 ('siri','Shortcuts & Controls',['44'],'controls','Saved summary, launcher and confirmed hardware actions.'),
 ('fps','Frame pacing',['45'],'states','Local callback timing, not GPU FPS. Disabled by default.'),
 ('about','About',['46','47','50'],'network','Privacy, project information and hardware limitations.'),
 ('offline','Offline settings state',['56'],'states','Read-only cached settings. Same General route, not another page.')
]

def esc(s): return html.escape(str(s), quote=True)
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()

def main():
 p=argparse.ArgumentParser(); p.add_argument('--captures',type=Path,default=Path.home()/'.jcode/scratch/axe-page-capture/screenshots'); p.add_argument('--generated',type=Path,default=Path.home()/'.jcode/generated-images'); args=p.parse_args()
 for name in ['current','proposals']: (OUT/name).mkdir(parents=True,exist_ok=True)
 captures=[]
 for f in sorted(args.captures.glob('*.png')):
  dest=OUT/'current'/f.name; shutil.copy2(f,dest)
  captures.append({'file':'current/'+f.name,'sha256':sha(dest),'captured_mtime':f.stat().st_mtime})
 boards=[]
 for ident,title,prefix,note in BOARDS:
  files=list(args.generated.glob(prefix+'-*.png')); assert len(files)==1,(prefix,files)
  src=files[0]; dst=OUT/'proposals'/(ident+'.png'); shutil.copy2(src,dst)
  meta=json.loads(src.with_suffix('.json').read_text())
  boards.append({'id':ident,'title':title,'note':note,'file':'proposals/'+dst.name,'sha256':sha(dst),'original':src.name,'prompt':meta['revised_prompt'],'generator':meta.get('native_tool'),'provider':meta.get('provider')})
 pages=[]
 for ident,title,prefixes,board,note in PAGES:
  files=[c['file'] for c in captures if Path(c['file']).stem.split('_')[0] in prefixes]
  pages.append({'id':ident,'title':title,'current':files,'board':board,'note':note,'capture_status':'captured' if files else 'pending'})
 manifest={'schema':1,'date':'2026-09-10','source_head':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),'source_state':'Functional changes present in working tree during capture. Multiple capture runs, not one atomic snapshot. Artwork changes belong to a separate task.','boards':boards,'captures':captures,'pages':pages}
 (OUT/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
 css='''*{box-sizing:border-box}html{scroll-behavior:smooth}body{margin:0;background:#10100f;color:#f3f0eb;font:16px/1.5 system-ui}header,main{max-width:1500px;margin:auto;padding:28px}h1{font-size:clamp(30px,5vw,56px);line-height:1.1}h2{font-size:28px}a{color:#ffc267}nav{position:sticky;top:0;background:#181714f5;padding:12px 28px;z-index:2;display:flex;gap:24px;flex-wrap:wrap;border-bottom:1px solid #45413b}section{scroll-margin-top:90px}.notice,article,figure{background:#211f1b;border:1px solid #45413b;border-radius:16px;padding:20px;margin:20px 0}.notice{border-color:#a06b20}figure img{display:block;width:100%;height:auto}figure.portrait img{max-width:380px;margin:auto}figcaption{margin-top:14px}input{width:min(100%,600px);padding:14px;background:#292621;border:1px solid #71695d;color:white;border-radius:9px;font:inherit}.thumbs{display:flex;gap:14px;overflow:auto;padding:14px 0}.thumbs img{height:350px;width:auto;border-radius:10px}small,.muted{color:#bfb8ae}.tag{font-size:12px;letter-spacing:.08em;text-transform:uppercase;color:#ffc267}summary{cursor:pointer;padding:10px}article:target,figure:target{outline:2px solid #ffb03b}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(290px,1fr));gap:20px}.grid article{margin:0}button{font:inherit}footer{padding:35px;color:#bfb8ae}@media(prefers-reduced-motion:reduce){html{scroll-behavior:auto}}'''
 body=f'''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Hash Fleet · Page redesign review</title><style>{css}</style><header><span class="tag">Hash Fleet / Design review / September 10, 2026</span><h1>Current pages.<br>Proposed next direction.</h1><p>{len(captures)} original screenshots · {len(pages)} route families and explicit states · {len(boards)} generated proposal images.</p><div class="notice"><strong>Approval gallery, not an implemented redesign.</strong> Functional updates are separate. Generated images are visual references, not API specifications. Source behavior, review requirements, privacy and accessibility take precedence. Notes below identify superseded columns and required corrections.</div></header><nav><a href="#pages">Current pages & context</a><a href="#boards">Proposal boards</a><a href="manifest.json">Provenance manifest</a></nav><main><section id="pages"><h2>Every route, with context</h2><p>Scroll positions, appearances and disclosures are grouped together rather than counted as separate pages. Generic endpoint and system file-picker variants are not unique custom layouts.</p><label for="search">Find a page</label><br><input id="search" type="search" placeholder="Try cooling, Siri, JSON, widgets…"><div id="page-list">'''
 for page in pages:
  thumbs=''.join(f'<a href="{esc(f)}" target="_blank" rel="noopener"><img loading="lazy" src="{esc(f)}" alt="{esc(Path(f).stem)}"></a>' for f in page['current'])
  body+=f'<article id="page-{page["id"]}" data-search="{esc((page["title"]+" "+page["note"]).lower())}"><span class="tag">Current application · {esc(page["capture_status"])}</span><h3>{esc(page["title"])}</h3><p>{esc(page["note"])}</p><a href="#board-{page["board"]}">View related proposed design →</a><div class="thumbs">{thumbs or "Capture pending."}</div></article>'
 body+='</div></section><section id="boards"><h2>Generated design proposals</h2><p>Review visual hierarchy and direction first. No new navigation or artwork is approved simply because it appears in a concept.</p>'
 for b in boards:
  body+=f'<figure id="board-{b["id"]}" class="{"portrait" if b["id"]=="detail" else "board"}"><h3>{esc(b["title"])}</h3><a href="{b["file"]}" target="_blank" rel="noopener"><img loading="lazy" src="{b["file"]}" alt="Generated proposal: {esc(b["title"])}"></a><figcaption><strong>Review notes:</strong> {esc(b["note"])}<details><summary>Generation brief and provenance</summary><p>{esc(b["prompt"])}</p><small>Original: {esc(b["original"])}</small></details></figcaption></figure>'
 body+='''</section></main><footer>No external scripts, fonts or analytics. Original PNG pixels are preserved. Native system Siri, Control Center, file importers and share sheets require separate on-device acceptance.</footer><script>document.querySelector('#search').addEventListener('input',e=>{const q=e.target.value.toLowerCase().trim();document.querySelectorAll('[data-search]').forEach(a=>a.hidden=!a.dataset.search.includes(q));});</script></html>'''
 (OUT/'index.html').write_text(body)
 lines=['# Page capture inventory · 2026-09-10','','Gallery: [Current pages and proposals](research/page-redesign-2026/index.html).','','The gallery contains original PNGs and a SHA-256 provenance manifest. Captures span multiple simulator runs of the functional changes, not one atomic pre-change snapshot. Most use demo mode. Confirmation and offline acceptance use a loopback fixture, never a real miner.','','| Route / state | Original screenshot prefixes | Proposal board |','|---|---|---|']
 for page in pages:lines.append(f'| {page["title"]} | '+(', '.join(Path(x).stem.split('_')[0] for x in page['current']) or 'Pending')+f' | {page["board"]} |')
 lines+=['','## Counting and limitations','','Diagnostics, history, offline settings, disclosure expansions and light appearances are states, not separate top-level routes. Endpoint catalog operations share a generic editor, with representative read, PATCH, restart and binary-upload variants captured. Native document pickers, share sheets, alerts and system Siri/Control Center surfaces are not app-designed pages and are not exhaustively captured.','',f'{len(captures)} screenshot files; {len(pages)} grouped route families and explicit states; {len(boards)} generated images. These are different counts and must not be conflated.','']
 (ROOT/'docs/PAGE-CAPTURE-INVENTORY-2026-09-10.md').write_text('\n'.join(lines))
 missing=[x['id'] for x in pages if not x['current']]
 print(json.dumps({'screenshots':len(captures),'groups':len(pages),'boards':len(boards),'pending_groups':missing}))

if __name__=='__main__':main()
