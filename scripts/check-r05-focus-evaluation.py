#!/usr/bin/env python3
"""Check frozen R05 experiment evidence; does not rerun timings or claim adoption."""
import datetime,hashlib,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
F=ROOT/'docs/validation/r-backlog-2026-11-09/r05'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def require(v,m):
 if not v:raise SystemExit('FAIL: '+m)
report=json.loads((F/'measurements-v1/report.json').read_text())
build=json.loads((ROOT/report['build_manifest']).read_text());base=(ROOT/report['build_manifest']).parent
require(sha(ROOT/report['build_manifest'])==report['build_manifest_sha256'],'build manifest hash')
require(sha(base/'r05-probe')==report['probe_sha256']==build['probe_sha256'],'probe hash')
for file,digest in build['source_sha256'].items():require(sha(base/'source-archive'/file)==digest,'frozen source '+file)
require(sha(ROOT/build['generated_filter'])==build['generated_filter_sha256'],'generated filter hash')
original=(base/'source-archive/Sources/SpaceSnifferCore/Filter.swift').read_text()
extension=(base/'source-archive/scripts/bench/r05-focus-extension.swift').read_text()
require((ROOT/build['generated_filter']).read_text()==original+'\n'+extension,'private-access source construction')
out=F/'measurements-v1';require(sha(out/'verification.stdout')==report['verification_stdout_sha256'],'verification raw hash')
require(sha(out/'runner-source.py')==report['runner_sha256'],'measured runner archive')
require(report['verification']=={'cancellation_checks':8,'comparisons':576,'passed':True},'oracle/cancel coverage')
require(report['pairs']==5 and len(report['rows'])==270 and len(report['summary'])==18,'paired sample count')
for row in report['rows']:
 for key in ['stdout','stderr']:require(sha(out/row['raw_'+key])==row[key+'_sha256'],'raw '+row['raw_'+key])
 raw=json.loads((out/row['raw_stdout']).read_text())
 require(all(raw[key]==row[key] for key in raw),'raw row mismatch')
 require(row['oracle_equal'] and row['frozen_scope_equal'],'oracle equality')
 if row['mode']=='focus' and row['scenario']!='root':require(row['weight_buffers_distinct'],'missing actual COW')
for files in [25000,250000]:
 for shape in ['small','large','root']:
  for case in ['empty','mask','mixed']:
   rows=[r for r in report['rows'] if (r['files'],r['scenario'],r['filter_case'])==(files,shape,case)]
   require(len(rows)==15 and len({r['checksum'] for r in rows})==1,'full output checksum')
   for mode in ['full','focus','fused']:require({r['pair'] for r in rows if r['mode']==mode}==set(range(5)),'five process pairs')
measured={p:h for p,h in build['source_sha256'].items() if p.startswith('Sources/')}
differences=[{'file':p,'measured_sha256':h,'current_sha256':sha(ROOT/p) if (ROOT/p).exists() else None} for p,h in measured.items() if not (ROOT/p).exists() or sha(ROOT/p)!=h]
hotpaths=['Filter.swift','FilterProjection.swift','FilterScratch.swift','Model.swift','NodeTable.swift']
def control_definition(path):
 text=path.read_text();start=text.index('public final class ScanControl:');end=text.index('\n}\n',start)+3;return text[start:end]
old_control=control_definition(base/'source-archive/Sources/SpaceSnifferCore/Scanner.swift')
current_control=control_definition(ROOT/'Sources/SpaceSnifferCore/Scanner.swift')
control_review={'exercised_declaration':'ScanControl','frozen_sha256':hashlib.sha256(old_control.encode()).hexdigest(),'current_sha256':hashlib.sha256(current_control.encode()).hexdigest(),'equal':old_control==current_control,'scope':'DiskScanner and its metadata backends are not called by this in-memory fixture/probe; a whole Scanner.swift change is recorded separately'}
hot_changed=[x['file'] for x in differences if Path(x['file']).name in hotpaths]
if old_control!=current_control:hot_changed.append('Sources/SpaceSnifferCore/Scanner.swift:ScanControl')
added=sorted(str(p.relative_to(ROOT)) for p in (ROOT/'Sources/SpaceSnifferCore').glob('*.swift') if str(p.relative_to(ROOT)) not in measured)
result={'result':'PASS','recorded_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'scope':'frozen kernel/immutable-reader experiment only; no production focus-first or GUI/MCP partial-revision adoption','rows':270,'pairs':5,'cases':18,'oracle_comparisons':576,'cancel_checks':8,'current_source_differences':differences,'added_current_core_files':added,'scan_control_review':control_review,'hotpath_files_changed':hot_changed,'report_sha256':sha(out/'report.json'),'build_manifest_sha256':sha(ROOT/report['build_manifest'])}
(F/'evidence-check.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))
