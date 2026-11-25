#!/usr/bin/env python3
"""Exercise the installed production app through its bundled real STDIO MCP."""
import argparse,base64,json,os,sys,tempfile,time
from pathlib import Path
from qa_process_metrics import start_installed_app,verify_installed_resources
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'mcp'))
from acceptance import Client,Bridge
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--app',type=Path,required=True);p.add_argument('--server',type=Path,required=True)
p.add_argument('--display-root',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
a=p.parse_args();assert not a.output.exists();a.output.mkdir(parents=True)
product=json.loads((Path(__file__).resolve().parents[2]/'gpui-app/product.json').read_text());bridge=Bridge();before={v['pid'] for v in bridge.instances()};report={'passed':False};client=None
try:
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
  def settled():
   deadline=time.monotonic()+120
   while time.monotonic()<deadline:
    value=call('app_status')['structuredContent']
    if value['phase'] in ('completed','completed_with_issues') and not value['projection_pending'] and not value.get('geometry_pending'):return value
    assert value['phase']!='failed',value
    time.sleep(.1)
   raise TimeoutError('Installed scan did not settle')
  with tempfile.TemporaryDirectory(prefix='spacer-installed-fixture-') as temp:
   root=Path(temp);(root/'owned.txt').write_bytes(b'x'*17);(root/'한국어.txt').write_bytes(b'x'*33)
   call('scan_start',{'path':str(root),'watching':False});value=settled();assert value['files']==2 and value['logical_bytes']==50 and value['issue_count']==0,value
   report['oracle']={'files':2,'logicalBytes':50,'issues':0}
  call('scan_start',{'path':str(a.display_root),'watching':False});value=settled()
  image=next(v for v in call('view_capture')['content'] if v['type']=='image');data=base64.b64decode(image['data']);assert data.startswith(b'\x89PNG\r\n\x1a\n');(a.output/'installed.png').write_bytes(data)
  report.update(passed=True,pid=pid,version=product['version'],serverInfo=info['serverInfo'],toolCount=len(tools),displayRoot=value['root'],displayFiles=value['files'],leftRunning=True)
except Exception as error:report['error']=repr(error)
finally:
 if client:client.close()
 if report.get('passed'):
  try:report['integrity']=verify_installed_resources(a.app,a.server)
  except Exception as error:report.update(passed=False,error=repr(error))
 (a.output/'results.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report));sys.exit(0 if report['passed'] else 1)
