#!/usr/bin/env python3
"""Real QA windows; paired by caller. Capture waits for latest geometry on both builds."""
import argparse,base64,hashlib,importlib.util,json,statistics,time
from pathlib import Path
spec=importlib.util.spec_from_file_location('bridge',Path(__file__).parents[1]/'mcp/space_sniffer_mcp.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
p=argparse.ArgumentParser();p.add_argument('--bundle-id',required=True);p.add_argument('--fixture',required=True);p.add_argument('--output',required=True);p.add_argument('--mode',choices=['navigation','resize','visibility'],required=True);p.add_argument('--samples',type=int,default=40);p.add_argument('--pair',type=int,default=0);p.add_argument('--allow-occluded',action='store_true');p.add_argument('--states',default='normal,hidden,minimized');a=p.parse_args()
out=Path(a.output);out.mkdir(parents=True,exist_ok=False);bridge=module.Bridge(a.bundle_id);target={};requests=0
def call(name,**args):
 global requests
 requests+=1;return bridge.call_app(name,target|args)
def settled():
 deadline=time.monotonic()+30
 while time.monotonic()<deadline:
  s=call('app_status')
  if not s['projection_pending'] and s['phase'] not in ['idle','scanning']:return s
  time.sleep(.003)
 raise AssertionError(('not settled',s))
def artifact(name,**args):
 job=call(name,**args);deadline=time.monotonic()+30
 while time.monotonic()<deadline:
  state=call('task_status',job_id=job['job_id'])
  if state['phase']!='running':assert state['phase']=='completed',state;return state
  time.sleep(.01)
 raise AssertionError(('artifact timeout',state))
s=call('app_status');assert len(s['windows'])==1,s;target['window_id']=s['windows'][0]['window_id']
start=time.monotonic();artifact('snapshot_load',path=str(Path(a.fixture).resolve()));settled();load_seconds=time.monotonic()-start
call('view_set',action='root',expression='',size_mode='logical',depth=2,width=1340,height=860,window_state='normal');settled()
call('view_capture');time.sleep(.6)
# WindowServer/SwiftUI occlusion notifications can lag the control response.
# Wait outside measured interactions; never accept covered-window timings.
visibility_deadline=time.monotonic()+30;initial=call('app_status')
while initial['window_occluded'] and not (a.mode=='visibility' and a.allow_occluded) and time.monotonic()<visibility_deadline:
 time.sleep(.05);initial=call('app_status')
before=call('app_resources')
assert not initial['window_occluded'] or a.mode=='visibility' and a.allow_occluded,('QA window must be visibly raised before timing',initial)
rows=[];states=[]
if a.mode in ['navigation','resize']:
 for index in range(a.samples):
  args=({'path':f'/fixture/branch-{90+index%10}'} if index%2==0 else {'action':'root'}) if a.mode=='navigation' else {'width':1340+index%20*2,'height':860+index%7,'depth':2+index%2}
  start=time.monotonic();call('view_set',**args);state=settled()
  assert not state['window_occluded'],('window occluded during sample',index,state)
  row={'index':index,'pair':a.pair,'arguments':args,'window_occluded_before_capture':state['window_occluded']}
  if a.mode=='resize':
   capture=call('view_capture');png=base64.b64decode(capture['image']['data']);assert png.startswith(b'\x89PNG\r\n\x1a\n')
   assert capture['width']<=1600 and capture['height']<=1200
   row.update(png_sha256=hashlib.sha256(png).hexdigest(),png_bytes=len(png))
   if index in [0,a.samples-1]:(out/f'frame-{index}.png').write_bytes(png)
  else:assert state['focus_path']==args.get('path','/fixture'),state
  final_state=call('app_status');assert not final_state['window_occluded'],('window occluded after sample',index,final_state)
  row['seconds']=time.monotonic()-start;row['window_occluded_after_capture']=final_state['window_occluded'];rows.append(row)
else:
 for visible in a.states.split(','):
  assert visible in ['normal','hidden','minimized']
  call('view_set',window_state=visible);time.sleep(.7)
  r0=call('app_resources');start=time.monotonic();observed=[]
  for index in range(20):
   call('view_set',width=1340+index%20*2,height=860+index%7,depth=1+index%3)
   time.sleep(.02);observed.append(call('app_status'))
  r1=call('app_resources');states.append({'state':visible,'seconds':time.monotonic()-start,'before':r0,'after':r1,'observations':observed})
  if 'scratch' in r1:
   assert r1['scratch']['charged_idle_bytes']<=r1['scratch']['idle_limit_bytes']
   if visible!='normal':assert all(s['presentation']['timer_active']==0 and s['presentation']['text_entries']==0 for s in observed)
 call('view_set',window_state='normal');settled();call('view_capture')
after=call('app_resources');values=sorted(r['seconds'] for r in rows)
report={'scope':'actual QA window bridge/IPC; navigation to projection publication; resize includes latest geometry readiness + AppKit PNG render/encode; no compositor FPS claim; visibility samples are geometry-only changes (no filter/tag work)','mode':a.mode,'pair':a.pair,'bundle':a.bundle_id,'fixture_sha256':hashlib.sha256(Path(a.fixture).read_bytes()).hexdigest(),'script_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'load_seconds':load_seconds,'initial':initial,'requests':requests,'rows':rows,'states':states,'p50_seconds':statistics.median(values) if values else None,'p95_seconds':values[int(.95*(len(values)-1))] if values else None,'before':before,'after':after}
(out/'report.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({'mode':a.mode,'samples':len(rows),'p50':report['p50_seconds'],'p95':report['p95_seconds']}),flush=True)
