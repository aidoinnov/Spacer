#!/usr/bin/env python3
"""Owned-fixture acceptance for native SNS/filter/report RPC, never scans user data."""
import os,math,statistics,argparse,base64,json,pathlib,queue,struct,subprocess,tempfile,threading,time
p=argparse.ArgumentParser();p.add_argument('bridge');p.add_argument('--portable');p.add_argument('--output',required=True);a=p.parse_args()
report={'checks':[]}; maximum_line=0
class Engine:
 def __init__(self,program,mode,source,output):
  self.output=output;self.events=queue.Queue();self.child=subprocess.Popen([program,mode,str(source),'--output',str(output),'--watch','false'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
  def read():
   global maximum_line
   for line in self.child.stdout:
    maximum_line=max(maximum_line,len(line.encode()));self.events.put(json.loads(line))
   self.events.put({'type':'eof'})
  threading.Thread(target=read,daemon=True).start()
 def send(self,line):self.child.stdin.write(line+'\n');self.child.stdin.flush()
 def event(self):
  e=self.events.get(timeout=30)
  if e['type'] in ('failure','eof'):raise RuntimeError(e)
  return e
 def complete(self):
  while True:
   e=self.event()
   if e['type']=='complete':
    self.version=e['version'];source=json.loads(self.output.read_text())
    for node in source['nodes']:
     if not node.get('path'):node['path']=source['nodes'][node['parent']]['path'].rstrip('/\\')+('\\' if len(source['root'])>1 and source['root'][1]==':' else '/')+node['name']
    return source
 def request(self,op,**kw):
  start=time.perf_counter();self.send(json.dumps(dict(request='test',operation=op,version=self.version,**kw)));parts=[]
  while True:
   e=self.event()
   if e.get('request')!='test':continue
   if e['type']=='documentError':raise RuntimeError(e['message'])
   if e['type']=='documentData':parts.append(base64.b64decode(e['data'],validate=True))
   if e['type']=='documentEnd':
    result=b''.join(parts);assert len(result)==e['bytes'];return result,(time.perf_counter()-start)*1000
 def weights(self,text='',**kw):
  data,ms=self.request('weights',filter=text,**kw);return list(struct.unpack('<'+'Q'*(len(data)//8),data)),ms
 def close(self):
  self.send('quit');self.child.wait(timeout=6);assert self.child.returncode==0
 def __enter__(self):return self
 def __exit__(self,*args):
  if self.child.poll() is None:
   try:self.close()
   except Exception:self.child.kill();self.child.wait()
def check(name,**values):report['checks'].append(dict(name=name,passed=True,**values))
with tempfile.TemporaryDirectory(prefix='sniffer-document-') as tmp:
 t=pathlib.Path(tmp);root=t/'data';(root/'alpha').mkdir(parents=True);(root/'beta').mkdir()
 (root/'alpha'/'한글.zip').write_bytes(b'a'*4096);(root/'beta'/'second.txt').write_bytes(b'b'*1024);(root/'.hidden.zip').write_bytes(b'c'*512)
 if os.name=='nt':
  import ctypes
  assert ctypes.windll.kernel32.SetFileAttributesW(str(root/'.hidden.zip'),2)
 with Engine(a.bridge,'--scan',root,t/'scan.json') as native:
  source=native.complete();nodes=source['nodes'];ids={n['name']:n['id'] for n in nodes};tags={str(root/'alpha'):4}
  weights,ms=native.weights('logicalsize>4096b',logical=True);assert weights[ids['한글.zip']]==4096 and weights[ids['second.txt']]==0
  check('inclusive_native_size_bound',latencyMs=round(ms,3))
  weights,ms=native.weights(':green',tags=tags,logical=True);assert weights[0]==4096 and weights[ids['한글.zip']]==4096
  check('ancestor_tag_bitmask_filter',latencyMs=round(ms,3))
  weights,_=native.weights('\\alpha;\\beta',logical=True);assert weights[0]==5120
  check('folder_masks_use_OR')
  weights,_=native.weights('*.zip',logical=True,hidden=False);assert weights[0]==4096
  check('native_hidden_attribute_filter')
  weights,_=native.weights('modified<1d',logical=True);assert weights[0]==5632
  check('native_date_metadata_filter')
  sns,ms=native.request('sns',tags=tags);(t/'saved.sns').write_bytes(sns);assert sns[:1]!=b'{'
  check('binary_sns_stream',bytes=len(sns),latencyMs=round(ms,3))
  txt,_=native.request('report',filter=':green',tags=tags,logical=True)
  assert txt.decode()==str(root/'alpha'/'한글.zip')+'\n';check('native_simple_report_paths_only')
  # Invalid filters must return an error while preserving a usable document.
  try:native.weights('logicalsize>bad');raise AssertionError('invalid filter accepted')
  except RuntimeError:pass
  assert native.weights('',logical=True)[0][0]==5632;check('invalid_filter_recovery')
  start=time.perf_counter();(root/'alpha'/'new.txt').write_bytes(b'n'*333);native.send('focus '+str(root/'alpha'));updated=native.complete()
  assert updated['root']==str(root) and updated['files']==4 and updated['nodes'][0]['logical']==5965
  assert any(n['name']=='second.txt' for n in updated['nodes']);check('focused_rescan_preserves_siblings',latencyMs=round((time.perf_counter()-start)*1000,3))
 for program,label in [(a.bridge,'mac')]+([(a.portable,'portable')] if a.portable else []):
  with Engine(program,'--open',t/'saved.sns',t/(label+'.json')) as imported:
   restored=imported.complete();assert restored['tags']==tags;assert restored['nodes'][0]['logical']==5632
   assert imported.weights(':green',tags=tags,logical=True)[0][0]==4096
   assert imported.request('report',filter=':green',tags=tags,logical=True)[0]==txt
   check(label+'_sns_reopen_filter_report',nodes=len(restored['nodes']))
  (t/'multi.sns').write_bytes(sns+sns)
  with Engine(program,'--open',t/'multi.sns',t/(label+'multi.json')) as imported:
   event=imported.event();assert event['type']=='importRoots' and len(event['roots'])==2
   assert not imported.output.exists();imported.send('select 1');assert imported.complete()['root']==str(root)
   check(label+'_explicit_multi_root_selection')
with tempfile.TemporaryDirectory(prefix='sniffer-chunks-') as tmp:
 t=pathlib.Path(tmp);root=t/'data';root.mkdir()
 for i in range(9000):(root/f'{i:05d}.txt').touch()
 with Engine(a.bridge,'--scan',root,t/'bulk.json') as native:
  source=native.complete();weights,ms=native.weights();assert len(weights)==9001
  compact=native.output.stat().st_size;expanded=len(json.dumps(source,separators=(',',':'),ensure_ascii=False).encode())
  check('compact_parent_name_paths',wireBytes=compact,fullPathBytes=expanded,reductionPercent=round((1-compact/expanded)*100,2))
  text,report_ms=native.request('report');assert len(text)>65536 and len(text.splitlines())==9000
  check('bounded_multi_chunk_response',nodes=len(weights),filterMs=round(ms,3),reportBytes=len(text),reportMs=round(report_ms,3))
  timings={'filter':[],'report':[]}
  for i in range(33):
   for label,operation in [('filter','weights'),('report','report')]:
    _,latency=native.request(operation)
    if i>=3:timings[label].append(latency)
  report['benchmark']={label:{'samples':len(values),'p50Ms':round(statistics.median(values),3),'p95Ms':round(sorted(values)[math.ceil(0.95*len(values))-1],3)} for label,values in timings.items()}
  report['benchmark']['scope']='9001 nodes / 9000 zero-byte files, owned fixture; native document RPC; 3 warmups; no traversal speed claim'
report['maxJSONLBytes']=maximum_line;assert maximum_line<90_000
report['passed']=True;pathlib.Path(a.output).write_text(json.dumps(report,ensure_ascii=False,indent=2));print(json.dumps(report,ensure_ascii=False))
