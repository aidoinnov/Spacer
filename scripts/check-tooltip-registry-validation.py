#!/usr/bin/env python3
"""Check native tooltip registration component evidence, not full frame/Windows parity."""
import argparse,hashlib,json
from pathlib import Path
root=Path(__file__).resolve().parents[1];folder=root/'docs/validation/tooltip-registry-2026-11-09'
parser=argparse.ArgumentParser();parser.add_argument('--historical',action='store_true');args=parser.parse_args()
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def check(ok,why):
 if not ok:raise SystemExit('FAIL: '+why)
r=json.loads((root/'docs/validation/tooltip-registry-2026-11-09.json').read_text())
check(len(r['rows'])==30,'sample count')
archive=json.loads((folder/'source-manifest.json').read_text())
for file,digest in r['source_sha256'].items():
 target=folder/'source-archive'/file if args.historical and file in archive['files'] else root/file
 check(sha(target)==digest,'recorded source '+file)
check(sha(root/'dist/tooltip-registry-2026-11-09/map-tooltips')==r['probe_sha256'],'probe binary')
previous=json.loads((root/'docs/validation/accessibility-cache-2026-11-09/source-manifest.json').read_text())
check(sha(folder/'TreemapView-before.swift')==r['baseline_sha256']==previous['files']['Sources/MacSpaceSniffer/TreemapView.swift'],'published baseline')
for case,s in r['summary'].items():
 scenario,n=case.rsplit('-',1);n=int(n);rows=[v for v in r['rows'] if (v['scenario'],v['items'])==(scenario,n)]
 check(len(rows)==10 and len({v['checksum'] for v in rows})==1,'paired geometry '+case)
 for row in rows:
  rebuilds=60 if row['mode']=='legacy' or scenario=='moving' else 1
  check(row['rebuilds']==rebuilds and row['native_adds']==rebuilds*n and row['registered_after_clear']==0,'native registration counts')
 for mode in ['legacy','registry']:check(sum(v['mode']==mode for v in rows)==5,'five pairs')
 if scenario=='stationary':check(s['registry']['seconds']['median']<s['legacy']['seconds']['median'],'stationary component improvement')
log=(folder/'tsan.log').read_text();check('Executed 99 tests, with 0 failures' in log and 'WARNING: ThreadSanitizer' not in log and 'reported ' not in log,'clean TSAN99')
for name in ['testStationaryRedrawSkipsRegistrationAndContentResolvesLive','testRebuildRejectsDelayedTokenAndReusedNodeID','testEligibilityAndOrderMatchOriginalAndPendingGeometryDisablesTargets','testTransitionFramesAndInterruptedTransitionUseCurrentPresentationRects','testInvalidationReleasesViewAndOnlyCurrentTargetsRemain']:check(name+"]' passed" in log,'tooltip test '+name)
check('Ran 6 tests' in (folder/'python-tests.log').read_text(),'Python6')
archive=json.loads((folder/'source-manifest.json').read_text())
for file,digest in archive['files'].items():
 check(sha(folder/'source-archive'/file)==digest,'archive source '+file)
 if not args.historical:check(sha(root/file)==digest,'current source '+file)
qa=json.loads((folder/'mcp-results.json').read_text());check(qa['tools']==20 and 'actual app PNG capture' in qa['passed'],'real app MCP')
pkg=json.loads((folder/'package.json').read_text());check(pkg['signature_verified'] and pkg['packaged_mcp_matches'] and set(pkg['architectures'].split())=={'arm64','x86_64'},'universal package')
check(pkg['zip_sha256']==sha(root/pkg['archived_zip']),'archive package')
if not args.historical:check(sha(root/'dist/MacSpaceSniffer-macOS.zip')==pkg['zip_sha256'],'current package')
print(f"PASS: Swift99 TSAN/Python6, 30 paired native registration samples, stationary skip/moving rect updates/stale token guard/clear, current+archived source/ZIP, MCP{qa['rpc_requests']}")
print('B05 remains partial: text/font/full-frame/aggregate lifetime and Reduce Motion/VoiceOver full suite remain.')
