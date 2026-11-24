#!/usr/bin/env python3
"""Fixed small-input worker matrix; this alone never changes defaults."""
import argparse,hashlib,json,os,shutil,statistics,subprocess,tempfile
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--control',type=Path,required=True);p.add_argument('--safe',type=Path,required=True);p.add_argument('--rust',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--label-prefix',default='safe');p.add_argument('--control-label',default='v9-default2');p.add_argument('--pairs',type=int,default=15);p.add_argument('--warmup-pairs',type=int,default=0);p.add_argument('--resource-note',default='shared host live root scan');p.add_argument('--scenarios',nargs='+',choices=['flat20000','branches200x100','mixedFirstTiny','mixedFirstLarge'],default=['flat20000','branches200x100']);a=p.parse_args()
assert not a.output.exists() and a.pairs>0 and a.warmup_pairs>=0
assert len(a.scenarios)==len(set(a.scenarios))
assert not a.control_label.startswith('disktree') and not a.label_prefix.startswith('disktree')
variants=[(a.control_label,a.control,'parallel2'),(a.label_prefix+'-serial',a.safe,'automatic'),(a.label_prefix+'-2',a.safe,'parallel2'),(a.label_prefix+'-4',a.safe,'parallel4')]+[(f'disktree-{i}',a.rust,str(i)) for i in [1,2,4]]
assert len(variants)==len({v for v,_,_ in variants})
r={'scope':'exploratory engine-only; fresh processes; warm/unknown cache; '+a.resource_note+'; Swift retains immutable progress reader; pinned disktree Core, dedup=false','pairs':a.pairs,'planned_scenarios':a.scenarios,'warmup_pairs':a.warmup_pairs,'warmup_rows':[],'binaries':{v:{'path':str(b),'mode':m,'sha256':hashlib.sha256(b.read_bytes()).hexdigest()} for v,b,m in variants},'rows':[],'summary':{},'status':'running'}
root=Path(tempfile.mkdtemp(prefix='sniffer-adoption-workers-',dir='/private/tmp'))
def save():
 tmp=a.output.with_suffix('.tmp');tmp.write_text(json.dumps(r,indent=2)+'\n');tmp.replace(a.output)
save()
try:
 for scenario in a.scenarios:
  fixture=root/scenario;fixture.mkdir();allocated=logical=0
  for i in range(20000):
   if scenario=='flat20000':folder=fixture
   elif scenario=='branches200x100':folder=fixture/f'b{i%200:03}'
   else:
    small_odd=scenario=='mixedFirstTiny'
    branch=2*i+int(small_odd) if i<100 else 2*((i-100)%100)+int(not small_odd)
    folder=fixture/f'b{branch:03}'
   folder.mkdir(exist_ok=True);path=folder/f'f{i:05}.bin';path.write_bytes(b'x'*(1+i%128));s=path.stat();allocated+=s.st_blocks*512;logical+=s.st_size
  os.sync()
  for pair in range(-a.warmup_pairs,a.pairs):
   cell=[];order=variants[pair%len(variants):]+variants[:pair%len(variants)]
   if pair%2:order.reverse()
   for variant,binary,mode in order:
    cmd=[str(binary),str(fixture),mode] if variant.startswith('disktree') else [str(binary),mode,str(fixture)]
    proc=subprocess.run(cmd,capture_output=True,text=True,timeout=120)
    row={'scenario':scenario,'variant':variant,'pair':pair,'phase':'warmup' if pair<0 else 'measured','exit_status':proc.returncode}
    if proc.returncode:row.update(status='failed',error=proc.stderr[-2000:])
    else:
     raw=json.loads(proc.stdout);row['raw']=raw
     valid=raw['files']==20000 and raw.get('dirs',raw.get('folders'))==(1 if scenario=='flat20000' else 201) and raw.get('bytes',raw.get('allocated_bytes'))==allocated
     if not variant.startswith('disktree'):valid=valid and raw['logical_bytes']==logical and raw['issue_count']==0
     row['status']='ok' if valid else 'oracle_mismatch'
    r['warmup_rows' if pair<0 else 'rows'].append(row);cell.append(row)
   swift_rows=[x for x in cell if not x['variant'].startswith('disktree')]
   equal=all(x['status']=='ok' for x in cell) and len({x['raw']['digest'] for x in swift_rows})==1
   for row in cell:row['pair_equal']=equal
   save()
   if pair<0 and not equal:raise RuntimeError('warmup oracle/digest mismatch')
  r['summary'][scenario]={}
  for variant,binary,mode in variants:
   rows=[x['raw'] for x in r['rows'] if x['scenario']==scenario and x['variant']==variant and x['status']=='ok']
   r['summary'][scenario][variant]={'n':len(rows),'p50_ms':statistics.median(x.get('ms',x.get('scan_complete_ms')) for x in rows)}
  print(scenario,json.dumps(r['summary'][scenario]),flush=True);shutil.rmtree(fixture)
 r['status']='measured_exploratory' if all(x['status']=='ok' and x['pair_equal'] for x in r['rows']) else 'failed'
finally:
 shutil.rmtree(root);r['cleanup']={'path':str(root),'removed':not root.exists()};save()
