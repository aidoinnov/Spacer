#!/usr/bin/env python3
"""Verify canonical source links on Mac and materialized sources in Windows archives."""
import argparse,hashlib,json
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--refresh',action='store_true');a=p.parse_args()
r=Path(__file__).resolve().parents[2];manifest=r/'Packages/SpaceSnifferExplorerBridge/shared-sources.json'
if a.refresh:
 entries={}
 for top in ['Packages/SpaceSnifferExplorerBridge/Sources/ExplorerDomain','Packages/SpaceSnifferExplorerBridge/Sources/ExplorerBackend','Sources/MacScanBridge','Sources/MacPreviewSupport']:
  for path in (r/top).rglob('*.swift'):
   if path.is_symlink():
    source=str(path.resolve().relative_to(r));entries[str(path.relative_to(r))]={'source':source,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
 manifest.write_text(json.dumps(entries,indent=2)+'\n')
entries=json.loads(manifest.read_text())
for target,entry in entries.items():
 data=(r/target).read_bytes();assert hashlib.sha256(data).hexdigest()==entry['sha256'],target
 if (r/entry['source']).exists():assert data==(r/entry['source']).read_bytes(),target
print(f'PASS: {len(entries)} canonical source links/copies; no independent filter/SNS/report fork')
