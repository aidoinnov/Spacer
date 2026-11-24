#!/usr/bin/env python3
"""Bounded owned-fixture RSS comparison, scan boundary sampled by same macOS API."""
import argparse,hashlib,json,os,shutil,statistics,subprocess,tempfile,time
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--swift',type=Path,required=True);p.add_argument('--rust',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--sizes',nargs='+',type=int,choices=[100000,1000000],default=[100000,1000000]);p.add_argument('--swift-name',default='swift-v9');p.add_argument('--baseline-swift',type=Path);p.add_argument('--baseline-swift-mode',choices=['automatic','parallel2','parallel4'],default='parallel2');p.add_argument('--swift-mode',choices=['automatic','parallel2','parallel4'],default='parallel2');p.add_argument('--fixture-parent',type=Path,default=Path('/private/tmp'));p.add_argument('--reserve-gib',type=float,default=5);a=p.parse_args()
assert not a.output.exists()
assert a.reserve_gib >= (5 if 1000000 in a.sizes else 2)
assert shutil.disk_usage(a.fixture_parent).free>a.reserve_gib*1024**3
root=Path(tempfile.mkdtemp(prefix='sniffer-adoption-memory-',dir=a.fixture_parent))
variants=[(a.swift_name,a.swift,a.swift_mode),('disktree-1',a.rust,'1'),('disktree-4',a.rust,'4')]
if a.baseline_swift:variants.insert(0,('swift-baseline',a.baseline_swift,a.baseline_swift_mode))
assert len(a.sizes)==len(set(a.sizes))
assert len(variants)==len({v for v,_,_ in variants})
r={'scope':'engine; equal API proc_pid_rusage V2, before and after scan; retained RSS includes allocator caches and runtime, not a pure node-size calculation; Swift has additional metadata and retained immutable reader; no GUI','plan':{'sizes':a.sizes,'branches':1000,'pairs':3,'cache':'warm/unknown shared host','reserve_gib':a.reserve_gib,'fixture_parent':str(a.fixture_parent),'fixtures':'independently written 1-byte regular files, same paths and per-path allocated semantics; hardlink dedup disabled'},'binaries':{v:{'path':str(b),'sha256':hashlib.sha256(b.read_bytes()).hexdigest(),'mode':m} for v,b,m in variants},'rows':[],'fixtures':[],'status':'running'}
def save():
 tmp=a.output.with_suffix('.tmp');tmp.write_text(json.dumps(r,indent=2)+'\n');tmp.replace(a.output)
save()
try:
 for count in r['plan']['sizes']:
  fixture=root/str(count);fixture.mkdir();folders=[fixture/f'b{i:04}' for i in range(1000)]
  for folder in folders:folder.mkdir()
  allocated=0
  for i in range(count):
   if i%4096==0:assert shutil.disk_usage(root).free>a.reserve_gib*1024**3,'reserve reached'
   path=folders[i%1000]/f'f{i:07}'
   path.write_bytes(b'x');allocated+=path.stat().st_blocks*512
   if i%65536==0:
    r['fixture_progress']={'planned_files':count,'created_files':i+1};save();print('create',count,i+1,flush=True)
  info={'files':count,'folders':1001,'allocated_bytes':allocated,'logical_bytes':count};r['fixtures'].append(info);save();os.sync()
  for pair in range(3):
   order=variants[pair%len(variants):]+variants[:pair%len(variants)]
   for variant,binary,mode in order:
    proc=subprocess.run([str(binary),mode,str(fixture)] if variant.startswith('swift-') else [str(binary),str(fixture),mode],capture_output=True,text=True,timeout=300)
    row={'files':count,'pair':pair,'variant':variant,'exit_status':proc.returncode}
    if proc.returncode:row.update(status='failed',error=proc.stderr[-2000:])
    else:
     raw=json.loads(proc.stdout);row['raw']=raw
     valid=raw['files']==count and raw.get('dirs',raw.get('folders'))==1001 and raw.get('bytes',raw.get('allocated_bytes'))==allocated
     if variant.startswith('swift-'):valid=valid and raw['logical_bytes']==count and raw['issue_count']==0
     row['status']='ok' if valid else 'oracle_mismatch'
    r['rows'].append(row);save()
   cell=r['rows'][-len(variants):]
   swift_rows=[x for x in cell if x['variant'].startswith('swift-')]
   equal=all(x['status']=='ok' for x in cell) and len({x['raw']['digest'] for x in swift_rows})==1
   for row in cell:row['swift_digests_equal']=equal
   save()
   print(count,pair+1,flush=True)
  shutil.rmtree(fixture)
 r['status']='measured_exploratory' if all(x['status']=='ok' and x['swift_digests_equal'] for x in r['rows']) else 'failed'
 r['summary']={}
 for count in r['plan']['sizes']:
  r['summary'][str(count)]={}
  for variant,binary,mode in variants:
   rows=[x['raw'] for x in r['rows'] if x['files']==count and x['variant']==variant and x['status']=='ok']
   r['summary'][str(count)][variant]={k:statistics.median(x[k] for x in rows) for k in ['rss_before_bytes','rss_after_scan_bytes','footprint_after_scan_bytes']}
 print(json.dumps(r['summary']),flush=True)
finally:
 shutil.rmtree(root);r['cleanup']={'path':str(root),'removed':not root.exists()};save()
