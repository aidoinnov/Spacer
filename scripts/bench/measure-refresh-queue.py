#!/usr/bin/env python3
"""Sequential five-pair queue measurements; no filesystem scan or UI timing."""
import argparse, hashlib, json, platform, re, statistics, subprocess
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--probe',required=True);p.add_argument('--output',required=True);a=p.parse_args()
cases=[('small',1),('small',4),('small',16),('independent',1000),('independent',2000),('independent',4000),('duplicates',1000),('ancestors',1000),('root',1000),('churn',1000)]
rows=[]
for pair in range(5):
 for scenario,n in cases:
  for mode in (['legacy','indexed'] if pair%2==0 else ['indexed','legacy']):
   r=subprocess.run(['/usr/bin/time','-l',a.probe,mode,scenario,str(n)],capture_output=True,text=True,check=True,timeout=120)
   row=json.loads(r.stdout);row['pair']=pair;row['max_rss_bytes']=int(re.search(r'(\d+)\s+maximum resident set size',r.stderr).group(1));rows.append(row)
summary={}
for scenario,n in cases:
 group=[r for r in rows if (r['scenario'],r['n'])==(scenario,n)]
 assert len({(r['checksum'],r['pops']) for r in group})==1
 assert all(r['idle_slots']==0 for r in group)
 summary[f'{scenario}-{n}']={m:{k:{'median':statistics.median(r[k] for r in group if r['mode']==m),'min':min(r[k] for r in group if r['mode']==m),'max':max(r[k] for r in group if r['mode']==m)} for k in ['seconds','max_rss_bytes']} for m in ['legacy','indexed']}
files=sorted(Path('Sources').rglob('*.swift'))+sorted(Path('Tests').rglob('*.swift'))+[Path('Package.swift'),Path('scripts/bench/refresh-queue.swift'),Path('scripts/bench/measure-refresh-queue.py')]
sha=lambda f:hashlib.sha256(f.read_bytes()).hexdigest()
report={'date':'2026-11-09','scope':'queue metadata only; fixture excluded from duration, included in process peak RSS; small repeats=2000; others=1; sequential alternating processes','pairs':5,'compiler':subprocess.check_output(['swiftc','--version'],text=True).strip(),'platform':platform.platform(),'flags':'-O -whole-module-optimization','source_sha256':{str(f):sha(f) for f in files},'probe_sha256':sha(Path(a.probe)),'rows':rows,'summary':summary}
Path(a.output).write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(summary,indent=2))
