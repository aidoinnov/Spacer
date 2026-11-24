#!/usr/bin/env python3
"""Validate current artifact evidence; does not rerun performance/runtime tests."""
import argparse,hashlib,json,re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def read(p):return json.loads((ROOT/p).read_text())
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def check(ok,why):
 if not ok:raise SystemExit('FAIL: '+why)
r=read('docs/validation/artifact-export-2026-11-09.json')
parser=argparse.ArgumentParser();parser.add_argument('--historical',action='store_true');args=parser.parse_args()
folder=ROOT/'docs/validation/artifact-2026-11-09'
check(len(r['rows'])==40,'export samples')
for path,digest in r['source_sha256'].items():
 relative=Path(path)
 if relative.is_absolute():
  # The original driver recorded its own absolute path. Match only the known suffix.
  check(str(relative).endswith('/scripts/bench/measure-artifact-export.py'),'unknown absolute source '+path)
  relative=Path('scripts/bench/measure-artifact-export.py')
 source=folder/'source-archive'/relative if args.historical else ROOT/relative
 check(sha(source)==digest,'source drift '+str(source))
check(sha(ROOT/'dist/artifact-2026-11-09/artifact-export')==r['probe_sha256'],'probe binary hash')
for format in ['txt','sns']:
 for scope in ['all','focus']:
  rows=[v for v in r['rows'] if v['format']==format and v['scope']==scope]
  check(len(rows)==10 and len({(v['bytes'],v['sha256']) for v in rows})==1,'byte equivalence '+format+scope)
  for mode in ['legacy','stream']:check(sum(v['mode']==mode for v in rows)==5,'paired samples')
for format in ['txt','sns']:
 summary=r['summary'][format+'-all']
 check(summary['stream']['max_rss_bytes']['max']<summary['legacy']['max_rss_bytes']['min'],'full export peak RSS ranges '+format)
folder=ROOT/'docs/validation/artifact-2026-11-09'
log=(folder/'final-tsan.log').read_text()
check('Executed 81 tests, with 0 failures' in log and 'WARNING: ThreadSanitizer' not in log and 'reported ' not in log,'TSAN record')
check('Ran 6 tests' in (folder/'python-tests.log').read_text(),'Python record')
qa=read('docs/validation/artifact-2026-11-09/mcp-results.json')
check('SNS save/load + TXT jobs + existing-output rejection' in qa['passed'],'MCP artifacts')
pkg=read('docs/validation/artifact-2026-11-09/package-cli-check.json')
check(pkg['signature_verified'] and pkg['packaged_mcp_matches'] and pkg['txt_equal'],'package record')
check(pkg['filtered_scan']['matchedBytes']==pkg['filtered_sns_load']['matchedBytes']==1048576,'CLI projection summary')
check({'arm64','x86_64'}<=set(pkg['architectures'].split()),'universal')
check(sha(ROOT/pkg['archived_zip'])==pkg['zip_sha256'],'archived ZIP')
if not args.historical:check(sha(ROOT/'dist/MacSpaceSniffer-macOS.zip')==pkg['zip_sha256'],'current ZIP')
archive=read('docs/validation/artifact-2026-11-09/source-archive-manifest.json')
for source,digest in archive['files'].items():
 if not args.historical:check(sha(ROOT/source)==digest,'current snapshot '+source)
 check(sha(folder/'source-archive'/source)==digest,'archived source '+source)
before=read('docs/validation/artifact-2026-11-09/main-before.json')
after=read('docs/validation/artifact-2026-11-09/main-after.json')
check(before['pid']!=after['app_status']['pid'],'main app restart')
check(all(w['phase']=='idle' for w in after['app_status']['windows']),'idle main app')
check(after['app_resources']['workers']['volumes.enumerate']['main_thread_runs']==0,'volume I/O main thread')
print(f"PASS: 40 full/scoped SNS/TXT samples, byte hashes, full-export RSS separation, recorded Swift81/Python6/MCP{qa['rpc_requests']}, {'archived' if args.historical else 'current+archived'} sources/ZIP")
print('Recorded evidence only; not Windows runtime equivalence or full TODO completion.')
