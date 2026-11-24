#!/usr/bin/env python3
"""Owned QA window, actual bridge/UI intents. Navigation times end at projection publish, not compositor."""
import argparse,base64,importlib.util,json,statistics,time
from pathlib import Path
spec=importlib.util.spec_from_file_location('bridge',Path(__file__).parents[1]/'mcp/space_sniffer_mcp.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
p=argparse.ArgumentParser();p.add_argument('--bundle-id',required=True);p.add_argument('--fixture',required=True);p.add_argument('--output',required=True);p.add_argument('--mode',choices=['navigation','lifecycle'],required=True);p.add_argument('--pairs',type=int,default=5);a=p.parse_args()
out=Path(a.output);out.mkdir(parents=True,exist_ok=False);b=module.Bridge(a.bundle_id);target={};requests=0
def call(name,**args):
 global requests
 requests+=1;return b.call_app(name,target|args)
def settled(geometry=False):
 deadline=time.monotonic()+30
 while time.monotonic()<deadline:
  s=call('app_status')
  if not s['projection_pending'] and s['phase'] not in ['scanning','idle'] and (not geometry or s.get('presentation',{}).get('geometry_pending',0)==0):return s
  time.sleep(.003)
 raise AssertionError(('settle timeout',s))
def artifact(name,**args):
 job=call(name,**args)
 while True:
  status=call('task_status',job_id=job['job_id'])
  if status['phase']!='running':assert status['phase']=='completed',status;return status
  time.sleep(.01)
status=call('app_status');assert len(status['windows'])==1;target['window_id']=status['windows'][0]['window_id']
start=time.monotonic();artifact('snapshot_load',path=str(Path(a.fixture).resolve()));initial=settled();load_seconds=time.monotonic()-start
call('view_set',size_mode='logical',expression='',depth=2);settled();before=call('app_resources');rows=[]
if a.mode=='navigation':
 for pair in range(a.pairs):
  for index in range(40):
   args={'path':f'/fixture/branch-{90+index%10}'} if index%2==0 else {'action':'root'}
   start=time.monotonic();call('view_set',**args);s=settled();rows.append({'pair':pair,'index':index,'seconds':time.monotonic()-start,'focus':s['focus_path']})
   assert s['focus_path']==args.get('path','/fixture'),s
  print('navigation',pair,flush=True)
else:
 # A real-window resize sample is separate from the preserved offscreen renderer comparison.
 for index in range(220):
  start=time.monotonic();call('view_set',width=900+index%20,height=650+index%7,depth=2+index%2)
  s=settled(geometry=True);rows.append({'index':index,'seconds':time.monotonic()-start,'presentation':s['presentation']})
  assert s['presentation']['sort_slots']<=65536 and s['presentation']['rect_tiles']<=50000
 resources_before_hide=call('app_resources');states=[]
 for state in ['hidden','minimized','normal']:
  call('view_set',window_state=state);time.sleep(.15)
  s=call('app_status');r0=call('app_resources');time.sleep(.4);r1=call('app_resources')
  states.append({'state':state,'status':s,'before':r0,'after':r1})
  if state!='normal':
   assert s['presentation']['timer_active']==0 and s['presentation']['text_entries']==0 and s['presentation']['rect_tiles']==0,s
 # Hidden data still updates; capture prepares current geometry and then discards hidden presentation.
 call('view_set',window_state='hidden');time.sleep(.1)
 hidden_before=call('app_resources');old=call('tree_children',limit=1)
 call('node_tag',path='/fixture/branch-90',color=1);s=settled()
 assert call('node_info',path='/fixture/branch-90')['node']['own_tag']==1
 try:call('tree_children',limit=1,revision=old['revision']);raise AssertionError('stale pagination accepted')
 except RuntimeError as e:assert 'stale_revision' in str(e),e
 call('view_set',expression='*.bin',size_mode='allocated',show_hidden=False);s=settled()
 capture=call('view_capture');png=base64.b64decode(capture['image']['data']);assert png.startswith(b'\x89PNG\r\n\x1a\n');(out/'hidden.png').write_bytes(png)
 time.sleep(.1);after_capture=call('app_status');assert after_capture['presentation']['text_entries']==0 and after_capture['presentation']['timer_active']==0,after_capture
 call('view_set',window_state='normal',expression='',size_mode='logical',show_hidden=True);restored=settled(geometry=True)
 assert restored['presentation']['items']>0
 (out/'lifecycle.json').write_text(json.dumps({'states':states,'before_hide':resources_before_hide,'hidden_before':hidden_before,'hidden_projection':s,'after_capture':after_capture,'restored':restored},indent=2)+'\n')
after=call('app_resources');values=sorted(r['seconds'] for r in rows)
report={'scope':'actual QA app IPC/UI projection publication latency including bridge validation and polling; geometry readiness included only for lifecycle resize; not compositor FPS','bundle':a.bundle_id,'load_seconds':load_seconds,'initial':initial,'requests':requests,'rows':rows,'p50_seconds':statistics.median(values),'p95_seconds':values[int(.95*(len(values)-1))],'before':before,'after':after}
(out/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({'mode':a.mode,'samples':len(rows),'p50':report['p50_seconds'],'p95':report['p95_seconds']}),flush=True)
