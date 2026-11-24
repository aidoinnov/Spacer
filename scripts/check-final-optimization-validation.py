#!/usr/bin/env python3
"""Validate retained final evidence; this does not create runtime measurements."""
import argparse,collections,hashlib,json,re,subprocess,tempfile,zipfile
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
F=ROOT/'docs/validation/final-optimization-2026-11-09'
p=argparse.ArgumentParser();p.add_argument('--require-complete',action='store_true')
p.add_argument('--historical',action='store_true',help='Validate frozen source archives and the retained release ZIP, without asserting current source/app completion.')
args=p.parse_args()
def require(value,message):
    if not value:raise SystemExit('FAIL: '+message)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read(name):return json.loads((F/name).read_text())
def verify(path,digest):require(sha(ROOT/path)==digest,'evidence hash: '+str(path))
source_root=F/'packaged-source-archive' if args.historical else ROOT
def verify_source(path,digest):require(sha(source_root/path)==digest,'source hash: '+str(path))

manifest=read('packaged-source-manifest.json')['files']
for path,digest in manifest.items():
    verify_source(path,digest)
    require(sha(F/'packaged-source-archive'/path)==digest,'packaged source archive: '+path)
kernel=read('paired-final/report.json')
require(kernel['pairs']==5 and len(kernel['rows'])==150,'kernel sample count')
groups=collections.defaultdict(list)
for row in kernel['rows']:groups[(row['probe'],row['scenario'])].append(row)
for key,rows in groups.items():
    require({r['pair'] for r in rows}==set(range(5)),str(key)+' missing pair')
    require(len({r['checksum'] for r in rows})==1,str(key)+' result checksum')
verify('dist/final-optimization-2026-11-09/final-probe',kernel['probe_sha256'])
# Later App lifecycle/scalar changes are intentionally not called measured App source.
for path,digest in kernel['source_sha256'].items():
    if args.historical:
        require(sha(F/'paired-final/source-archive'/path)==digest,'measured source archive: '+path)
    if path.startswith('Sources/SpaceSnifferCore/') or path in ['Sources/MacSpaceSniffer/TreemapView.swift','Sources/MacSpaceSniffer/MapTextCache.swift','Sources/MacSpaceSniffer/MapTransition.swift']:
        verify_source(path,digest)
allocation=read('allocations-final/report.json');require(len(allocation['rows'])==8,'allocation profile count')
for row in allocation['rows']:verify(row['raw'],row['raw_sha256'])
draw=read('render-allocations-warm/report.json');verify(draw['raw'],draw['raw_sha256'])
frames=read('render-dense-final.json');require(frames['pairs']==5 and frames['items']==200,'render scope')
require(collections.Counter({mode:sum(len(r['seconds']) for r in frames['rows'] if r['mode']==mode) for mode in ['legacy','current']})=={'legacy':1250,'current':1250},'render frame counts')
app=read('app-comparison.json')
for mode in ['navigation','resize']:
    for version in ['baseline','current']:
        group=app['groups'][mode][version];require(group['samples']==200,'app sample count')
        count=0
        for path,digest in group['reports'].items():
            verify(path,digest);report=json.loads((ROOT/path).read_text());count+=len(report['rows'])
            require(not report['initial']['window_occluded'],'initial occlusion')
            require(all(not r['window_occluded_before_capture'] and not r['window_occluded_after_capture'] for r in report['rows']),'occluded accepted sample')
        require(count==200,'native raw sample count')
visibility=read('app-visible-hidden-minimized/report.json')
require([r['state'] for r in visibility['states']]==['normal','hidden','minimized'],'native state matrix')
for row in visibility['states']:
    require(len(row['observations'])==20,'native visibility sample count')
    if row['state']!='normal':require(all(o['presentation']['timer_active']==0 and o['presentation']['text_entries']==0 for o in row['observations']),'hidden visual work retained')
cycles=read('lifetime-cycles.json')['rows'];require(len(cycles)==25,'native lifetime cycles')
for kind in ['partial','full']:
    native=read('two-window-'+kind+'.json')
    require(len(native['observations'])==20,'two-window samples')
    require(all(s['window_on_active_space'] and s['window_occluded']==(kind=='full') for s in native['observations']),'two-window native occlusion')
    require((0<native['intersection_area']<native['target_area']) if kind=='partial' else native['intersection_area']==native['target_area'],'native frame intersection')
space=read('other-space/report.json');require(len(space['observations'])==20,'Space samples')
require(all(not s['window_on_active_space'] and s['presentation']['timer_active']==0 and s['presentation']['text_entries']==0 for s in space['observations']),'off-Space visual work')
verify('docs/validation/final-optimization-2026-11-09/other-space/latest.png',space['png_sha256'])
require(not space['after_capture']['window_on_active_space'] and space['after_capture']['presentation']['text_entries']==0,'off-Space capture cleanup')
returned=read('visibility-return.json');require(not returned['window_occluded'] and returned['presentation']['text_entries']>0,'latest presentation restore')
for row in cycles:
    engine=row['resources']['engine']
    require(all(engine[k]==0 for k in ['cached_roots','subscribers','active_scans','queued_scans']),'root/worker leak after cycle')
