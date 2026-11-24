#!/usr/bin/env python3
"""Verify the explicitly packaged candidate using its own public MCP bridge."""
import argparse,base64,importlib.util,json,subprocess,sys,time
from pathlib import Path
sys.dont_write_bytecode=True
p=argparse.ArgumentParser();p.add_argument('--proof',type=Path,required=True);a=p.parse_args();package=json.loads((a.proof/'packaging.json').read_text());fixture=json.loads((a.proof/'fixture.json').read_text());root=Path(fixture['root']);pid=package['gui_pid'];binary=Path(package['candidate_app'])/'Contents/MacOS/MacSpaceSniffer'
assert subprocess.check_output(['/bin/ps','-p',str(pid),'-o','comm='],text=True).strip()==str(binary)
spec=importlib.util.spec_from_file_location('scope_bridge',Path(package['candidate_app'])/'Contents/Resources/MCP/space_sniffer_mcp.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);bridge=module.Bridge()
bridge.handle(dict(jsonrpc='2.0',id=1,method='initialize',params=dict(protocolVersion=module.LEGACY[0],capabilities={},clientInfo=dict(name='scope-native-qa',version='1'))))
def request(name,**args):
 result=bridge.handle(dict(jsonrpc='2.0',id=2,method='tools/call',params=dict(name=name,arguments=dict(instance_id=pid,**args))))
 assert not result.get('isError'),result
 return result
def call(name,**args):return request(name,**args)['structuredContent']
call('app_instances');state=call('app_status');window=state['windows'][0]['window_id']
def settle(files,mode,name):
 deadline=time.monotonic()+25
 while time.monotonic()<deadline:
  state=call('app_status');w=next(x for x in state['windows'] if x['window_id']==window)
  if w['phase']=='completed' and not w['projection_pending'] and w['snapshot_files']==files and w['volume_traversal']==mode:
   (a.proof/(name+'.json')).write_text(json.dumps(state,indent=2)+'\n');return w
  time.sleep(.05)
 raise RuntimeError('candidate did not settle: '+json.dumps(w))
def capture(name):
 image=next(x for x in request('view_capture',window_id=window)['content'] if x['type']=='image')
 (a.proof/(name+'.png')).write_bytes(base64.b64decode(image['data']))
initial=settle(100,'selectedVolume','ui-selected');assert initial['excluded_boundary_count']==1;capture('ui-selected')
call('scan_start',path=str(root),watching=True,include_mounted_volumes=True)
included=settle(6100,'allVolumes','ui-all');assert included['excluded_boundary_count']==0;capture('ui-all')
remote_delta=root/'foreign/watch-v00-delta.bin';assert not remote_delta.exists();remote_delta.write_bytes(b'1234567')
updated=settle(6101,'allVolumes','ui-all-watch');assert updated['snapshot_logical_bytes']==30307 and updated['volume_total_bytes']==included['volume_total_bytes']
call('scan_start',path=str(root),watching=True,include_mounted_volumes=False)
selected=settle(100,'selectedVolume','ui-selected-again');assert selected['excluded_boundary_count']==1
local_delta=root/'b0/watch-v00-local.bin';assert not local_delta.exists();local_delta.write_bytes(b'1234567')
updated=settle(101,'selectedVolume','ui-selected-watch');assert updated['snapshot_logical_bytes']==307;capture('ui-selected-watch')
for _ in range(100):
 resources=call('app_resources')
 if resources['engine']['cached_roots']==1:break
 time.sleep(.05)
assert resources['engine']['cached_roots']==1,resources['engine']
(a.proof/'ui-resources.json').write_text(json.dumps(resources,indent=2)+'\n')
package['gui_checks']=dict(default_selected=True,include_option=True,cross_volume_watch=True,selected_watch=True,root_capacity_preserved=True,mode_cache_isolated=True,forced_app_captures=True)
(a.proof/'packaging.json').write_text(json.dumps(package,indent=2)+'\n');print(json.dumps(package['gui_checks']))
