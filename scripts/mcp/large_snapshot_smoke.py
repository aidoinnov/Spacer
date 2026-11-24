#!/usr/bin/env python3
"""One retained real-volume SNS load and release in a separately identified QA app."""
import argparse, json, time
from pathlib import Path
from space_sniffer_mcp import Bridge

p=argparse.ArgumentParser();p.add_argument('--bundle-id',required=True);p.add_argument('--snapshot',required=True);p.add_argument('--release-fixture',required=True);p.add_argument('--output',required=True);a=p.parse_args()
out=Path(a.output);out.mkdir(parents=True,exist_ok=False);b=Bridge(a.bundle_id)
initial=b.call_app('app_status',{});assert len(initial['windows'])==1
target={'window_id':initial['windows'][0]['window_id']};events=[]
def call(command,**args):
    result=b.call_app(command,target|args)
    if command=='app_resources':
        result={key:result[key] for key in ['process','engine','canvases','scratch'] if key in result}
    events.append({'at':time.time(),'command':command,'arguments':args,'result':result})
    (out/'events.json').write_text(json.dumps(events,ensure_ascii=False,indent=2)+'\n')
    return result
def load(path):
    job=call('snapshot_load',path=str(Path(path).resolve()));deadline=time.monotonic()+300
    while time.monotonic()<deadline:
        status=call('task_status',job_id=job['job_id']);state=call('app_status')
        call('app_resources')
        if status['phase']=='failed':raise AssertionError(status)
        if status['phase']=='completed' and not state['projection_pending']:return state
        time.sleep(2)
    raise AssertionError('Large load timeout')
before=call('app_resources');loaded=load(a.snapshot)
assert loaded['offline'] and not loaded['watch_active'] and loaded['snapshot_nodes']>1_000_000
assert loaded['snapshot_logical_bytes']==loaded['volume_total_bytes'] # native drive wire capacity
assert loaded['displayed_bytes']<loaded['volume_total_bytes'] # file contributions stay separate
page=call('query_nodes',traversal='subtree',budget=500,limit=3)
assert page['traversal_steps']<=500 and page['next_cursor']
call('query_nodes',traversal='subtree',cursor=page['next_cursor'],cancel_cursor=True)
after_large=call('app_resources')
released=load(a.release_fixture);assert released['snapshot_nodes']<100
time.sleep(2);after_release=call('app_resources')
assert call('app_status')['query_session']['cursors']==0
(out/'report.json').write_text(json.dumps({'result':'PASS','scope':'actual retained live-volume SNS in offline QA window; one load/release, not long-duration watch test or memory ceiling',
    'loaded_state':loaded,'released_state':released,'before':before,'after_large':after_large,'after_release':after_release},ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'result':'PASS','nodes':loaded['snapshot_nodes'],'displayed_bytes':loaded['displayed_bytes']}))
