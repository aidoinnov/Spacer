#!/usr/bin/env python3
import argparse,hashlib,json,re,shutil,statistics,subprocess,time
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--output',required=True);p.add_argument('--scratch',required=True);p.add_argument('--count',type=int,default=250000);a=p.parse_args()
out=Path(a.output);out.mkdir(parents=True,exist_ok=False);scratch=Path(a.scratch);scratch.mkdir(parents=True,exist_ok=False)
probe=Path('dist/r-backlog-2026-11-09/artifact-pool-memory');source={}
for path in sorted(Path('Sources/SpaceSnifferCore').glob('*.swift')):
 archive=out/'source-archive'/path;archive.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(path,archive);source[str(path)]=hashlib.sha256(path.read_bytes()).hexdigest()
rows=[]
for pair in range(5):
 for mode in (['legacy','current'] if pair%2==0 else ['current','legacy']):
  path=scratch/f'{pair}-{mode}.sns'
  run=subprocess.run(['/usr/bin/time','-lp',str(probe),mode,str(a.count),str(path)],capture_output=True,text=True);assert run.returncode==0,run.stderr
  (out/f'{pair}-{mode}.stderr').write_text(run.stderr)
  r=json.loads(run.stdout);r.update(pair=pair,max_rss_bytes=int(re.search(r'(\d+)\s+maximum resident set size',run.stderr)[1]),peak_footprint_bytes=int(re.search(r'(\d+)\s+peak memory footprint',run.stderr)[1]))
  digest=hashlib.sha256()
  with path.open('rb') as f:
   while block:=f.read(1<<20):digest.update(block)
  r.update(output_bytes=path.stat().st_size,output_sha256=digest.hexdigest(),output_path=str(path));rows.append(r)
 assert rows[-1]['output_sha256']==rows[-2]['output_sha256'],'native record bytes changed'
require=[p for p,d in source.items() if hashlib.sha256(Path(p).read_bytes()).hexdigest()!=d];assert not require,require
summary={mode:{key:statistics.median(r[key] for r in rows if r['mode']==mode) for key in ['seconds','max_rss_bytes','peak_footprint_bytes']} for mode in ['legacy','current']}
report={'scope':'five alternating fresh-process release pairs; 250k synthetic long paths/Unicode names; native SNS file output; fixture + output included in process high-water RSS/footprint, timer only emit+finish; full v4 bytes equal to frozen historical writer; shared host load; not scan/FPS or a memory ceiling','rows':rows,'summary':summary,'source_sha256':source,'probe_sha256':hashlib.sha256(probe.read_bytes()).hexdigest(),'legacy_source_sha256':hashlib.sha256(Path('dist/r-backlog-2026-11-09/LegacySNSSnapshot.swift').read_bytes()).hexdigest()}
(out/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(summary))
