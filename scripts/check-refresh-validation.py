#!/usr/bin/env python3
"""Validate recorded current queue evidence; does not rerun timings or the app."""
import argparse,hashlib,json
from pathlib import Path
root=Path(__file__).resolve().parents[1]
folder=root/'docs/validation/refresh-queue-2026-11-09'
parser=argparse.ArgumentParser();parser.add_argument('--historical',action='store_true');args=parser.parse_args()
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def check(ok,why):
 if not ok:raise SystemExit('FAIL: '+why)
r=json.loads((root/'docs/validation/refresh-queue-2026-11-09.json').read_text())
legacy=(root/'Tests/SpaceSnifferCoreTests/LegacyRefreshQueue.swift').read_text().replace('@testable import SpaceSnifferCore\n','').replace('struct LegacyRefreshQueue','struct RefreshQueue')
check(legacy==(root/'docs/validation/artifact-2026-11-09/source-archive/Sources/SpaceSnifferCore/RefreshQueue.swift').read_text(),'frozen pre-change oracle')
check(len(r['rows'])==100,'sample count')
for file,digest in r['source_sha256'].items():
 source=folder/'source-archive'/file if args.historical else root/file
 check(sha(source)==digest,'source drift '+file)
check(sha(root/'dist/refresh-queue-2026-11-09/refresh-queue')==r['probe_sha256'],'probe hash')
for case in r['summary']:
 scenario,n=case.rsplit('-',1);rows=[v for v in r['rows'] if v['scenario']==scenario and v['n']==int(n)]
 check(len(rows)==10 and len({(v['checksum'],v['pops']) for v in rows})==1,'FIFO checksum '+case)
 check(all(v['idle_slots']==0 for v in rows),'idle slots '+case)
 check(all(sum(v['mode']==m for v in rows)==5 for m in ['legacy','indexed']),'paired samples '+case)
for n in [1000,2000,4000]:
 s=r['summary'][f'independent-{n}'];check(s['indexed']['seconds']['max']<s['legacy']['seconds']['min'],'independent improvement')
log=(folder/'tsan.log').read_text();check('Executed 88 tests, with 0 failures' in log and 'WARNING: ThreadSanitizer' not in log and 'reported ' not in log,'TSAN record')
check("testFSEventsBurstAndWatchReplacementPreserveIndependentBranches]' passed" in log,'live engine burst test')
check('Ran 6 tests' in (folder/'python-tests.log').read_text(),'Python record')
qa=json.loads((folder/'mcp-results.json').read_text());check(qa['tools']==20 and 'real admission metrics and explicit scheduling-error field' in qa['passed'],'MCP integration')
burst=json.loads((folder/'burst-results.json').read_text());check(burst['burst']['snapshot_files']==49 and burst['replacement']['snapshot_files']==50,'app burst convergence')
check(burst['resources_released']['engine']['cached_roots']==1,'old root release')
pkg=json.loads((folder/'package.json').read_text());check(set(pkg['architectures'].split())=={'arm64','x86_64'} and pkg['signature_verified'] and pkg['packaged_mcp_matches'],'universal package')
check(sha(root/pkg['archived_zip'])==pkg['zip_sha256'],'archived ZIP')
if not args.historical:check(sha(root/'dist/MacSpaceSniffer-macOS.zip')==pkg['zip_sha256'],'current ZIP')
archive=json.loads((folder/'source-archive-manifest.json').read_text())
for file,digest in archive['files'].items():
 check(sha(folder/'source-archive'/file)==digest,'archived source '+file)
 if not args.historical:check(sha(root/file)==digest,'current source '+file)
before=json.loads((folder/'main-before.json').read_text());after=json.loads((folder/'main-after.json').read_text())
check(before['app_status']['pid']!=after['app_status']['pid'],'main restart')
check(all(w['phase']=='idle' for w in after['app_status']['windows']) and not after['app_status']['jobs'],'idle main')
print(f"PASS: 100 paired queue samples/FIFO hashes/idle slots, {'archived' if args.historical else 'current'} source+probe+ZIP, recorded Swift88/Python6/MCP{qa['rpc_requests']}, live burst {burst['rpc_requests']} requests")
print('Initial queue-stage record only; subsequent B08.08 lifecycle work is validated separately.')
