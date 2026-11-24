#!/usr/bin/env python3
"""Check recorded B08.08 evidence and exact current source/package identity."""
import argparse,hashlib,json,re
from pathlib import Path
root=Path(__file__).resolve().parents[1];folder=root/'docs/validation/refresh-lifecycle-2026-11-09'
parser=argparse.ArgumentParser();parser.add_argument('--historical',action='store_true');args=parser.parse_args()
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def check(ok,why):
 if not ok:raise SystemExit('FAIL: '+why)
log=(folder/'tsan.log').read_text()
check('Executed 90 tests, with 0 failures' in log and 'WARNING: ThreadSanitizer' not in log and 'reported ' not in log,'90 clean TSAN tests')
for name in ['testOldMonitorCallbackCannotQueueAfterReplacementOrRootRecreation','testRealFSEventsBurstCancelsRunningScanAndReleasesPromotedQueue']:
 check(name+"]' passed" in log,'lifecycle test '+name)
m=re.search(r'B08_LIVE pending=(\d+) slots=(\d+) status_seconds=([\d.e+-]+)',log)
check(m and int(m[1])==48 and int(m[2])>0 and float(m[3])>=0,'live queue promotion and status observation')
check('cancelled=true arena_released=true pending_after_stop=0 refreshed_bytes=96 roots_after_unsubscribe=0' in log,'actual cancellation/release/recovery observation')
check('Ran 6 tests' in (folder/'python-tests.log').read_text(),'Python6')
archive=json.loads((folder/'source-manifest.json').read_text())
for path,digest in archive['files'].items():
 check(sha(folder/'source-archive'/path)==digest,'archived source '+path)
 if not args.historical:check(sha(root/path)==digest,'current source '+path)
qa=json.loads((folder/'mcp-results.json').read_text());check(qa['tools']==20 and 'real admission metrics and explicit scheduling-error field' in qa['passed'],'MCP integration')
burst=json.loads((folder/'burst-results.json').read_text());check(burst['burst']['snapshot_files']==49 and burst['replacement']['snapshot_files']==50,'real app burst')
pkg=json.loads((folder/'package.json').read_text());check(pkg['signature_verified'] and pkg['packaged_mcp_matches'] and set(pkg['architectures'].split())=={'arm64','x86_64'},'universal package')
check(sha(root/pkg['archived_zip'])==pkg['zip_sha256'],'archived package')
if not args.historical:check(sha(root/'dist/MacSpaceSniffer-macOS.zip')==pkg['zip_sha256'],'current package')
print(f"PASS: Swift90 TSAN/Python6, real FSEvents pending={m[1]}/slots={m[2]}, running cancel/weak arena release/stale generations/recovery, {'archived' if args.historical else 'current+archived'} sources/ZIP, MCP{qa['rpc_requests']}+burst{burst['rpc_requests']}")
print('Weak object lifetime proves queue ownership release; it does not measure deep retained bytes or OS RSS return.')
