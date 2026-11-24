#!/usr/bin/env python3
"""Fresh-process five-way alternating triples; no concurrent probes."""
import argparse,hashlib,json,os,re,statistics,subprocess,time
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--build',required=True);p.add_argument('--output',required=True);p.add_argument('--pairs',type=int,default=5);a=p.parse_args()
build=Path(a.build);out=Path(a.output);out.mkdir(parents=True,exist_ok=False);probe=(build/'r05-probe').resolve()
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
manifest=json.loads((build/'build-manifest.json').read_text());assert sha(probe)==manifest['probe_sha256']
verification=subprocess.run([str(probe),'verify'],capture_output=True,text=True,check=True)
(out/'verification.stdout').write_text(verification.stdout);(out/'verification.stderr').write_text(verification.stderr)
assert json.loads(verification.stdout)['passed']
rows=[];modes=['full','focus','fused']
host={'scope':'shared macOS host; main GUI large scan/other compilation may overlap; processes here are sequential; memory samples before/at-focus/after exclude later oracle from primary peak','date':time.time(),'disk':{str(p):{'total':os.statvfs(p).f_blocks*os.statvfs(p).f_frsize,'available':os.statvfs(p).f_bavail*os.statvfs(p).f_frsize} for p in [Path('/'),Path('/Volumes/develop')]}}
(out/'host.json').write_text(json.dumps(host,indent=2)+'\n')
for count in [25000,250000]:
 for shape in ['small','large','root']:
  for filter_case in ['empty','mask','mixed']:
   for pair in range(a.pairs):
    order=modes[pair%3:]+modes[:pair%3]
    if pair%2:order=order[::-1]
    for mode in order:
     name=f'{count}-{shape}-{filter_case}-{pair}-{mode}'
     start=time.monotonic()
     r=subprocess.run(['/usr/bin/time','-l',str(probe),mode,str(count),shape,filter_case],capture_output=True,text=True,timeout=120)
     (out/(name+'.stdout')).write_text(r.stdout);(out/(name+'.stderr')).write_text(r.stderr)
     assert r.returncode==0,(name,r.stderr)
     row=json.loads(r.stdout);row.update(pair=pair,wall_seconds=time.monotonic()-start,raw_stdout=name+'.stdout',raw_stderr=name+'.stderr')
     assert all(row[phase][field]>0 for phase in ['before','at_focus','after'] for field in ['resident_bytes','physical_footprint_bytes','peak_rss_bytes']),(name,'unavailable process metrics')
     row['stdout_sha256']=sha(out/row['raw_stdout']);row['stderr_sha256']=sha(out/row['raw_stderr'])
     def metric(pattern):
      match=re.search(pattern,r.stderr);return float(match[1]) if match else None
     row['whole_process_peak_rss_bytes']=metric(r'(\d+)\s+maximum resident set size')
     row['whole_process_footprint_peak_bytes']=metric(r'(\d+)\s+peak memory footprint')
     rows.append(row);print(name,round(row['focus_ready_seconds']*1000,3),round(row['total_seconds']*1000,3),flush=True)
summary={}
for count in [25000,250000]:
 for shape in ['small','large','root']:
  for filter_case in ['empty','mask','mixed']:
   group=[r for r in rows if (r['files'],r['scenario'],r['filter_case'])==(count,shape,filter_case)]
   assert len(group)==a.pairs*3 and len({r['checksum'] for r in group})==1
   key=f'{count}-{shape}-{filter_case}';summary[key]={}
   for mode in modes:
    selected=[r for r in group if r['mode']==mode]
    values={k:[r[k] for r in selected] for k in ['focus_ready_seconds','total_seconds']}
    for field in ['resident_bytes','physical_footprint_bytes','peak_rss_bytes']:
     values['after_'+field]=[r['after'][field] for r in selected]
    summary[key][mode]={k:{'median':statistics.median(v),'min':min(v),'max':max(v)} for k,v in values.items()}
assert sha(probe)==manifest['probe_sha256']
report={'scope':'kernel metadata prototype only; same frozen private predicates/UInt8 bulk ancestor contexts; current full, loop-fusion control and focus-first. Focus callback holds immutable whole arrays until final validation, includes actual COW; no geometry/IPC/MCP/GUI publication or Windows timing claim. Frozen snapshots are focus-complete only, not global totals. RSS primary samples end before oracle; whole-process peaks include it. Shared-host/noise limitation applies.','pairs':a.pairs,'modes':modes,'rows':rows,'summary':summary,'verification':json.loads(verification.stdout),'verification_stdout_sha256':sha(out/'verification.stdout'),'probe_sha256':sha(probe),'build_manifest':str(build/'build-manifest.json'),'build_manifest_sha256':sha(build/'build-manifest.json'),'runner_sha256':sha(Path(__file__))}
(out/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({'rows':len(rows),'cases':len(summary),'passed':True}))
