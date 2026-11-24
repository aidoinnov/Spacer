#!/usr/bin/env python3
"""Exploratory fixed-five-pair ablation. Does not declare adoption gates passed."""
import argparse,hashlib,json,math,os,shutil,statistics,subprocess,tempfile,time
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--sources',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--variants',nargs='+',default=['control','control-phases','single-pass','single-pass-phases']);p.add_argument('--scenarios',nargs='+');p.add_argument('--allocation-library',type=Path);p.add_argument('--pairs',type=int,default=5);p.add_argument('--variant-modes',nargs='*',default=[]);a=p.parse_args()
assert not a.output.exists()
variants=a.variants
assert len(variants)==len(set(variants)) and variants
binaries={v:Path(str(a.sources).removesuffix('-sources')+'-'+v) for v in variants}
assert all(b.is_file() for b in binaries.values())
variant_modes={v:'automatic' for v in variants}
for value in a.variant_modes:
 name,mode=value.split('=',1);assert name in variants and mode in ['automatic','parallel2','parallel4','posix'];variant_modes[name]=mode
assert a.pairs>0
scenarios={'small1000':(1000,50),'normal10000':(10000,100),'flat20000':(20000,0),'branches20000':(20000,200),'wide100000':(100000,0),'overbudget131073':(131073,0),'tinyfolders1000':(1000,1000),'deep200':(200,200),'longnames20000':(20000,0)}
if a.scenarios:
 assert len(a.scenarios)==len(set(a.scenarios)) and set(a.scenarios)<=set(scenarios)
 scenarios={k:v for k,v in scenarios.items() if k in a.scenarios}
root=Path(tempfile.mkdtemp(prefix='sniffer-adoption-ablation-',dir='/private/tmp'))
r={'plan':{'pairs':a.pairs,'variant_modes':variant_modes,'scenarios':scenarios,'mode':'per-variant CLI mode, immutable reader retained','purpose':'exploratory ablation only; no release gate claims','cache':'warm/unknown shared host','phase_scope':'nested sum wall; instrumentation overhead reported separately; reader/build phase remainder is not a profile attribution','reserve_gib':3},'binaries':{v:{'path':str(b),'sha256':hashlib.sha256(b.read_bytes()).hexdigest()} for v,b in binaries.items()},'rows':[],'summary':{},'status':'running'}
a.output.parent.mkdir(parents=True,exist_ok=True)
def save():
 t=a.output.with_suffix('.tmp');t.write_text(json.dumps(r,indent=2)+'\n');t.replace(a.output)
save()
try:
 for scenario,(files,branches) in scenarios.items():
  fixture=root/scenario;fixture.mkdir();folders=[]
  for i in range(branches):
   folder=(folders[-1]/'d' if folders else fixture/'d') if scenario=='deep200' else fixture/f'b{i:03}'
   folder.mkdir();folders.append(folder)
  logical=allocated=0
  for i in range(files):
   if i%1024==0:assert shutil.disk_usage(root).free>3*1024**3,'reserve reached'
   path=(folders[i%branches] if branches else fixture)/((('long'*50) if scenario=='longnames20000' else '')+f'f{i:06}')
   path.write_bytes(b'x'*(1+i%100));st=path.stat();logical+=st.st_size;allocated+=st.st_blocks*512
  expected={'files':files,'folders':branches+1,'logical_bytes':logical,'allocated_bytes':allocated,'issue_count':0,'cancelled':False}
  os.sync()
  for pair in range(a.pairs):
   modes=variants[pair%len(variants):]+variants[:pair%len(variants)]
   if pair%2:modes.reverse()
   cell=[]
   for v in modes:
    row={'scenario':scenario,'pair':pair,'variant':v}
    env=os.environ.copy()
    if v.startswith('alloc-'):
     assert a.allocation_library is not None
     env['DYLD_INSERT_LIBRARIES']=str(a.allocation_library)
    proc=subprocess.run([str(binaries[v]),variant_modes[v],str(fixture)],capture_output=True,text=True,timeout=120,env=env)
    row['exit_status']=proc.returncode
    if proc.returncode:row.update(status='failed',error=proc.stderr[-2000:])
    else:
     row.update(json.loads(proc.stdout));row['status']='ok' if all(row.get(k)==val for k,val in expected.items()) else 'oracle_mismatch'
    r['rows'].append(row);cell.append(row)
   equal=all(x['status']=='ok' for x in cell) and len({x['digest'] for x in cell})==1
   for row in cell:row['pair_equal']=equal
   save()
  summary={}
  for v in variants:
   rows=[x for x in r['rows'] if x['scenario']==scenario and x['variant']==v and x['status']=='ok']
   summary[v]={k:statistics.median(x[k] for x in rows) for k in ['scan_complete_ms','cpu_seconds','peak_rss_mib']}
   summary[v]['p95']={k:sorted(x[k] for x in rows)[max(0,math.ceil(.95*len(rows))-1)] for k in ['scan_complete_ms','cpu_seconds','peak_rss_mib']}
   if rows[0].get('allocation_probe'):summary[v]['allocation_median']={k:statistics.median(x['allocation_probe'][k] for x in rows) for k in ['malloc_calls','calloc_calls','realloc_calls','requested_bytes']}
   if v.endswith('phases'):summary[v]['phases_median_ms']={k:statistics.median(x['phases']['sum_wall_ms'].get(k,0) for x in rows) for k in rows[0]['phases']['sum_wall_ms']}
  r['summary'][scenario]=summary;save()
  print(scenario,json.dumps(summary),flush=True)
  shutil.rmtree(fixture)
 r['status']='exploratory_complete' if all(x['status']=='ok' and x['pair_equal'] for x in r['rows']) else 'failed'
finally:
 shutil.rmtree(root);r['cleanup']={'path':str(root),'removed':not root.exists()};save()
