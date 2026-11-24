#!/usr/bin/env python3
"""Check retained scan/scratch evidence. Does not rerun runtime or performance tests."""
import argparse,hashlib,json,re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser();parser.add_argument('--historical',action='store_true');args=parser.parse_args()
def read(p):return json.loads((ROOT/p).read_text())
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def check(ok,why):
 if not ok:raise SystemExit('FAIL: '+why)
files=['docs/validation/scan-admission-2026-11-09.json','docs/validation/scan-resources-2026-11-09.json','docs/validation/allocations-adopted-2026-11-09/report.json']
archive_manifest=read('docs/validation/scan-resource-2026-11-09/source-archive-manifest.json') if args.historical else None
if args.historical:
 for source,digest in archive_manifest['files'].items():check(sha(ROOT/'docs/validation/scan-resource-2026-11-09/source-archive'/source)==digest,'archived source '+source)
for file in files:
 for source,digest in read(file)['source_sha256'].items():
  target=ROOT/'docs/validation/scan-resource-2026-11-09/source-archive'/archive_manifest['recorded_source_paths'][source] if args.historical else ROOT/source
  check(sha(target)==digest,'source drift '+source)
allocation=read(files[2]);modes={r['mode']:r for r in allocation['rows']}
for row in allocation['rows']:check(sha(ROOT/row['raw'])==row['raw_sha256'],'allocation raw hash')
fresh=modes['filter-fresh'];reuse=modes['filter-reuse']
check(fresh['probe_result']['checksum']==reuse['probe_result']['checksum'],'profile filter checksum')
for key in ['calls','allocated_bytes']:check(reuse['groups']['filter_membership'][key]<fresh['groups']['filter_membership'][key],'allocation benefit '+key)
fs=read(files[0]);check(len(fs['rows'])==75,'filesystem samples')
for roots in [1,8,32]:
 for mode in ['detached','1','2','4','8']:
  rows=[r for r in fs['rows'] if r['roots']==roots and r['mode']==mode]
  check(len(rows)==5,'filesystem sample group')
  for row in rows:
   check(row['files']==roots*1000 and row['checksum']==roots*256000,'filesystem result mismatch')
   if mode!='detached':check(0<row['peak_admitted']<=int(mode),'admission bound')
resources=read(files[1]);check(len(resources['rows'])==25,'filter/response samples')
for kind in ['filter','response']:check(len({r['checksum'] for r in resources['rows'] if r['kind']==kind})==1,'result checksum '+kind)
for row in resources['rows']:
 if row['kind']=='response' and row['mode']!='detached':check(row['peak_operations']<=int(row['mode']),'actual operation bound')
folder=ROOT/'docs/validation/scan-resource-2026-11-09'
log=(folder/'final-tsan.log').read_text()
check('Executed 68 tests, with 0 failures' in log and 'WARNING: ThreadSanitizer' not in log and 'reported ' not in log,'final TSAN record')
check('Ran 6 tests' in (folder/'python-tests.log').read_text(),'Python record')
qa=read('docs/validation/scan-resource-2026-11-09/mcp-results.json');e=qa['resource_sample']['engine']
check(e['scan_limit']==8 and e['scan_queue_capacity']==64,'live configured limits')
check(0<=e['active_scans']<=8 and 0<=e['queued_scans']<=64 and e['peak_active_scans']<=8,'live admission counters')
check('real admission metrics and explicit scheduling-error field' in qa['passed'],'missing live API check')
package=read('docs/validation/scan-resource-2026-11-09/package-cli-check.json')
check(package['signature_verified'] and package['txt_bytes_equal'] and package['packaged_mcp_matches'],'packaged CLI/signature record')
check({'arm64','x86_64'}<=set(package['architectures'].split()),'universal architectures')
if not args.historical:check(sha(ROOT/'dist/MacSpaceSniffer-macOS.zip')==package['zip_sha256'],'delivered ZIP hash')
else:check(len(package['zip_sha256'])==64,'historical package hash record')
before=read('docs/validation/scan-resource-2026-11-09/main-before.json')
after=read('docs/validation/scan-resource-2026-11-09/main-after.json')
check(before['app_status']['pid']!=after['app_status']['pid'],'main process restart')
check(after['app_resources']['engine']['scan_limit']==8 and after['app_resources']['engine']['scan_queue_capacity']==64,'live main limits')
check(all(w['phase']=='idle' for w in after['app_status']['windows']),'main idle state')
print(f"PASS: 75 filesystem samples / 25 filter-response samples / 5 allocation profiles / recorded Swift68 + Python6 + MCP{qa['rpc_requests']} / {'archived source hashes' if args.historical else 'current source and ZIP hashes'}")
if args.historical:print('Historical mode: validates archived source; previous ZIP is a recorded result, current ZIP belongs to the artifact phase.')
print('Checks recorded evidence; does not prove full TODO completion or Windows runtime equivalence.')
