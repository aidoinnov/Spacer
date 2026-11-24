#!/usr/bin/env python3
"""Disposable QA-app live FSEvents smoke; does not assert OS event batching shape."""
import argparse,json,pathlib,select,statistics,subprocess,sys,time

def main():
 p=argparse.ArgumentParser();p.add_argument('--bundle-id',required=True);p.add_argument('--output',required=True);a=p.parse_args()
 out=pathlib.Path(a.output).resolve();out.mkdir(parents=True,exist_ok=False)
 root=out/'fixture';root.mkdir();(root/'stable.bin').write_bytes(b'stable')
 for i in range(48):(root/f'branch-{i}').mkdir()
 child=subprocess.Popen([sys.executable,str(pathlib.Path(__file__).with_name('space_sniffer_mcp.py')),'--bundle-id',a.bundle_id],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
 counter=0;window={};latencies=[];observations=[]
 def rpc(method,params=None):
  nonlocal counter
  counter+=1;child.stdin.write((json.dumps({'jsonrpc':'2.0','id':counter,'method':method,'params':params or {}})+'\n').encode());child.stdin.flush()
  assert select.select([child.stdout],[],[],35)[0],'MCP timeout'
  result=json.loads(child.stdout.readline());assert result['id']==counter and 'error' not in result,result
  return result['result']
 def call(name,extra=None):
  start=time.monotonic();r=rpc('tools/call',{'name':name,'arguments':window|(extra or {})})
  assert not r.get('isError'),r
  if name=='app_status':latencies.append(time.monotonic()-start)
  return r['structuredContent']
 def wait_for(files,bytes):
  deadline=time.monotonic()+20
  while time.monotonic()<deadline:
   s=call('app_status');observations.append({k:s.get(k) for k in ['phase','snapshot_files','snapshot_logical_bytes','watch_active','projection_pending']})
   if s['phase']=='completed' and not s['projection_pending'] and s['snapshot_files']==files and s['snapshot_logical_bytes']==bytes:return s
   time.sleep(.025)
  raise AssertionError(('content did not converge',s))
 def wait_watching(enabled):
  deadline=time.monotonic()+10
  while time.monotonic()<deadline:
   s=call('app_status')
   if s['watch_active']==enabled:return
   time.sleep(.025)
  raise AssertionError(('monitor transition did not converge',s))
 try:
  rpc('initialize',{'protocolVersion':'2025-11-25','capabilities':{},'clientInfo':{'name':'refresh-burst-smoke','version':'1'}})
  s=call('app_status');window['window_id']=s['windows'][0]['window_id']
  call('scan_start',{'path':str(root),'watching':True});initial=wait_for(1,6)
  before=call('app_resources')
  for i in range(48):(root/f'branch-{i}'/'event.bin').write_bytes(bytes([i])*(i+1))
  burst=wait_for(49,6+sum(range(1,49)))
  stable=call('node_info',{'path':str(root/'stable.bin')});assert stable['node']['logical_bytes']==6,stable
  call('view_set',{'watching':False});wait_watching(False)
  call('scan_stop');call('view_set',{'watching':True});wait_watching(True)
  (root/'branch-47'/'replacement.bin').write_bytes(b'replacement')
  replacement=wait_for(50,6+sum(range(1,49))+11)
  after=call('app_resources')
  assert after['workers']['watch.events']['runs']>before['workers'].get('watch.events',{}).get('runs',0)
  # Replace the live root and confirm the old root's shared cache was released.
  empty=out/'empty';empty.mkdir();call('scan_start',{'path':str(empty),'watching':False});wait_for(0,0)
  released=call('app_resources');assert released['engine']['cached_roots']==1,released
  result={'rpc_requests':counter,'initial':initial,'burst':burst,'replacement':replacement,'resources_before':before,'resources_after':after,'resources_released':released,'status_seconds':{'samples':len(latencies),'median':statistics.median(latencies),'max':max(latencies)},'observations':observations,'limits':['FSEvents may coalesce scopes to a root; this does not prove index promotion in this run.','Stop between watch generations is exercised; cancellation during an active burst and stale callback injection are not proven.','Root cache release is observed; queue slot release is covered by unit tests, not direct live retained-byte instrumentation.']}
  (out/'results.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n');print(json.dumps({'rpc_requests':counter,'status_seconds':result['status_seconds']},indent=2))
 finally:
  child.stdin.close();child.wait(timeout=5);error=child.stderr.read();assert not error,error

if __name__=='__main__':main()
