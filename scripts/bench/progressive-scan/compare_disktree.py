#!/usr/bin/env python3
"""Pinned disktree Core vs Swift scanner; engine-only, owned regular-file fixtures."""
import hashlib,json,os,shutil,statistics,subprocess,tempfile,time
from pathlib import Path
out=Path('docs/validation/disktree-2026-11-19'); target=out/'comparison.json'
if target.exists():raise SystemExit('refusing overwrite')
swift=Path('/private/tmp/sniffer-progressive-profile-instrumented')
rust=Path('/private/tmp/sniffer-disktree-bench-20261119/target/release/examples/speed_probe')
if shutil.disk_usage('/private/tmp').free<1024**3:raise SystemExit('insufficient reserve')
root=Path(tempfile.mkdtemp(prefix='sniffer-disktree-compare-'))
report={'scope':'engine-only release comparison, warm/unknown cache, shared host including running root scan; small regular-file fixtures, no whole-volume speed claim','disktree_head':'9b18b272ca3c5a145f6ff58eaf89dc4d311eeaea','disktree_options':'dedup_hardlinks=false to align path accounting; no mounts/symlinks in fixtures; worker 1 or 4; no GUI','binaries':{str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in [swift,rust]},'rows':[],'fixtures':[]}
try:
 for kind in ['flat-20000','branches-200x100']:
  fixture=root/kind;fixture.mkdir();expected=0
  for i in range(20000):
   if i%256==0 and shutil.disk_usage(root).free<1024**3:raise RuntimeError('reserve reached')
   parent=fixture if kind.startswith('flat') else fixture/f'b{i%200:03}'
   parent.mkdir(exist_ok=True)
   p=parent/f'f{i:05}.bin';p.write_bytes(b'x'*(1+i%128));expected+=p.stat().st_blocks*512
  info={'kind':kind,'files':20000,'folders':1 if kind.startswith('flat') else 201,'allocated_bytes':expected};report['fixtures'].append(info)
  for pair in range(5):
   modes=['swift-posix','swift-stream','disktree-1','disktree-4']
   if pair%2:modes.reverse()
   for mode in modes:
    cmd=[str(swift),'posix' if mode=='swift-posix' else 'stream',str(fixture)] if mode.startswith('swift') else [str(rust),str(fixture),mode[-1]]
    row={'fixture':kind,'pair':pair,'mode':mode}
    started=time.monotonic()
    try:
     p=subprocess.run(cmd,capture_output=True,text=True,timeout=60)
     row.update(exit_status=p.returncode,process_ms=(time.monotonic()-started)*1000)
     if p.returncode:row.update(status='failed',error=p.stderr[-2000:])
     else:
      r=json.loads(p.stdout);row['raw']=r
      row['ms']=r['scan_complete_ms'] if mode.startswith('swift') else r['ms']
      row['accurate_totals']=(r['files']==info['files'] and r.get('allocated_bytes',r.get('bytes'))==expected and r.get('folders',r.get('dirs'))==info['folders'])
      row['status']='ok' if row['accurate_totals'] else 'mismatch'
    except Exception as e:row.update(status='failed',error=str(e))
    report['rows'].append(row)
   print(kind,pair+1,flush=True)
   target.write_text(json.dumps(report,indent=2)+'\n')
  shutil.rmtree(fixture)
 report['summary']={}
 for kind in ['flat-20000','branches-200x100']:
  report['summary'][kind]={}
  for mode in ['swift-posix','swift-stream','disktree-1','disktree-4']:
   rows=[r for r in report['rows'] if r['fixture']==kind and r['mode']==mode and r['status']=='ok']
   v=[r['ms'] for r in rows]
   report['summary'][kind][mode]={'n':len(v),'p50_ms':statistics.median(v) if v else None,'min_ms':min(v) if v else None,'max_ms':max(v) if v else None}
 report['status']='measured_exploratory_5_pairs'
finally:
 shutil.rmtree(root);report['cleanup']={'owned_fixture_removed':not root.exists()}
 target.write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report.get('summary'),indent=2))
