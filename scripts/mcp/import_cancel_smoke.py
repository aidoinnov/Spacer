#!/usr/bin/env python3
"""Supersede an in-flight real large import using a new explicit small live scan."""
import argparse,json,time
from pathlib import Path
from space_sniffer_mcp import Bridge

p=argparse.ArgumentParser();p.add_argument('--bundle-id',required=True);p.add_argument('--snapshot',required=True);p.add_argument('--output',required=True);a=p.parse_args()
out=Path(a.output).resolve();out.mkdir(parents=True,exist_ok=False)
fixture=out/'fixture';fixture.mkdir()
for i in range(3):(fixture/f'file-{i}').write_bytes(b'x'*(i+1))
b=Bridge(a.bundle_id);instances=b.instances();assert len(instances)==1
initial=b.call_app('app_status',{});assert len(initial['windows'])==1
target={'window_id':initial['windows'][0]['window_id']};events=[]
def call(command,**args):
    result=b.call_app(command,target|args)
    if command=='app_resources':result={'process':result['process']}
    events.append({'at':time.time(),'command':command,'arguments':args,'result':result})
    (out/'events.json').write_text(json.dumps(events,ensure_ascii=False,indent=2)+'\n');return result
baseline=call('app_resources')['process']['physical_footprint_bytes']
job=call('snapshot_load',path=str(Path(a.snapshot).resolve()));deadline=time.monotonic()+30
while time.monotonic()<deadline:
    status=call('task_status',job_id=job['job_id']);assert status['phase']=='running',status
    footprint=call('app_resources')['process']['physical_footprint_bytes']
    if footprint>baseline+16*1024*1024:break
    time.sleep(.1)
else:raise AssertionError('Did not observe real import allocation before cancellation')
cancelled_at=time.monotonic();call('scan_start',path=str(fixture),watching=False)
deadline=time.monotonic()+30
while time.monotonic()<deadline:
    status=call('task_status',job_id=job['job_id']);state=call('app_status')
    if status['phase']=='failed' and state['phase']=='completed' and not state['projection_pending']:break
    time.sleep(.05)
else:raise AssertionError('Superseded import did not cancel and settle the new scan')
assert state['snapshot_files']==3 and state['snapshot_logical_bytes']==6 and not state['offline']
seconds=time.monotonic()-cancelled_at;time.sleep(2);resources=call('app_resources')
(out/'report.json').write_text(json.dumps({'result':'PASS','instances':instances,'seconds_cancel_and_small_scan':seconds,
    'cancelled_job':status,'final_state':state,'resources_after':resources,'scope':'native large SNS import allocated before a new explicit scan cancels its control; model never replaced the new scan; shared host timing, not a hard latency/memory bound'},ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'result':'PASS','seconds_cancel_and_small_scan':seconds}))
