#!/usr/bin/env python3
"""Same-model synthetic storage comparison; no on-disk fixtures or volume scans."""
import argparse,hashlib,json,statistics,subprocess,time
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--before',type=Path,required=True);p.add_argument('--current',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
assert not a.output.exists()
variants=[('before',a.before),('current',a.current)]
r={'started':time.time(),'scope':'synthetic in-memory model storage; long identical paths, numeric inode progression and same metadata; not disk scan/GUI speed. RSS/footprint/peak sampled before validation/hash. Not pooled with filesystem fixture results.','plan':{'files':[100000,1000000],'branches':1000,'pairs':3},'binaries':{v:{'path':str(b),'sha256':hashlib.sha256(b.read_bytes()).hexdigest()} for v,b in variants},'rows':[],'summary':{},'status':'running'}
def save():a.output.write_text(json.dumps(r,indent=2)+'\n')
save()
for count in [100000,1000000]:
 for pair in range(3):
  cell=[]
  for variant,binary in (variants if pair%2==0 else list(reversed(variants))):
   proc=subprocess.run([str(binary),str(count)],capture_output=True,text=True,timeout=300)
   row={'count':count,'pair':pair,'variant':variant,'exit_status':proc.returncode}
   if proc.returncode:row.update(status='failed',error=proc.stderr[-2000:])
   else:
    raw=json.loads(proc.stdout);row['raw']=raw
    row['status']='ok' if (raw['files']==count and raw['folders']==1001 and raw['nodes']==count+1001 and raw['logical_bytes']==count and raw['allocated_bytes']==count*4096) else 'oracle_mismatch'
   r['rows'].append(row);cell.append(row)
  equal=all(x['status']=='ok' for x in cell) and len({x['raw']['digest'] for x in cell})==1
  for row in cell:row['pair_equal']=equal
  save();print(count,pair+1,flush=True)
 r['summary'][str(count)]={}
 for variant,binary in variants:
  rows=[x['raw'] for x in r['rows'] if x['count']==count and x['variant']==variant and x['status']=='ok']
  r['summary'][str(count)][variant]={key:statistics.median(x[key] for x in rows) for key in ['rss_after_build_bytes','footprint_after_build_bytes','peak_rss_before_validation_bytes','node_stride_bytes']}
r['status']='measured_exploratory' if all(x['status']=='ok' and x['pair_equal'] for x in r['rows']) else 'failed';save();print(json.dumps(r['summary']),flush=True)
