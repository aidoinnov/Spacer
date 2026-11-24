#!/usr/bin/env python3
"""Profile only the owned synthetic probe with macOS MallocStackLogging."""
import argparse,gzip,hashlib,json,os,re,subprocess
from collections import defaultdict
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--probe',required=True);p.add_argument('--output',required=True);a=p.parse_args()
out=Path(a.output);out.mkdir(parents=True,exist_ok=False);rows=[]
for mode,count in [('nodes',2000),('scratch-fresh',50000),('scratch-reuse',50000),('filter-fresh',2000),('filter-reuse',2000)]:
 env=os.environ|{'MallocStackLogging':'1','MallocStackLoggingNoCompact':'1','SNIFFER_PROFILE_WAIT':'1'}
 with (out/f'{mode}-stderr.log').open('w') as errors:
  process=subprocess.Popen([str(Path(a.probe).resolve()),mode,str(count)],env=env,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=errors,text=True)
  try:
   result=json.loads(process.stdout.readline())
   raw=out/f'{mode}.txt'
   with raw.open('w') as log:subprocess.run(['malloc_history',str(process.pid),'-allEvents'],stdout=log,stderr=subprocess.STDOUT,check=True,timeout=30)
  finally:process.stdin.write('x');process.stdin.flush();process.wait(timeout=10)
 groups=defaultdict(lambda:{'calls':0,'allocated_bytes':0})
 for line in raw.open():
  if not line.startswith('ALLOC '):continue
  if mode=='nodes':
   if 'AllocationProbe.buildNodes' not in line:continue
   key='path_constructor_site' if 'allocation-probe.swift:10' in line else 'node_table_append' if 'NodeTable.append' in line else 'children_append_site' if 'allocation-probe.swift:11' in line else 'subscript_modify_context' if 'NodeTable.subscript.modify' in line else 'other_builder'
  elif mode.startswith('filter-'):
   if 'ScanFilter.membership' not in line and 'FilterScratch.membership' not in line:continue
   key='filter_membership'
  else:
   if 'AllocationProbe.scratch' not in line:continue
   key='scratch_function'
  size=int(re.search(r'\[size=(\d+)\]',line)[1]);groups[key]['calls']+=1;groups[key]['allocated_bytes']+=size
 compressed=raw.with_suffix('.txt.gz')
 with raw.open('rb') as src,gzip.open(compressed,'wb') as dst:
  for chunk in iter(lambda:src.read(1048576),b''):dst.write(chunk)
 raw.unlink()
 rows.append({'mode':mode,'input_count':count,'probe_result':result,'groups':dict(groups),'raw':str(compressed),'raw_sha256':hashlib.sha256(compressed.read_bytes()).hexdigest()})
 print(json.dumps({'mode':mode,'groups':dict(groups)}),flush=True)
sources=sorted(Path('Sources/SpaceSnifferCore').glob('*.swift'))+[Path('scripts/bench/allocation-probe.swift'),Path(__file__)]
report={'date':'2026-11-09','kind':'all ALLOC events at selected synthetic builder/scratch call sites; VM_ALLOC excluded; cumulative bytes not peak/live RSS; instrumented timings are not performance comparison','rows':rows,'probe_sha256':hashlib.sha256(Path(a.probe).read_bytes()).hexdigest(),'source_sha256':{str(f):hashlib.sha256(f.read_bytes()).hexdigest() for f in sources}}
(out/'report.json').write_text(json.dumps(report,indent=2)+'\n')
