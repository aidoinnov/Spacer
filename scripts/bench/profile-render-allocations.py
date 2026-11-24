#!/usr/bin/env python3
"""MallocStackLogging on the owned release XCTest renderer, never on a user process."""
import argparse,gzip,hashlib,json,os,re,select,subprocess,time
from collections import defaultdict
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--output',required=True);a=p.parse_args();out=Path(a.output);out.mkdir(parents=True,exist_ok=False)
stacks=(out/'stack-logs').resolve();stacks.mkdir()
test=Path('.build/arm64-apple-macosx/release/MacSpaceSnifferPackageTests.xctest').resolve()
env=os.environ|{'MallocStackLogging':'1','MallocStackLoggingNoCompact':'1','MallocStackLoggingDirectory':str(stacks),'SNIFFER_RENDER_REPORT':str((out/'instrumented-frames.json').resolve()),'SNIFFER_RENDER_PROFILE_WAIT':'1'}
groups=defaultdict(lambda:{'calls':0,'allocated_bytes':0})
with (out/'test-stderr.log').open('w') as errors,(out/'test-stdout.log').open('w') as log:
 process=subprocess.Popen(['/Applications/Xcode.app/Contents/Developer/usr/bin/xctest','-XCTest','MacSpaceSnifferTests.MapRenderingTests/testRenderProbe',str(test)],env=env,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=errors,text=True)
 try:
  deadline=time.monotonic()+120
  while True:
   assert time.monotonic()<deadline,'renderer ready timeout'
   assert select.select([process.stdout],[],[],60)[0],'no renderer output'
   line=process.stdout.readline();assert line,'renderer exited before ready';log.write(line);log.flush()
   if 'SNIFFER_RENDER_PROFILE_READY' in line:break
  raw=out/'malloc-history.txt.gz'
  history=subprocess.Popen(['malloc_history',str(process.pid),'-allEvents'],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
  with gzip.open(raw,'wt') as compressed:
   for line in history.stdout:
    compressed.write(line)
    if not line.startswith('ALLOC '):continue
    if 'MapRenderingTests.sampledPixels' not in line:continue
    if 'com.apple.MallocStackLogging' in line or 'reap_orphaned_log_files' in line:continue
    mode='legacy' if 'LegacyMapCanvas.draw' in line else 'current' if 'MapCanvas.draw' in line else None
    if not mode:continue
    category='text_font' if any(s in line for s in ['NSParagraphStyle','NSMutableParagraphStyle','NSFont','NSStringDrawing','_NSCString','NSAttributedString']) else 'tooltip' if 'MapTooltipRegistry' in line else 'AX' if 'MapAccessibilityCache' in line else 'rect_index' if 'Dictionary' in line else 'other_draw'
    m=re.search(r'\[size=(\d+)\]',line)
    if m:groups[mode+'/'+category]['calls']+=1;groups[mode+'/'+category]['allocated_bytes']+=int(m[1])
  assert history.wait(timeout=10)==0
 finally:
  if process.poll() is None:process.stdin.write('x');process.stdin.flush()
  tail=process.communicate(timeout=20)[0];log.write(tail or '')
 assert process.returncode==0,process.returncode
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
report={'scope':'cumulative ALLOC events inside sampledPixels + draw only, one paired x20 frames per renderer, four items; first font initialization, ten warmups each and pixel oracle excluded by sampledPixels stack guard; MallocStackLogging internals excluded; instrumented times are not performance measurements; bitmap allocation/copy outside draw excluded; no compositor FPS claim','groups':dict(groups),'raw':str(raw),'raw_sha256':sha(raw),'test_binary_sha256':sha(test/'Contents/MacOS/MacSpaceSnifferPackageTests'),'source_manifest':'docs/validation/final-optimization-2026-11-09/delivery-source-manifest.json'}
(out/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
