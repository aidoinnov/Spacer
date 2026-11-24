#!/usr/bin/env python3
"""Sequential alternating pairs; kernel RSS/CPU are whole-process, stage seconds are scoped."""
import argparse, hashlib, json, os, re, shutil, statistics, subprocess, time
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--probe',required=True);p.add_argument('--output',required=True);p.add_argument('--pairs',type=int,default=5);p.add_argument('--fallback-only',action='store_true');a=p.parse_args()
out=Path(a.output);out.mkdir(parents=True,exist_ok=False);probe=str(Path(a.probe).resolve());rows=[]
sources=list(Path('Sources').rglob('*.swift'))+[Path('Package.swift'),Path('scripts/bench/final-optimizations.swift'),Path(__file__).resolve().relative_to(Path.cwd())]+list(Path('Tests').rglob('*.swift'))
sha=lambda f:hashlib.sha256(f.read_bytes()).hexdigest()
source_hashes={str(f):sha(f) for f in sources}
for f in sources:
 target=out/'source-archive'/f;target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(f,target)
cases=[('navigation',250000,'default',['legacy','current']),('geometry',25000,'alternating',['legacy','current']),('geometry',25000,'resize',['legacy','current'])]
cases += [('geometry',25000,'branch',['legacy','current'])]
cases += [('delta',250000,s,['legacy','current']) for s in ['sparse','independent','branch','dense','rename']]
cases += [('pools',25000,'default',['fresh','current','pages','nodes'])]
cases += [('scratch-filter',2000,'default',['fresh','current'])]
cases += [('reorder',25000,s,['legacy','current']) for s in ['sparse','branch','dense']]
if a.fallback_only:cases=[c for c in cases if c[0]=='delta' and c[2] in ['dense','rename']]
for case,count,scenario,modes in cases:
 for pair in range(a.pairs):
  for mode in modes if pair%2==0 else modes[::-1]:
   name=f'{case}-{scenario}-{mode}-{pair}';start=time.monotonic()
   r=subprocess.run(['/usr/bin/time','-l',probe,case,mode,str(count),scenario],capture_output=True,text=True,check=True)
   (out/(name+'.stderr')).write_text(r.stderr);v=json.loads(r.stdout)
   def metric(pattern):
    m=re.search(pattern,r.stderr);return float(m[1]) if m else None
   v.update(pair=pair,wall_seconds=time.monotonic()-start,max_rss_bytes=metric(r'(\d+)\s+maximum resident set size'),user_seconds=metric(r'([\d.]+) user'),system_seconds=metric(r'([\d.]+) sys'))
   rows.append(v);print(name,round(v['seconds'],5),flush=True)
summary={}
for case,count,scenario,modes in cases:
 values=[v for v in rows if (v['probe'],v['scenario'])==(case,scenario)]
 assert len({v['checksum'] for v in values})==1,(case,scenario,'semantic mismatch')
 summary[case+'-'+scenario]={m:{k:{'median':statistics.median(v[k] for v in values if v['mode']==m),'min':min(v[k] for v in values if v['mode']==m),'max':max(v[k] for v in values if v['mode']==m)} for k in ['seconds','max_rss_bytes','user_seconds','system_seconds']} for m in modes}
calibration=[]
for _ in range(5):calibration.append(json.loads(subprocess.check_output([probe,'telemetry','current','0'],text=True)))
assert source_hashes=={str(f):sha(f) for f in sources},'sources changed during measurement'
report={'scope':'alternating fresh-process pairs per case; 20 navigation/layout or 12 delta or eight pool generations per process; not screen FPS or a whole-app multiplier; RSS includes fixtures and full oracle outside scoped time','pairs':a.pairs,'rows':rows,'summary':summary,'telemetry':calibration,'probe_sha256':sha(Path(probe)),'source_sha256':source_hashes}
(out/'report.json').write_text(json.dumps(report,indent=2)+'\n')
