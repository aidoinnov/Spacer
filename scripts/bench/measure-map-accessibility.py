#!/usr/bin/env python3
"""Five sequential process pairs for AppKit AX presentation work; excludes drawing."""
import argparse,hashlib,json,platform,re,statistics,subprocess
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--probe',required=True);p.add_argument('--output',required=True);a=p.parse_args();rows=[]
for pair in range(5):
 for n in [32,10000]:
  for mode in (['legacy','cache'] if pair%2==0 else ['cache','legacy']):
   r=subprocess.run(['/usr/bin/time','-l',a.probe,mode,str(n),'60'],capture_output=True,text=True,check=True,timeout=60)
   row=json.loads(r.stdout);row['pair']=pair;row['max_rss_bytes']=int(re.search(r'(\d+)\s+maximum resident set size',r.stderr).group(1));rows.append(row)
summary={}
for n in [32,10000]:
 group=[r for r in rows if r['items']==n];assert len({r['checksum'] for r in group})==1
 for r in group:
  assert r['created_elements']==min(n,500)*(60 if r['mode']=='legacy' else 1)
  assert r['visited_items']==(n if r['mode']=='legacy' else min(n,500))*60
  assert r['retained_elements_after_clear']==0
 summary[str(n)]={m:{k:{'median':statistics.median(v[k] for v in group if v['mode']==m),'min':min(v[k] for v in group if v['mode']==m),'max':max(v[k] for v in group if v['mode']==m)} for k in ['seconds','max_rss_bytes']} for m in ['legacy','cache']}
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
files=sorted(Path('Sources').rglob('*.swift'))+sorted(Path('Tests').rglob('*.swift'))+[Path('Package.swift'),Path('scripts/bench/map-accessibility.swift'),Path('scripts/bench/measure-map-accessibility.py')]
report={'date':'2026-11-09','scope':'AppKit AX candidate/element/label/frame presentation, 60 updates; parent is offscreen NSView; no full drawing, animation, tooltip, fonts or actual frame-time claim; fixture excluded from duration, included in peak RSS','flags':'-O -whole-module-optimization, linked existing release SpaceSnifferCore objects','compiler':subprocess.check_output(['swiftc','--version'],text=True).strip(),'platform':platform.platform(),'source_sha256':{str(f):sha(f) for f in files},'probe_sha256':sha(Path(a.probe)),'baseline_source_sha256':sha(Path('docs/validation/accessibility-cache-2026-11-09/TreemapView-before.swift')),'rows':rows,'summary':summary}
Path(a.output).write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(summary,indent=2))
