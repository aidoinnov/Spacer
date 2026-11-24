#!/usr/bin/env python3
"""Native JSON/SSW1 differential oracle and paired publication measurements."""
import argparse,base64,json,pathlib,queue,subprocess,tempfile,threading,time,statistics
p=argparse.ArgumentParser();p.add_argument('bridge');p.add_argument('gpui');p.add_argument('--sns',type=pathlib.Path);p.add_argument('--pairs',type=int,default=5);p.add_argument('--output',type=pathlib.Path,required=True);a=p.parse_args()
class Engine:
 def __init__(self,mode,path,output,wire='json'):
  self.child=subprocess.Popen([a.bridge,mode,str(path),'--output',str(output),'--watch','false','--wire',wire],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True);self.events=queue.Queue()
  def read():
   for line in self.child.stdout:self.events.put(json.loads(line))
   self.events.put({'type':'eof'})
  threading.Thread(target=read,daemon=True).start()
 def event(self):
  event=self.events.get(timeout=120)
  if event['type'] in ('failure','eof','documentError'):raise RuntimeError(event)
  return event
 def send(self,value):self.child.stdin.write(value+'\n');self.child.stdin.flush()
 def complete(self):
  while True:
   event=self.event()
   if event['type']=='complete':self.version=event['version'];return
 def close(self):
  self.send('quit');self.child.wait(timeout=6);assert self.child.returncode==0
 def __enter__(self):return self
 def __exit__(self,*_):
  if self.child.poll() is None:
   try:self.close()
   finally:
    if self.child.poll() is None:self.child.kill();self.child.wait()
with tempfile.TemporaryDirectory(prefix='sniffer-wire-oracle-') as directory:
 root=pathlib.Path(directory);fixture=root/'input';fixture.mkdir()
 for name in ['한글🙂.txt','café.zip','café.bin']:(fixture/name).write_bytes(b'owned fixture')
 (fixture/'nested').mkdir();(fixture/'nested'/'file.txt').write_bytes(b'data')
 sns=root/'unicode.sns'
 with Engine('--scan',fixture,root/'scan.json') as engine:
  engine.complete();engine.send(json.dumps({'request':'save','version':engine.version,'operation':'sns','tags':{str(fixture/'nested'):15}}));parts=[]
  while True:
   event=engine.event()
   if event.get('request')!='save':continue
   if event['type']=='documentData':parts.append(base64.b64decode(event['data']))
   if event['type']=='documentEnd':sns.write_bytes(b''.join(parts));break
 checks=[];samples=[]
 for source,label,pairs in [(sns,'unicode_metadata_tags',1)]+([(a.sns,'scale',a.pairs)] if a.sns else []):
  for index in range(pairs):
   timings={}
   for wire in (['json','binary'] if index%2==0 else ['binary','json']):
    started=time.perf_counter()
    with Engine('--open',source,root/(wire+'.wire'),wire) as engine:engine.complete();timings[wire]=(time.perf_counter()-started)*1000
   report=root/'compare.json'
   subprocess.run([a.gpui,'--qa-wire-compare',str(root/'json.wire'),str(root/'binary.wire'),str(report)],check=True,timeout=120)
   result=json.loads(report.read_text());assert result['passed'],result
   result.update(case=label,pair=index,nativePublicationMs=timings);checks.append(result)
   if label=='scale':samples.append(timings)
 report={'passed':True,'checks':checks,'publicationMs':{key:{'median':statistics.median(sample[key] for sample in samples),'samples':[sample[key] for sample in samples]} for key in ['json','binary']} if samples else {},'notes':['Native decode + wire publication; GUI parse/paint measured separately','Alternating order; no claim of filesystem traversal speedup','ElapsedSeconds is intentionally excluded from semantic comparison']}
 a.output.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report))
