#!/usr/bin/env python3
"""V00: scope reduction and same-scope engine regression are separate metrics."""
import argparse,hashlib,json,math,random,shutil,statistics,subprocess,time
from pathlib import Path

def percentile(a,q):return sorted(a)[max(0,math.ceil(len(a)*q)-1)]
def ci(a):
 rng=random.Random(20261119);v=[statistics.median(rng.choices(a,k=len(a))) for _ in range(2000)]
 return [percentile(v,.025),percentile(v,.975)]
def main():
 p=argparse.ArgumentParser();p.add_argument('--fixture',type=Path,required=True);p.add_argument('--before',type=Path,required=True);p.add_argument('--after',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--pairs',type=int,default=20);a=p.parse_args()
 assert a.pairs>=20 and not a.output.exists()
 fixture=json.loads(a.fixture.read_text());root=Path(fixture['root']);parent=Path(fixture['parent']);assert str(parent).startswith('/private/tmp/sniffer-scope-native-') and not fixture['removed']
 control=parent/'control10000';assert not control.exists();control.mkdir()
 report=dict(started=time.time(),pairs=a.pairs,scope='shared host; warm/unknown filesystem cache; release engine completion, not GUI. Selected-volume reduction is not same-scope engine speedup.',binaries={v:dict(path=str(b),sha256=hashlib.sha256(b.read_bytes()).hexdigest()) for v,b in [('before',a.before),('after',a.after)]},rows=[],summary={},status='running')
 def save():a.output.write_text(json.dumps(report,indent=2)+'\n')
 save()
 try:
  for i in range(10000):
   folder=control/f'b{i%100:03}';folder.mkdir(exist_ok=True);(folder/f'f{i:05}').write_bytes(b'x'*(i%100+1))
  for scenario,path in [('mounted',root),('control10000',control)]:
   variants=[('before_all',a.before,'automatic'),('after_all',a.after,'all'),('after_selected',a.after,'automatic')]
   for pair in range(a.pairs):
    cell=[]
    order=variants[pair%3:]+variants[:pair%3]
    for name,binary,mode in order:
     row=dict(scenario=scenario,pair=pair,variant=name)
     try:
      proc=subprocess.run([str(binary),mode,str(path)],capture_output=True,text=True,timeout=30)
      row['exit_status']=proc.returncode
      if proc.returncode:row.update(status='failed',error=proc.stderr[-2000:])
      else:
       row.update(json.loads(proc.stdout));expected=(fixture['expected']['selected'] if name=='after_selected' else fixture['expected']['all']) if scenario=='mounted' else dict(files=10000,folders=101,logical=505000,excluded=0)
       row['status']='ok' if row['files']==expected['files'] and row['folders']==expected['folders'] and row['logical_bytes']==expected['logical'] and row['issue_count']==0 and not row['cancelled'] else 'oracle_mismatch'
       if name.startswith('after') and row['volume_coverage']['excludedCount']!=expected['excluded']:row['status']='scope_mismatch'
     except (subprocess.TimeoutExpired,json.JSONDecodeError) as exc:row.update(status='failed',error=str(exc))
     report['rows'].append(row);cell.append(row)
    allrows=[r for r in cell if r['variant']!='after_selected' or scenario=='control10000']
    equal=all(r['status']=='ok' for r in cell) and len({r['digest'] for r in allrows})==1
    for row in cell:row['same_scope_equal']=equal
    save();print(scenario,pair+1,flush=True)
   groups={v:[r for r in report['rows'] if r['scenario']==scenario and r['variant']==v and r['status']=='ok' and r['same_scope_equal']] for v,_,_ in variants}
   summary={v:dict(valid=len(rows),metrics={k:dict(p50=statistics.median([r[k] for r in rows]),p95=percentile([r[k] for r in rows],.95)) for k in ['scan_complete_ms','cpu_seconds','peak_rss_mib']}) for v,rows in groups.items() if rows}
   gates={}
   for variant in ['after_all']+(['after_selected'] if scenario=='control10000' else []):
    before={r['pair']:r for r in groups['before_all']};after={r['pair']:r for r in groups[variant]}
    if len(before)!=a.pairs or len(after)!=a.pairs:gates[variant]=dict(valid=False);continue
    changes=[100*(r['scan_complete_ms']-after[i]['scan_complete_ms'])/r['scan_complete_ms'] for i,r in before.items()];b=summary['before_all']['metrics'];c=summary[variant]['metrics']
    gates[variant]=dict(valid=True,latency=all(c['scan_complete_ms'][q]<=b['scan_complete_ms'][q]*1.1 for q in ['p50','p95']),paired_ci=ci(changes)[0]>=-10,cpu=c['cpu_seconds']['p95']<=b['cpu_seconds']['p95']*1.2,rss=c['peak_rss_mib']['p95']<=max(b['peak_rss_mib']['p95']*1.1,b['peak_rss_mib']['p95']+32),paired_change=statistics.median(changes),ci95=ci(changes))
   report['summary'][scenario]=dict(variants=summary,gates=gates);save()
  report['status']='measured'
 finally:
  shutil.rmtree(control);report['control_removed']=not control.exists();save()
 return 0 if all(r['status']=='ok' and r['same_scope_equal'] for r in report['rows']) else 1
if __name__=='__main__':raise SystemExit(main())
