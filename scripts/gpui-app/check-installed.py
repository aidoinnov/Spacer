#!/usr/bin/env python3
"""Exercise the installed production app through its bundled real STDIO MCP."""
import argparse,base64,json,os,struct,subprocess,sys,tempfile,time
from pathlib import Path
from qa_process_metrics import start_installed_app,verify_installed_resources,foreground_pid,create_probe,same_path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'mcp'))
from acceptance import Client,Bridge
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--app',type=Path,required=True);p.add_argument('--server',type=Path,required=True)
p.add_argument('--instance-id',type=int,help='Verify an already running installed instance without relaunching')
p.add_argument('--display-root',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
a=p.parse_args();assert not a.output.exists();a.output.mkdir(parents=True)
product=json.loads((Path(__file__).resolve().parents[2]/'gpui-app/product.json').read_text());bridge=Bridge();before={v['pid'] for v in bridge.instances()};report={'passed':False,'foregroundBefore':foreground_pid()};client=None;child=None
try:
 if a.instance_id:
  pid=a.instance_id;assert pid in before,'Requested installed instance not found'
  probe=create_probe();actual=probe.path(pid) if sys.platform=='win32' else probe.processes()[pid][1]
  expected=a.app/'Contents/MacOS/Spacer' if sys.platform=='darwin' else a.app
  assert same_path(actual,expected),'Requested instance executable differs from installed app'
  state=bridge.call_app('app_status',{'instance_id':pid});assert len(state['windows'])==1
  view=state['windows'][0]
  assert view['phase'] in ('completed','completed_with_issues') and Path(view['root'])==a.display_root.resolve() and view['focus_path']==view['root'] and not view['filter'],'Attached view changed since installation; preserve user analysis'
 else:
  with (a.output/'app.log').open('w') as log:
   child=start_installed_app(a.app,log)
  deadline=time.monotonic()+90;pid=None
  while time.monotonic()<deadline:
   fresh=[v['pid'] for v in bridge.instances() if v['pid'] not in before]
   if child: fresh=[v for v in fresh if v==child.pid]
   if len(fresh)==1:pid=fresh[0];break
   time.sleep(.1)
 assert pid,'Installed app controller not found'
 client=Client('local.macspacesniffer.app',a.server)
 info=client.result('initialize',{'protocolVersion':'2025-11-25','capabilities':{},'clientInfo':{'name':'spacer-installed-check','version':'1'}})
 assert info['serverInfo']['name']=='spacer',info
 client.child.stdin.write(b'{"jsonrpc":"2.0","method":"notifications/initialized"}\n');client.child.stdin.flush()
 window={}
 def call(name,args=None):
  result=client.result('tools/call',{'name':name,'arguments':{'instance_id':pid,**window,**(args or {})}})
  assert not result.get('isError'),(name,result)
  return result
 status=call('app_status')['structuredContent'];assert status['version']==product['version'];window['window_id']=status['windows'][0]['window_id']
 tools=client.result('tools/list')['tools'];assert len(tools)==22
 def settled(focus=None):
  deadline=time.monotonic()+120
  while time.monotonic()<deadline:
   value=call('app_status')['structuredContent']
   if value['phase'] in ('completed','completed_with_issues') and not value['projection_pending'] and not value.get('geometry_pending') and (focus is None or Path(value['focus_path'])==focus):return value
   assert value['phase']!='failed',value
   time.sleep(.1)
  raise TimeoutError('Installed scan did not settle')
 with tempfile.TemporaryDirectory(prefix='spacer-installed-fixture-') as temp:
  root=Path(temp);(root/'owned.txt').write_bytes(b'x'*17);(root/'한국어.txt').write_bytes(b'x'*33)
  for i in range(8):
   folder=root/f'group-{i}';folder.mkdir();(folder/'data.bin').write_bytes(b'x'*(7*(i+1)))
  call('scan_start',{'path':str(root),'watching':False});value=settled();assert value['files']==10 and value['logical_bytes']==302 and value['issue_count']==0,value
  call('view_set',{'size_mode':'logical','depth':1});value=settled()
  canonical_root=Path(value['root'])
  children=call('tree_children',{'path':value['root'],'filtered':False,'limit':100})['structuredContent']['items']
  assert len([item for item in children if item['is_directory']])==8,children
  call('view_capture');time.sleep(.7)
  image=next(v for v in call('view_capture')['content'] if v['type']=='image');fixture_image=base64.b64decode(image['data'])
  dimensions=struct.unpack('>II',fixture_image[16:24]);assert dimensions[0]>=640 and dimensions[1]>=480,dimensions
  (a.output/'eight-folders.png').write_bytes(fixture_image)
  canonical_child=Path(next(item['path'] for item in children if item['name']=='group-3'))
  call('view_set',{'path':str(root/'group-3')});value=settled(canonical_child);assert Path(value['focus_path']).name=='group-3',value
  call('view_set',{'action':'up'});value=settled(canonical_root);assert Path(value['focus_path']).name==root.name,value
  report['oracle']={'files':10,'logicalBytes':302,'issues':0,'rootFolders':8}
  report['navigation']={'enterFolder':True,'upToRoot':True}
  report['fixtureCapture']={'width':dimensions[0],'height':dimensions[1]}
  call('view_set',{'size_mode':'allocated'})
 call('scan_start',{'path':str(a.display_root),'watching':False});value=settled()
 call('view_capture');time.sleep(.7)
 image=next(v for v in call('view_capture')['content'] if v['type']=='image');data=base64.b64decode(image['data']);assert data.startswith(b'\x89PNG\r\n\x1a\n');(a.output/'installed.png').write_bytes(data)
 report['foregroundAfter']=foreground_pid();assert report['foregroundAfter']!=pid or report['foregroundBefore']==pid,'Installed app took foreground focus'
 report.update(passed=True,pid=pid,version=product['version'],serverInfo=info['serverInfo'],toolCount=len(tools),displayRoot=value['root'],displayFiles=value['files'],leftRunning=True)
except Exception as error:report['error']=repr(error)
finally:
 if client:client.close()
 if not report.get('passed') and child is not None and child.poll() is None:
  try:
   state=bridge.call_app('app_status',{'instance_id':child.pid})
   for owned_window in state['windows']:
    bridge.call_app('window_close',{'instance_id':child.pid,'window_id':owned_window['window_id']})
   child.wait(timeout=8)
  except Exception:
   if child.poll() is None:child.terminate();child.wait(timeout=8)
  report['failedOwnedAppExit']=child.returncode
 if report.get('passed'):
  try:report['integrity']=verify_installed_resources(a.app,a.server)
  except Exception as error:report.update(passed=False,error=repr(error))
 (a.output/'results.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report));sys.exit(0 if report['passed'] else 1)
