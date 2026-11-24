#!/usr/bin/env python3
"""Sequential resource probes, run after all builds/profilers have stopped."""
import argparse,hashlib,json,platform,re,statistics,subprocess
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--directory',required=True);p.add_argument('--output',required=True);a=p.parse_args()
bin=Path(a.directory);rows=[]
for pair in range(5):
 for kind,modes in [('filter',['filter-fresh','filter-reuse']),('response',['detached','4','8'])]:
  for mode in (modes if pair%2==0 else list(reversed(modes))):
   name='allocation-probe' if kind=='filter' else 'scan-response'
   cmd=[str(bin/name),mode]+(['250000'] if kind=='filter' else [])
   r=subprocess.run(['/usr/bin/time','-l',*cmd],capture_output=True,text=True,check=True,timeout=55)
   v=json.loads(r.stdout);v['pair']=pair;v['kind']=kind;v['max_rss_bytes']=int(re.search(r'(\d+)\s+maximum resident set size',r.stderr).group(1));rows.append(v)
for kind in ['filter','response']:assert len({v['checksum'] for v in rows if v['kind']==kind})==1
summary={}
for mode in ['filter-fresh','filter-reuse','detached','4','8']:
 samples=[r for r in rows if r['mode']==mode]
 keys=['compute_seconds','max_rss_bytes'] if mode.startswith('filter-') else ['response_seconds','all_io_seconds','peak_operations','max_rss_bytes']
 summary[mode]={k:{'median':statistics.median(r[k] for r in samples),'min':min(r[k] for r in samples),'max':max(r[k] for r in samples)} for k in keys}
sources=sorted(Path('Sources').rglob('*.swift'))+[Path('Package.swift'),Path('scripts/bench/allocation-probe.swift'),Path('scripts/bench/scan-response.swift'),Path(__file__)]
report={'date':'2026-11-09','scope':'filter: actual membership 250k nodes x40, checksum included, fixture excluded from compute duration; response: 32 synthetic 50ms blocking operations and one userInitiated 20k-node filter, not real disk latency or UI p95; process RSS includes fixture','pairs':5,'compiler':subprocess.check_output(['swiftc','--version'],text=True).strip(),'platform':platform.platform(),'source_sha256':{str(f):hashlib.sha256(f.read_bytes()).hexdigest() for f in sources},'probe_sha256':{name:hashlib.sha256((bin/name).read_bytes()).hexdigest() for name in ['allocation-probe','scan-response']},'rows':rows,'summary':summary}
Path(a.output).write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(summary,indent=2))
