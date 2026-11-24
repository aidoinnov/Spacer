import argparse,json,os,shutil,subprocess,tempfile,time,hashlib,statistics,math
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--binary',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--scenarios',nargs='+');a=p.parse_args();assert not a.output.exists()
plan={'tiny1000':(1000,'tiny',100),'uniform200x100':(200,'uniform',21),'alternatingTinyFirst':(200,'alternating',21),'contiguousTinyFirst':(200,'tinyFirst',21),'contiguousLargeFirst':(200,'largeFirst',21),'firstOversized':(200,'oversized',21),'firstDenied':(200,'denied',21)}
if a.scenarios:plan={k:v for k,v in plan.items() if k in a.scenarios}
variants=[('current','parallel4'),('same_binary_aa','parallel4'),('single','sampling-one'),('no_resample_experiment','sampling-off')]
r={'scope':'fresh processes; release engine, immutable progress reader retained; warm/unknown shared host; no GUI; count time is native query span only','binary':{'path':str(a.binary),'sha256':hashlib.sha256(a.binary.read_bytes()).hexdigest()},'plan':plan,'variants':variants,'iteration_order_strategy':'rotate positions; reverse alternating complete4-pair blocks;100 pairs gives25 executions per position per variant','warmup_pairs':3,'rows':[],'warmup_rows':[],'summary':{},'status':'running'}
parent=Path(tempfile.mkdtemp(prefix='sniffer-policy-',dir='/private/tmp'));denied=None

def save():
 t=a.output.with_suffix('.tmp');t.write_text(json.dumps(r,indent=2)+'\n');t.replace(a.output)
def pct(values,q):return sorted(values)[math.ceil(len(values)*q)-1]
save()
try:
 for scenario,(branches,kind,pairs) in plan.items():
  if kind=='denied' and os.getuid()==0:raise RuntimeError('permission fixture requires non-root user')
  root=parent/scenario;root.mkdir();logical=allocated=files=0
  for i in range(branches):
   folder=root/f'b{i:04}';folder.mkdir()
   if kind=='tiny':n=1
   elif kind=='uniform':n=100
   elif kind=='alternating':n=1 if i%2 else 199
   elif kind=='tinyFirst':n=1 if i>=100 else 199
   elif kind=='largeFirst':n=199 if i>=100 else 1
   elif kind=='oversized':n=2200 if i==199 else 96
   else:n=96
   for j in range(n):
    if j%256==0 and shutil.disk_usage(parent).free<2*1024**3:raise RuntimeError('reserve2GiB reached')
    f=folder/f'f{j:05}';f.write_bytes(b'x'*(1+j%31));s=f.stat()
    if kind!='denied' or i!=199:logical+=s.st_size;allocated+=s.st_blocks*512;files+=1
  if kind=='denied':denied=root/'b0199';denied.chmod(0)
  expected={'files':files,'folders':branches+1,'logical_bytes':logical,'allocated_bytes':allocated,'issue_count':1 if kind=='denied' else 0,'cancelled':False}
  os.sync()
  for pair in range(-3,pairs):
   order=variants[pair%4:]+variants[:pair%4]
   if (pair//len(variants))%2:order=list(reversed(order))
   cell=[]
   for label,mode in order:
    started=time.perf_counter();proc=subprocess.run([str(a.binary),mode,str(root)],capture_output=True,text=True,timeout=120)
    row={'execution_index':len(cell),'scenario':scenario,'pair':pair,'phase':'warmup' if pair<0 else 'measured','variant':label,'exit_status':proc.returncode,'process_wall_ms':(time.perf_counter()-started)*1000}
    if proc.returncode:row.update(status='failed',error=proc.stderr[-2000:])
    else:
     v=json.loads(proc.stdout);row['raw']=v;row['status']='ok' if all(v.get(k)==x for k,x in expected.items()) else 'oracle_mismatch'
    r['warmup_rows' if pair<0 else 'rows'].append(row);cell.append(row)
   equal=all(x['status']=='ok' for x in cell) and len({x['raw']['digest'] for x in cell})==1
   for row in cell:row['pair_equal']=equal
   save()
   if not equal:raise RuntimeError(f'oracle/digest failure {scenario} pair{pair}')
  summary={}
  for label,mode in variants:
   rows=[x['raw'] for x in r['rows'] if x['scenario']==scenario and x['variant']==label]
   summary[label]={'n':len(rows),'p50_ms':statistics.median(x['scan_complete_ms'] for x in rows),'p95_ms':pct([x['scan_complete_ms'] for x in rows],.95),'cpu_p95':pct([x['cpu_seconds'] for x in rows],.95),'rss_p95_mib':pct([x['peak_rss_mib'] for x in rows],.95),'count_calls':sorted(set(x['enumeration_io']['entryCountMetrics']['calls'] for x in rows)),'query_p50_ms':statistics.median(x['enumeration_io']['entryCountMetrics']['elapsedNanoseconds']/1e6 for x in rows),'prefetch_used':sorted(set(x['enumeration_io']['prefetchUsed'] for x in rows))}
  r['summary'][scenario]=summary;save();print(scenario,json.dumps(summary),flush=True)
  if denied:denied.chmod(0o700);denied=None
  shutil.rmtree(root)
 r['status']='measured';save()
except BaseException as e:
 r.update(status='failed',error=repr(e));raise
finally:
 if denied and denied.exists():denied.chmod(0o700)
 shutil.rmtree(parent);r['cleanup']={'path':str(parent),'removed':not parent.exists()};save()
