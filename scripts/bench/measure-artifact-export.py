#!/usr/bin/env python3
"""Five alternating process comparisons. Hash outputs after child exit, outside peak RSS."""
import argparse,hashlib,json,platform,re,statistics,subprocess
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--probe',required=True);p.add_argument('--output',required=True);p.add_argument('--work',required=True);a=p.parse_args()
work=Path(a.work);work.mkdir(parents=True,exist_ok=True);rows=[]
def sha(file):
 h=hashlib.sha256()
 with file.open('rb') as stream:
  for block in iter(lambda:stream.read(1048576),b''):h.update(block)
 return h.hexdigest()
for pair in range(5):
 for format,scope in [('txt','all'),('sns','all'),('txt','focus'),('sns','focus')]:
  for mode in (['legacy','stream'] if pair%2==0 else ['stream','legacy']):
   file=work/f'{format}-{scope}-{mode}.{format}'
   r=subprocess.run(['/usr/bin/time','-l',a.probe,mode,format,scope,str(file.resolve()),'250000'],capture_output=True,text=True,check=True,timeout=90)
   row=json.loads(r.stdout);row['pair']=pair;row['max_rss_bytes']=int(re.search(r'(\d+)\s+maximum resident set size',r.stderr).group(1));row['sha256']=sha(file);rows.append(row)
summary={}
for format,scope in [('txt','all'),('sns','all'),('txt','focus'),('sns','focus')]:
 values=[r for r in rows if r['format']==format and r['scope']==scope]
 assert len({(v['bytes'],v['sha256']) for v in values})==1,(format,scope)
 summary[f'{format}-{scope}']={mode:{k:{'median':statistics.median(r[k] for r in values if r['mode']==mode),'min':min(r[k] for r in values if r['mode']==mode),'max':max(r[k] for r in values if r['mode']==mode)} for k in ['seconds','max_rss_bytes']} for mode in ['legacy','stream']}
files=sorted(Path('Sources').rglob('*.swift'))+[Path('Package.swift'),Path('Tests/SpaceSnifferCoreTests/LegacyArtifactReference.swift'),Path('scripts/bench/artifact-export.swift'),Path(__file__)]
report={'date':'2026-11-09','scope':'250k metadata nodes, *.bin filter, 100 branches, full or first branch; output disk write included; fixture creation excluded from duration and included in process peak RSS; checksum after exit','pairs':5,'compiler':subprocess.check_output(['swiftc','--version'],text=True).strip(),'platform':platform.platform(),'flags':'-O -whole-module-optimization','source_sha256':{str(f):sha(f) for f in files},'probe_sha256':sha(Path(a.probe)),'rows':rows,'summary':summary}
Path(a.output).write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(summary,indent=2))
