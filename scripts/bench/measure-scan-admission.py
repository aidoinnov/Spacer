#!/usr/bin/env python3
"""Sequential warm filesystem comparisons; no Windows or cold-disk equivalence claim."""
import argparse,hashlib,json,platform,re,statistics,subprocess
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--probe',required=True);p.add_argument('--fixture',required=True);p.add_argument('--output',required=True);a=p.parse_args()
modes=['detached','1','2','4','8']; rows=[]
# Warm all directory entries before the rotated comparisons.
subprocess.run([a.probe,'detached',a.fixture],check=True,capture_output=True)
for roots in [1,8,32]:
 for pair in range(5):
  for mode in modes[pair%len(modes):]+modes[:pair%len(modes)]:
   r=subprocess.run(['/usr/bin/time','-l',a.probe,mode,a.fixture,str(roots)],check=True,capture_output=True,text=True,timeout=55)
   v=json.loads(r.stdout);v['pair']=pair;v['max_rss_bytes']=int(re.search(r'(\d+)\s+maximum resident set size',r.stderr).group(1));rows.append(v)
for roots in [1,8,32]:assert len({v['checksum'] for v in rows if v['roots']==roots})==1
summary={str(roots):{mode:{k:{'median':statistics.median(v[k] for v in rows if v['mode']==mode and v['roots']==roots),'min':min(v[k] for v in rows if v['mode']==mode and v['roots']==roots),'max':max(v[k] for v in rows if v['mode']==mode and v['roots']==roots)} for k in ['seconds','max_rss_bytes']} for mode in modes} for roots in [1,8,32]}
files=sorted(Path('Sources').rglob('*.swift'))+[Path('Package.swift'),Path('scripts/bench/scan-admission.swift'),Path(__file__)]
result={'date':'2026-11-09','kind':'warm filesystem scan 1/8/32 independent roots, 1000 files x 256 bytes each; excludes fixture creation and UI','pairs':5,'fixture':{'roots':32,'files_per_root':1000,'bytes_per_file':256,'content_sha256':hashlib.sha256(b'x'*256).hexdigest(),'names':'root-{0...31}/file-{0000...0999}.bin'},'compiler':subprocess.check_output(['swiftc','--version'],text=True).strip(),'os':platform.platform(),'source_sha256':{str(f):hashlib.sha256(f.read_bytes()).hexdigest() for f in files},'probe_sha256':hashlib.sha256(Path(a.probe).read_bytes()).hexdigest(),'rows':rows,'summary':summary}
Path(a.output).write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(summary,indent=2))
