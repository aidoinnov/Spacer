#!/usr/bin/env python3
import argparse,hashlib,json,statistics,subprocess
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--output',type=Path,default=Path('docs/validation/r-backlog-2026-11-09/r14'));a=p.parse_args();out=a.output;out.mkdir(parents=True,exist_ok=True);assert not (out/'kernel-profile.json').exists();binary=Path('dist/r14-lookup-hit');rows=[]
cases=[('lookup',196608,s,['first','hint']) for s in ['localized','random']]+[('hit',n,'nested',['flat','hierarchy']) for n in [22,200,2000,20000]]
for probe,count,scenario,modes in cases:
 for pair in range(5):
  for mode in modes if pair%2==0 else list(reversed(modes)):
   result=subprocess.run(['nice','-n','10',str(binary),probe,mode,str(count),scenario],capture_output=True,text=True);assert result.returncode==0,result.stderr
   r=json.loads(result.stdout);r['pair']=pair;rows.append(r)
  assert rows[-2]['checksum']==rows[-1]['checksum']
summary={}
for probe,count,scenario,modes in cases:
 key=f'{probe}-{count}-{scenario}';summary[key]={}
 for mode in modes:
  selected=[r for r in rows if r['probe']==probe and r['count']==count and r['scenario']==scenario and r['mode']==mode]
  summary[key][mode]={'seconds_median':statistics.median(r['seconds'] for r in selected),'seconds_range':[min(r['seconds'] for r in selected),max(r['seconds'] for r in selected)],'comparisons_median':statistics.median(r['comparisons'] for r in selected)}
report={'scope':'five alternating fresh-process pairs per research kernel; independent oracle checks are outside time; background GUI scan and other host work continue; no AppKit/whole-app speed, RSS or native Windows equivalence claim','binary_sha256':hashlib.sha256(binary.read_bytes()).hexdigest(),'source_sha256':hashlib.sha256(Path('scripts/bench/r14-lookup-hit.swift').read_bytes()).hexdigest(),'rows':rows,'summary':summary}
(out/'kernel-profile.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(summary))
