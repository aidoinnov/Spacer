#!/usr/bin/env python3
"""Owned bounded fixtures; actual optimized Scanner alternating process pairs."""
import hashlib,json,os,shutil,statistics,subprocess,tempfile
from pathlib import Path
out=Path('docs/validation/r-backlog-2026-11-09/r14/adaptive-v2');target=out/'native-profile.json';assert not target.exists()
binary=Path('dist/r14-native-scan-v2').resolve()
root=Path(tempfile.mkdtemp(prefix='mac-space-sniffer-r14-native-v2-',dir='/private/tmp'))
rows=[];fixtures=[]
try:
 for kind in ('flat','recursive','wide-fallback'):
  d=root/kind;d.mkdir()
  if kind=='recursive':
   for i in range(32):
    branch=d/f'branch-{i:02}';branch.mkdir()
    for j in range(64):(branch/f'file-{j:03}.bin').write_bytes(b'x'*(j%5))
  else:
   for i in range(4100 if kind=='wide-fallback' else 2048):(d/f'file-{i:05}.bin').write_bytes(b'x'*(i%5))
  fixtures.append({'kind':kind,'root':str(d),'entries':sum(1 for _ in d.rglob('*'))})
  for pair in range(5):
   for mode in (('posix','adaptive') if pair%2==0 else ('adaptive','posix')):
    proc=subprocess.run(['nice','-n','10',str(binary),mode,str(d),'5'],capture_output=True,text=True,check=True)
    row=json.loads(proc.stdout);row.update(pair=pair,fixture=kind);rows.append(row)
   assert rows[-1]['checksum']==rows[-2]['checksum'],rows[-2:]
 report={'scope':'5 alternating fresh-process pairs per owned fixture, 5 scans/process; compile -O WMO. Same active user GUI scan and other agents: paired results describe only these fixtures, not overall volume speed. max RSS includes checksum and scan. No production default change.', 'binary_sha256':hashlib.sha256(binary.read_bytes()).hexdigest(),'fixtures':fixtures,'rows':rows,
  'summary':{k:{m:{'seconds_median':statistics.median(r['seconds'] for r in rows if r['fixture']==k and r['mode']==m),'seconds_range':[min(r['seconds'] for r in rows if r['fixture']==k and r['mode']==m),max(r['seconds'] for r in rows if r['fixture']==k and r['mode']==m)],'max_rss_bytes_median':statistics.median(r['max_rss_bytes'] for r in rows if r['fixture']==k and r['mode']==m)} for m in ('posix','adaptive')} for k in ('flat','recursive','wide-fallback')}}
 target.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report['summary']))
finally:
 shutil.rmtree(root)
 (out/'native-profile-cleanup.json').write_text(json.dumps({'removed_owned_fixture':str(root),'exists_after':root.exists()})+'\n')
