#!/usr/bin/env python3
"""Same-scope frozen before/current1/2/4 release scans; fresh processes, warm/unknown cache."""
import argparse,hashlib,json,math,random,shutil,statistics,subprocess,tempfile,time,os,ctypes
from pathlib import Path

def percentile(a,q):return sorted(a)[max(0,math.ceil(len(a)*q)-1)]
def ci(a):
 rng=random.Random(20261119);samples=[statistics.median(rng.choices(a,k=len(a))) for _ in range(2000)]
 return [percentile(samples,.025),percentile(samples,.975)]
def main():
 p=argparse.ArgumentParser();p.add_argument('--before',type=Path,required=True);p.add_argument('--same-binary-aa',action='store_true',help='Compare candidate parallel4 to itself; no implementation/policy differences');p.add_argument('--before-mode',choices=['automatic','parallel2','parallel4'],default='automatic');p.add_argument('--candidate',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--pairs',type=int,default=5);p.add_argument('--warmup-pairs',type=int,default=0);p.add_argument('--scenarios',nargs='+',choices=['small1000','normal10000','wide4100','wide100000','overbudget131073','tinyfolders1000','deep200'],default=['normal10000']);a=p.parse_args()
 clone_files=os.environ.get('SNIFFER_BENCH_CLONE_FILES')=='1'
 backing=Path(os.environ.get('SNIFFER_BENCH_PARENT','/private/tmp')).resolve()
 reserve_gib=float(os.environ.get('SNIFFER_BENCH_RESERVE_GIB','2'))
 assert math.isfinite(reserve_gib) and reserve_gib>=(.25 if clone_files else 1)
 reserve_bytes=int(reserve_gib*1024**3)
 assert a.pairs>0 and a.warmup_pairs>=0 and not a.output.exists() and shutil.disk_usage(backing).free>reserve_bytes
 a.output.parent.mkdir(parents=True,exist_ok=True)
 variants=[('before',a.before,a.before_mode),('serial',a.candidate,'automatic'),('parallel2',a.candidate,'parallel2'),('parallel4',a.candidate,'parallel4')]
 selected=os.environ.get('SNIFFER_BENCH_VARIANTS')
 if selected:
  selected=selected.split(',');assert len(selected)==len(set(selected)) and {'before','serial'}<=set(selected)<=set(v[0] for v in variants)
  variants=[v for v in variants if v[0] in selected]
 if a.same_binary_aa:
  assert not selected,'A/A sets its two variants explicitly'
  variants=[('before',a.candidate,'parallel4'),('aa',a.candidate,'parallel4')]
 report=dict(started=time.time(),pairs=a.pairs,planned_scenarios=a.scenarios,scope='same selected-volume scope; release engine, reader retained; not GUI; fresh process, shared host, warm/unknown cache',variants={v:dict(binary=str(b),sha256=hashlib.sha256(b.read_bytes()).hexdigest(),mode=m) for v,b,m in variants},rows=[],warmup_rows=[],warmup_pairs=a.warmup_pairs,summary={},status='running')
 report['comparison_kind']='same_binary_same_mode_aa' if a.same_binary_aa else 'before_candidate'
 report['minimum_backing_space_bytes']=reserve_bytes
 report['fixture_storage']='APFS clone files; reported per-path allocated bytes retained' if clone_files else 'independently written files'
 report['fixture_setup_sync']=os.environ.get('SNIFFER_BENCH_SYNC_FIXTURE')=='1'
 parent=Path(tempfile.mkdtemp(prefix='sniffer-parallel-',dir=backing))
 def save():
  tmp=a.output.with_suffix('.tmp');tmp.write_text(json.dumps(report,indent=2)+'\n');tmp.replace(a.output)
 save()
 try:
  templates=[]
  if clone_files:
   libc=ctypes.CDLL(None,use_errno=True);libc.clonefile.argtypes=[ctypes.c_char_p,ctypes.c_char_p,ctypes.c_int];libc.clonefile.restype=ctypes.c_int
   for i in range(100):
    template=parent/f'template{i}';template.write_bytes(b'x'*(i+1));templates.append(template)
  for scenario in a.scenarios:
   root=parent/scenario;root.mkdir();files={'small1000':1000,'normal10000':10000,'wide4100':4100,'wide100000':100000,'overbudget131073':131073,'tinyfolders1000':1000,'deep200':200}[scenario];branches={'small1000':50,'normal10000':100,'tinyfolders1000':1000,'deep200':200}.get(scenario,0);folders=[]
   for i in range(branches):
    folder=(folders[-1]/'d' if folders else root/'d') if scenario=='deep200' else root/f'b{i:03}';folder.mkdir();folders.append(folder)
   logical=allocated=0
   for i in range(files):
    if i%1000==0 and shutil.disk_usage(backing).free<reserve_bytes:raise RuntimeError('backing-space reserve exhausted')
    path=(folders[i%branches] if branches else root)/f'f{i:06}'
    if clone_files:
     if libc.clonefile(os.fsencode(templates[i%100]),os.fsencode(path),0)!=0:raise OSError(ctypes.get_errno(),'clonefile failed')
    else:path.write_bytes(b'x'*(1+i%100))
    s=path.stat();logical+=s.st_size;allocated+=s.st_blocks*512
   expected=dict(files=files,folders=branches+1,logical_bytes=logical,allocated_bytes=allocated,issue_count=0,cancelled=False)
   if report['fixture_setup_sync']:
    os.sync();time.sleep(1)
   for pair in range(-a.warmup_pairs,a.pairs):
    cell=[];order=variants[pair%len(variants):]+variants[:pair%len(variants)]
    for variant,binary,mode in order:
     row=dict(scenario=scenario,pair=pair,variant=variant,phase='warmup' if pair<0 else 'measured')
     try:
      process_started=time.perf_counter()
      proc=subprocess.run([str(binary),mode,str(root)],capture_output=True,text=True,timeout=60);row['exit_status']=proc.returncode
      row['process_wall_ms']=(time.perf_counter()-process_started)*1000
      if proc.returncode:row.update(status='failed',error=proc.stderr[-2000:])
      else:
       row.update(json.loads(proc.stdout));row['status']='ok' if all(row.get(k)==v for k,v in expected.items()) else 'oracle_mismatch'
     except (subprocess.TimeoutExpired,json.JSONDecodeError) as exc:row.update(status='failed',error=str(exc))
     cell.append(row);report['warmup_rows' if pair<0 else 'rows'].append(row)
    equal=all(r['status']=='ok' for r in cell) and len({r['digest'] for r in cell})==1
    for row in cell:row['pair_equal']=equal
    save();print(scenario,('warmup '+str(pair+a.warmup_pairs+1)) if pair<0 else pair+1,flush=True)
    if pair<0 and not equal:raise RuntimeError('warmup oracle/digest mismatch; refusing timed collection')
   groups={v:{r['pair']:r for r in report['rows'] if r['scenario']==scenario and r['variant']==v and r['status']=='ok' and r['pair_equal']} for v,_,_ in variants}
   summary=dict(expected=expected,variants={},comparisons={})
   for variant,rows in groups.items():
    metrics={}
    for key in ['scan_complete_ms','cpu_seconds','peak_rss_mib']:
     values=[r[key] for r in rows.values()]
     if values:metrics[key]=dict(p50=statistics.median(values),p95=percentile(values,.95))
    summary['variants'][variant]=dict(valid=len(rows),metrics=metrics)
   for variant in [v for v in ['serial','parallel2','parallel4','aa'] if v in groups]:
    for baseline in ['before']+(['serial'] if variant not in ['serial','aa'] else []):
     b=groups[baseline];c=groups[variant]
     if not b or not c:continue
     changes=[100*(r['scan_complete_ms']-c[i]['scan_complete_ms'])/r['scan_complete_ms'] for i,r in b.items() if i in c];interval=ci(changes);bm=summary['variants'][baseline]['metrics'];cm=summary['variants'][variant]['metrics']
     gates=dict(valid=len(changes)==a.pairs,latency=all(cm['scan_complete_ms'][q]<=bm['scan_complete_ms'][q]*1.1 for q in ['p50','p95']),paired_ci=interval[0]>=-10,cpu=cm['cpu_seconds']['p95']<=bm['cpu_seconds']['p95']*1.2,rss=cm['peak_rss_mib']['p95']<=max(bm['peak_rss_mib']['p95']*1.1,bm['peak_rss_mib']['p95']+32))
     summary['comparisons'][variant+'_vs_'+baseline]=dict(paired_improvement_pct=statistics.median(changes),ci95=interval,gates=gates,passed=all(gates.values()) and a.pairs>=20)
   report['summary'][scenario]=summary;save();shutil.rmtree(root)
  report['status']='measured'
 finally:
  shutil.rmtree(parent);report['cleanup']=dict(path=str(parent),removed=not parent.exists());save()
 return 0 if all(r['status']=='ok' and r['pair_equal'] for r in report['rows']) else 1
if __name__=='__main__':raise SystemExit(main())
