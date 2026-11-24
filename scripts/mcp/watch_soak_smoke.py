#!/usr/bin/env python3
"""Bounded real FSEvents repetition on an explicitly disposable QA fixture."""
import argparse,json,time
from pathlib import Path
from space_sniffer_mcp import Bridge

p=argparse.ArgumentParser();p.add_argument('--bundle-id',required=True);p.add_argument('--output',required=True);p.add_argument('--seconds',type=int,default=180);a=p.parse_args()
assert 30<=a.seconds<=600
out=Path(a.output).resolve();out.mkdir(parents=True,exist_ok=False);root=out/'fixture';root.mkdir()
for i in range(48):(root/f'branch-{i}').mkdir()
b=Bridge(a.bundle_id);instances=b.instances();assert len(instances)==1
status=b.call_app('app_status',{});assert len(status['windows'])==1
target={'window_id':status['windows'][0]['window_id']};samples=[];events=[]
def call(command,**arguments):return b.call_app(command,target|arguments)
def resources():
    r=call('app_resources');return {'process':r['process'],'engine':r['engine'],'scratch':r['scratch'],'canvases':r['canvases']}
def expected():
    paths=[p for p in root.rglob('*') if p.is_file()];return len(paths),sum(p.stat().st_size for p in paths)
def converge():
    files,size=expected();deadline=time.monotonic()+20
    while time.monotonic()<deadline:
        s=call('app_status')
        if s['phase']=='completed' and not s['projection_pending'] and s['snapshot_files']==files and s['snapshot_logical_bytes']==size:
            assert s['issue_count']==0 and s['watch_active'];return s
        time.sleep(.05)
    raise AssertionError({'expected_files':files,'expected_bytes':size,'state':s})
call('scan_start',path=str(root),watching=True);converge();before=resources()
started=time.monotonic();rounds=0
while time.monotonic()-started<a.seconds:
    for i in range(48):
        directory=root/f'branch-{i}';file=directory/'event.bin';renamed=directory/'renamed.bin'
        file.write_bytes(bytes([i])*((rounds%7+1)*(i+1)))
        file.rename(renamed)
        if (i+rounds)%3==0:renamed.unlink()
    state=converge();rounds+=1
    samples.append({'elapsed_seconds':time.monotonic()-started,'round':rounds,'files':state['snapshot_files'],
        'logical_bytes':state['snapshot_logical_bytes'],'revision':state['snapshot_revision'],'resources':resources()})
    (out/'samples.json').write_text(json.dumps(samples,indent=2)+'\n')
    time.sleep(.1)
call('view_set',watching=False)
deadline=time.monotonic()+10
while call('app_status')['watch_active'] and time.monotonic()<deadline:time.sleep(.05)
assert not call('app_status')['watch_active']
call('scan_stop');time.sleep(.5)
after=resources()
report={'result':'PASS','duration_seconds':time.monotonic()-started,'rounds':rounds,'operations':rounds*112,
    'before':before,'after':after,'final_state':call('app_status'),
    'scope':'native FSEvents write/rename/delete convergence on 48 disposable branches, exact file/byte oracle each round, watch stop; explicitly bounded minutes, not a long-duration production guarantee or forced OS overflow'}
(out/'report.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({k:report[k] for k in ['result','duration_seconds','rounds','operations']}))
