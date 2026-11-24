#!/usr/bin/env python3
"""Validate recorded bounded AX component work; not a full draw/VoiceOver benchmark."""
import argparse,hashlib,json
from pathlib import Path
root=Path(__file__).resolve().parents[1];folder=root/'docs/validation/accessibility-cache-2026-11-09'
parser=argparse.ArgumentParser();parser.add_argument('--historical',action='store_true');args=parser.parse_args()
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def check(ok,why):
 if not ok:raise SystemExit('FAIL: '+why)
r=json.loads((root/'docs/validation/accessibility-cache-2026-11-09.json').read_text())
check(len(r['rows'])==20,'paired sample count')
for file,digest in r['source_sha256'].items():
 source=folder/'source-archive'/file if args.historical else root/file
 check(sha(source)==digest,'source '+file)
check(sha(root/'dist/accessibility-cache-2026-11-09/map-accessibility')==r['probe_sha256'],'probe binary')
previous=json.loads((root/'docs/validation/refresh-lifecycle-2026-11-09/source-manifest.json').read_text())
check(sha(folder/'TreemapView-before.swift')==r['baseline_source_sha256']==previous['files']['Sources/MacSpaceSniffer/TreemapView.swift'],'preserved published baseline')
for n in [32,10000]:
 rows=[v for v in r['rows'] if v['items']==n];check(len(rows)==10 and len({v['checksum'] for v in rows})==1,'presentation checksum')
 for row in rows:
  cap=min(500,n);check(row['created_elements']==cap*(60 if row['mode']=='legacy' else 1),'native element creations')
  check(row['visited_items']==60*(n if row['mode']=='legacy' else cap),'candidate visits')
  check(row['retained_elements_after_clear']==0,'clear')
 for mode in ['legacy','cache']:check(sum(v['mode']==mode for v in rows)==5,'five pairs')
 s=r['summary'][str(n)];check(s['cache']['seconds']['median']<s['legacy']['seconds']['median'],'component time improvement')
log=(folder/'tsan.log').read_text();check('Executed 94 tests, with 0 failures' in log and 'WARNING: ThreadSanitizer' not in log and 'reported ' not in log,'TSAN94')
for name in ['testBoundedCandidatesMatchLegacyOrderAndStopBeforeTrailingItems','testIdentitySurvivesIDRelocationAndLabelFrameChanges','testOldElementActivationUsesCurrentValidatedPathAndCannotKeepOwnerAlive','testPruningAndClearReleaseElementsAndParentReferences']:check(name+"]' passed" in log,'native test '+name)
check('Ran 6 tests' in (folder/'python-tests.log').read_text(),'Python6')
archive=json.loads((folder/'source-manifest.json').read_text())
for file,digest in archive['files'].items():
 check(sha(folder/'source-archive'/file)==digest,'archive '+file)
 if not args.historical:check(sha(root/file)==digest,'current '+file)
qa=json.loads((folder/'mcp-results.json').read_text());check(qa['tools']==20 and 'actual app PNG capture' in qa['passed'],'actual app MCP')
press=json.loads((folder/'qa-after-ax-press.json').read_text())
check(press['app_status']['windows'][0]['selected_path'].endswith('/fixture/a'),'native AX activation/current selection')
pkg=json.loads((folder/'package.json').read_text());check(pkg['signature_verified'] and pkg['packaged_mcp_matches'] and set(pkg['architectures'].split())=={'arm64','x86_64'},'universal package')
check(sha(root/pkg['archived_zip'])==pkg['zip_sha256'],'archive ZIP')
if not args.historical:check(sha(root/'dist/MacSpaceSniffer-macOS.zip')==pkg['zip_sha256'],'current ZIP')
print(f"PASS: Swift94 TSAN/Python6, 20 paired native AX component samples, bounded creation/visits/clear, {'archived' if args.historical else 'current+archived'} source/ZIP, MCP{qa['rpc_requests']}")
print('B05 remains partial: text/font/tooltip/full-frame/VoiceOver transition and aggregate lifecycle validation are separate.')
