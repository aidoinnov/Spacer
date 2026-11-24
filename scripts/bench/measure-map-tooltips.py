#!/usr/bin/env python3
"""Sequential native tooltip registration component comparisons, including moving geometry."""
import argparse,hashlib,json,platform,re,statistics,subprocess
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--probe',required=True);p.add_argument('--output',required=True);a=p.parse_args();rows=[]
cases=[(32,'stationary'),(1000,'stationary'),(1000,'moving')]
for pair in range(5):
 for n,scenario in cases:
  for mode in (['legacy','registry'] if pair%2==0 else ['registry','legacy']):
   r=subprocess.run(['/usr/bin/time','-l',a.probe,mode,str(n),scenario],capture_output=True,text=True,check=True,timeout=90)
   row=json.loads(r.stdout);row['pair']=pair;row['max_rss_bytes']=int(re.search(r'(\d+)\s+maximum resident set size',r.stderr).group(1));rows.append(row)
summary={}
for n,scenario in cases:
 group=[r for r in rows if (r['items'],r['scenario'])==(n,scenario)];assert len({r['checksum'] for r in group})==1
 for r in group:
  rebuilds=60 if r['mode']=='legacy' or scenario=='moving' else 1
  assert r['rebuilds']==rebuilds and r['native_adds']==n*rebuilds and r['registered_after_clear']==0
 summary[f'{scenario}-{n}']={mode:{key:{'median':statistics.median(r[key] for r in group if r['mode']==mode),'min':min(r[key] for r in group if r['mode']==mode),'max':max(r[key] for r in group if r['mode']==mode)} for key in ['seconds','max_rss_bytes']} for mode in ['legacy','registry']}
sha=lambda f:hashlib.sha256(f.read_bytes()).hexdigest()
files=sorted(Path('Sources').rglob('*.swift'))+sorted(Path('Tests').rglob('*.swift'))+[Path('Package.swift'),Path('scripts/bench/map-tooltips.swift'),Path('scripts/bench/measure-map-tooltips.py')]
r={'date':'2026-11-09','scope':'offscreen NSView native tooltip registration, 60 updates, current visible paths; no full draw/actual hover delay/native animation frame claim; fixture outside duration, inside peak RSS','compiler':subprocess.check_output(['swiftc','--version'],text=True).strip(),'platform':platform.platform(),'flags':'-O -whole-module-optimization; existing release SpaceSnifferCore object link','source_sha256':{str(f):sha(f) for f in files},'baseline_sha256':sha(Path('docs/validation/tooltip-registry-2026-11-09/TreemapView-before.swift')),'probe_sha256':sha(Path(a.probe)),'rows':rows,'summary':summary}
Path(a.output).write_text(json.dumps(r,indent=2)+'\n');print(json.dumps(summary,indent=2))