require(read('multiwindow/last-close.json')['instances']==[],'QA last close')
require(all(not instances for instances in read('native-final-close.json').values()),'owned native instances remain after final close')
ready=read('main-ready.json');require(len(ready['status']['windows'])==1 and ready['status']['windows'][0]['phase']=='idle' and ready['status']['jobs']==[],'fresh main app readiness')
if not args.historical:verify('dist/Mac Space Sniffer.app/Contents/MacOS/MacSpaceSniffer',ready['binary_sha256'])
log=(F/'packaged-126-tsan.log').read_text();require('Executed 126 tests, with 1 test skipped and 0 failures' in log,'packaged TSAN suite')
require('WARNING: ThreadSanitizer' not in log and 'data race' not in log,'TSAN warning')
release=(F/'packaged-126-release.log').read_text();require('Executed 126 tests, with 1 test skipped and 0 failures' in release,'release suite')
python=(F/'final-python-tests.log').read_text();require('Ran 6 tests' in python and 'OK' in python,'Python protocol tests')
mcp=read('main-mcp/results.json');require(mcp['passed'] and mcp['tools']==20,'real packaged MCP')
package=read('package.json');require(package['signature_verified'] and package['packaged_mcp_matches'],'packaged signature/MCP')
require(set(package['architectures'].split())=={'arm64','x86_64'},'universal architectures')
verify(package['archived_zip'],package['zip_sha256'])
package_zip=ROOT/package['archived_zip'] if args.historical else ROOT/'dist/MacSpaceSniffer-macOS.zip'
if not args.historical:verify('dist/MacSpaceSniffer-macOS.zip',package['zip_sha256'])
with zipfile.ZipFile(package_zip) as archive:
    binary=archive.read('Mac Space Sniffer.app/Contents/MacOS/MacSpaceSniffer')
    require(hashlib.sha256(binary).hexdigest()==ready['binary_sha256'],'ZIP binary differs from readiness receipt')
    require(archive.read('Mac Space Sniffer.app/Contents/Resources/MCP/space_sniffer_mcp.py')==(source_root/'scripts/mcp/space_sniffer_mcp.py').read_bytes(),'packaged bridge source')
    if not args.historical:require(binary==(ROOT/'dist/Mac Space Sniffer.app/Contents/MacOS/MacSpaceSniffer').read_bytes(),'ZIP binary differs from delivered app')
if args.historical:
    # ditto preserves executable modes/signature metadata; the archived app is never launched.
    scratch=ROOT/'.build/tmp';scratch.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='historical-final-',dir=scratch) as extracted:
        subprocess.run(['ditto','-x','-k',str(package_zip),extracted],check=True)
        subprocess.run(['codesign','--verify','--deep','--strict',str(Path(extracted)/'Mac Space Sniffer.app')],check=True)
else:
    subprocess.run(['codesign','--verify','--deep','--strict',str(ROOT/'dist/Mac Space Sniffer.app')],check=True)
    require((ROOT/'dist/Mac Space Sniffer.app/Contents/Resources/MCP/space_sniffer_mcp.py').read_bytes()==(ROOT/'scripts/mcp/space_sniffer_mcp.py').read_bytes(),'delivered bridge source')
require(len(package['cli'])==2 and len({r['sns_sha256'] for r in package['cli']})==1 and len({r['txt_sha256'] for r in package['cli']})==1,'architecture SNS/TXT oracle')
original=read('remaining-59.json')
require(len(original['ids'])==59 and len(set(original['ids']))==59,'original active59 IDs')
if args.historical:
    receipt=read('final-evidence-check.json')
    require(receipt['result']=='PASS','original completion receipt')
    require(receipt['source_manifest_sha256']==sha(F/'packaged-source-manifest.json'),'original source manifest receipt')
    require(receipt['package_sha256']==package['zip_sha256'],'original package receipt')
    require(receipt['original_remaining_manifest_sha256']==sha(F/'remaining-59.json'),'original remaining manifest receipt')
    pending=receipt['pending_steps'];checked_count=receipt['checked_steps']
    require(checked_count+len(pending)==116,'original execution receipt count')
    if args.require_complete:require(checked_count==116 and not pending,'original receipt incomplete')
else:
    todo=(ROOT/'TODO.md').read_text();steps=re.findall(r'^- \[([ x])\] ((?:G|A|E|B)\d{2}\.\d{2}) ',todo,re.M)
    pending=[key for status,key in steps if status==' ']
    require(len(steps)==116,'execution step count')
    checked={key for status,key in steps if status=='x'};checked_count=len(checked)
    require(set(original['ids'])<=checked if args.require_complete else True,'original active59 incomplete')
    progress=json.loads((ROOT/'docs/optimization-execution-progress.json').read_text())
    require(checked==set(progress['completed_steps']),'evidence progress differs from TODO')
    if args.require_complete:require(not pending,'remaining execution steps: '+', '.join(pending))
report={'result':'PASS','scope':'retained evidence/hash/oracle consistency; native state matrix includes partial/full occlusion and off-active-Space; not Windows dynamic equivalence or long-term heap proof','checked_steps':116-len(pending),'pending_steps':pending,'kernel_samples':150,'render_frames':2500,'native_navigation_samples_per_version':200,'native_resize_samples_per_version':200,'native_lifetime_cycles':25,'source_manifest_sha256':sha(F/'packaged-source-manifest.json'),'package_sha256':package['zip_sha256'],'original_remaining_manifest_sha256':sha(F/'remaining-59.json')}
report['checked_steps']=checked_count
report['validation_mode']='historical' if args.historical else 'current'
if args.historical:
    report['scope']+='; frozen archives/release only; completion counts are the original receipt, not a current TODO or new runtime validation'
    report['completion_basis']='preserved final-evidence-check.json receipt; current TODO/progress not evaluated'
    report['original_check_sha256']=sha(F/'final-evidence-check.json')
    report['checker_sha256']=sha(Path(__file__))
    report['measured_source_archive_files']=len(kernel['source_sha256'])
    report['packaged_source_archive_files']=len(manifest)
    report['package_archive']=package['archived_zip']
(F/('final-evidence-check-historical.json' if args.historical else 'final-evidence-check.json')).write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report))
