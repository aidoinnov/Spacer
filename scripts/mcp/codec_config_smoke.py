#!/usr/bin/env python3
"""Native app adapter QA using independently generated SNS/XML fixtures."""
import argparse, json, time
from pathlib import Path
from space_sniffer_mcp import Bridge

p=argparse.ArgumentParser();p.add_argument('--bundle-id',required=True);p.add_argument('--fixtures',required=True);p.add_argument('--output',required=True);a=p.parse_args()
out=Path(a.output).resolve();out.mkdir(exist_ok=False,parents=True);fixtures=Path(a.fixtures).resolve();b=Bridge(a.bundle_id)
instances=b.instances();assert len(instances)==1
initial=b.call_app('app_status',{});assert len(initial['windows'])==1
window={'window_id':initial['windows'][0]['window_id']};events=[]
def call(command,**args):
    result=b.call_app(command,window|args);events.append({'command':command,'arguments':args,'result':result});return result
def state():return call('app_status')
def job(command,success=True,**args):
    accepted=call(command,**args);deadline=time.monotonic()+30
    while time.monotonic()<deadline:
        status=call('task_status',job_id=accepted['job_id'])
        if status['phase']!='running':
            assert status['phase']==('completed' if success else 'failed'),status
            return status.get('result') if success else status
        time.sleep(.02)
    raise AssertionError('Artifact job timeout')
def ready(root):
    deadline=time.monotonic()+30
    while time.monotonic()<deadline:
        value=state()
        if not value['projection_pending']:
            assert value['root']==root,value;return value
        time.sleep(.02)
    raise AssertionError('Projection timeout')
job('snapshot_load',path=str(fixtures/'single.sns'));ready('/qa/first')
before=state()['snapshot_revision']
roots=job('snapshot_load',path=str(fixtures/'multiple.sns'),inspect_only=True)['roots']
assert [r['path'] for r in roots]==['/qa/first','/qa/second']
assert state()['snapshot_revision']==before
job('snapshot_load',success=False,path=str(fixtures/'multiple.sns'))
assert state()['snapshot_revision']==before
job('snapshot_load',path=str(fixtures/'multiple.sns'),root_index=1);ready('/qa/second')
before=state()['snapshot_revision']
job('snapshot_load',success=False,path=str(fixtures/'malformed.sns'),root_index=0)
assert state()['snapshot_revision']==before
job('snapshot_load',success=False,path=str(fixtures/'legacy.sns'))
assert state()['snapshot_revision']==before
job('snapshot_load',path=str(fixtures/'legacy.sns'),legacy_code_page=1252);ready('C:\\café')
job('snapshot_load',path=str(fixtures/'single.sns'));ready('/qa/first')
inspection=job('report_export',configuration_path=str(fixtures/'export.xml'),configuration_index=0,inspect_only=True)
assert not inspection['applied_to_window'] and inspection['selected_export']['detail']=='<%pathfile%>{&br}'
destination=out/'configured.txt'
job('report_export',configuration_path=str(fixtures/'export.xml'),output=str(destination),max_output_bytes=4096)
expected=('\n'.join(['/qa/first']+[f'/qa/first/entry-{i:02d}.bin' for i in range(24)])+'\n').encode()
assert destination.read_bytes()==expected
failed=out/'limited.txt'
job('report_export',success=False,configuration_path=str(fixtures/'export.xml'),output=str(failed),max_output_bytes=1)
assert not failed.exists() and not list(out.glob('*.tmp'))
try:call('report_export',output=str(out/'ignored-cap.txt'),max_output_bytes=1)
except RuntimeError as e:assert str(e).startswith('invalid_argument:'),e
else:raise AssertionError('Unconfigured output cap must not be silently ignored')
default=out/'default.txt';job('report_export',output=str(default))
assert b'\r\n' not in default.read_bytes() and len(default.read_bytes().splitlines())==24
assert state()['space_accounting'] is None
job('snapshot_load',path=str(fixtures/'single.DU'));du=ready('C:\\')
assert du['displayed_bytes']==10240 and du['snapshot_files']==0 and not du['root_is_volume']
du_report=out/'du-files.txt';job('report_export',output=str(du_report));assert du_report.read_bytes()==b''
du_sns=out/'du.sns';job('snapshot_save',output=str(du_sns));job('snapshot_load',path=str(du_sns));assert ready('C:\\')['displayed_bytes']==10240
du_roots=job('snapshot_load',path=str(fixtures/'multiple.DU'),inspect_only=True)['roots']
assert [row['path'] for row in du_roots]==['C:\\','D:\\']
job('snapshot_load',path=str(fixtures/'multiple.DU'),root_index=1);assert ready('D:\\')['displayed_bytes']==2048
job('snapshot_load',success=False,path=str(fixtures/'legacy.DU'))
job('snapshot_load',path=str(fixtures/'legacy.DU'),legacy_code_page=1252);assert ready('C:\\')['displayed_bytes']==1024
job('snapshot_load',path=str(fixtures/'single.sns'));ready('/qa/first')
(out/'report.json').write_text(json.dumps({'result':'PASS','instances':instances,'initial':initial,'events':events,
    'scope':'native QA bundle + independent synthetic records; not Windows runtime interoperability'},ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'result':'PASS','requests':len(events),'output':str(out)}))
