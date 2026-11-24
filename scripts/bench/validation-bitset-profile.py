#!/usr/bin/env python3
import argparse,hashlib,json,statistics,subprocess
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--actual',action='store_true');a=p.parse_args()
out=Path('docs/validation/r-backlog-2026-11-09/validation-bitset');binary=Path('dist/validation-bitset').resolve()
name='actual-profile' if a.actual else '250k-profile';target=out/(name+'.json');assert not target.exists()
source='/Users/aido/.local/share/mac-space-sniffer/validation/2026-11-09/develop-baseline.sns' if a.actual else '250000'
rows=[]
for pair in range(1 if a.actual else 5):
 for mode in (['set','bitset'] if pair%2==0 else ['bitset','set']):
  run=subprocess.run(['nice','-n','10',str(binary),mode,source,'1' if a.actual else '3'],capture_output=True,text=True)
  record={'pair':pair,'mode':mode,'exit_code':run.returncode,'stderr':run.stderr}
  if run.stdout.strip():record['result']=json.loads(run.stdout)
  (out/f'{name}-{pair}-{mode}.json').write_text(json.dumps(record,indent=2)+'\n')
  assert run.returncode==0,record
  rows.append(record['result']);print(mode,record['result']['nodes'],record['result']['validation_seconds'],flush=True)
 assert rows[-1]['checksum']==rows[-2]['checksum']
summary={m:{'seconds_median':statistics.median(r['validation_seconds'] for r in rows if r['mode']==m),'max_rss_bytes_median':statistics.median(r['max_rss_after_bytes'] for r in rows if r['mode']==m)} for m in ['set','bitset']}
target.write_text(json.dumps({'scope':'fresh processes, identical optimized copied Core + frozen Set oracle. Actual fixture only one pair; not repeated performance certification. Host GUI and other agents concurrent. No new large input files.', 'binary_sha256':hashlib.sha256(binary.read_bytes()).hexdigest(),'input':source,'rows':rows,'summary':summary},indent=2)+'\n');print(json.dumps(summary),flush=True)
