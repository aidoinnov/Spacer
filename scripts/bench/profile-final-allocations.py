#!/usr/bin/env python3
"""Owned fixtures only. ALLOC cumulative volume, never a live/peak-memory claim."""
import argparse,gzip,hashlib,json,os,re,subprocess
from collections import defaultdict
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--probe',required=True);p.add_argument('--output',required=True);a=p.parse_args()
out=Path(a.output);out.mkdir(parents=True,exist_ok=False);rows=[]
cases=[('pools',m,2000) for m in ['fresh','current','pages','nodes']]+[('scratch-filter',m,2000) for m in ['fresh','current']]+[('filesystem','current',0),('cow','current',250000)]
for case,mode,count in cases:
 name=case+'-'+mode;stackdir=(out/'stack-logs').resolve();stackdir.mkdir(exist_ok=True)
 env=os.environ|{'MallocStackLogging':'1','MallocStackLoggingNoCompact':'1','MallocStackLoggingDirectory':str(stackdir),'SNIFFER_PROFILE_WAIT':'1'}
 with (out/(name+'-stderr.log')).open('w') as errors:
  process=subprocess.Popen([str(Path(a.probe).resolve()),case,mode,str(count)],env=env,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=errors,text=True)
  try:
   line=process.stdout.readline();assert line,(name,'no result');result=json.loads(line);raw=out/(name+'.txt')
   with raw.open('w') as log:subprocess.run(['malloc_history',str(process.pid),'-allEvents'],stdout=log,stderr=subprocess.STDOUT,check=True,timeout=60)
  finally:
   if process.poll() is None:process.stdin.write('x');process.stdin.flush()
   process.wait(timeout=10)
 groups=defaultdict(lambda:{'calls':0,'allocated_bytes':0})
 for line in raw.open():
  if not line.startswith('ALLOC '):continue
  phase=next((v for v in ['firstScan','repeatedScan','addedScan','deletedScan','renamedScan','profiledFilter','scratchFiltering','arrayCOW','pools'] if 'FinalOptimizationProbe.'+v in line),None)
  if phase is None:continue
  category='filter_membership' if 'ScanFilter.membership' in line else 'scratch_bookkeeping' if 'ScratchBudget.' in line or 'FilterScratch.membership' in line else 'weights' if 'ScanFilter.weights' in line else 'path_name_identity' if any(v in line for v in ['String.','StringProtocol.','_StringGuts.']) else 'node_pages' if 'NodeTable.' in line else 'children_or_stack' if 'Array.' in line else 'other'
  key=phase+'/'+category;m=re.search(r'\[size=(\d+)\]',line)
  if m:groups[key]['calls']+=1;groups[key]['allocated_bytes']+=int(m[1])
 compressed=raw.with_suffix('.txt.gz')
 with raw.open('rb') as src,gzip.open(compressed,'wb') as dst:
  for chunk in iter(lambda:src.read(1048576),b''):dst.write(chunk)
 raw.unlink();row={'case':case,'mode':mode,'input_count':count,'result':result,'groups':dict(groups),'raw':str(compressed),'raw_sha256':hashlib.sha256(compressed.read_bytes()).hexdigest()};rows.append(row)
 print(json.dumps({'case':name,'groups':dict(groups)}),flush=True)
sha=lambda f:hashlib.sha256(f.read_bytes()).hexdigest()
sources=list(Path('Sources').rglob('*.swift'))+[Path('scripts/bench/final-optimizations.swift'),Path('Tests/SpaceSnifferCoreTests/PoolCandidates.swift'),Path(__file__)]
(out/'report.json').write_text(json.dumps({'scope':'macOS MallocStackLogging all ALLOC events at named fixture phases; attribution by stack precedence; cumulative allocation, VM excluded; instrumented seconds not speed comparison','rows':rows,'probe_sha256':sha(Path(a.probe)),'source_sha256':{str(f):sha(f) for f in sources}},indent=2)+'\n')
