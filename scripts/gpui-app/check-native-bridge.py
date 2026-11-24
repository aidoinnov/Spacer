#!/usr/bin/env python3
"""Owned-fixture integration check for the unchanged Mac engine behind GPUI."""
import argparse,json,pathlib,select,subprocess,tempfile,time
p=argparse.ArgumentParser();p.add_argument('bridge');p.add_argument('--output',required=True);a=p.parse_args();report={}
with tempfile.TemporaryDirectory(prefix='space-sniffer-bridge-test-') as temp:
 root=pathlib.Path(temp)/'data';root.mkdir();(root/'branch').mkdir();(root/'branch'/'한글.txt').write_bytes(b'a'*12345);(root/'sample.zip').write_bytes(b'b'*23456)
 output=pathlib.Path(temp)/'snapshot.json'
 child=subprocess.Popen([a.bridge,'--scan',str(root),'--output',str(output),'--watch','true'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
 def complete(timeout=10):
  deadline=time.monotonic()+timeout
  while time.monotonic()<deadline:
   if select.select([child.stdout],[],[],0.2)[0]:
    line=child.stdout.readline()
    if not line:raise RuntimeError('bridge exited before completion')
    event=json.loads(line)
    if event['type']=='failure':raise RuntimeError(event)
    if event['type']=='complete':return json.loads(output.read_text())
  raise TimeoutError('native completion')
 try:
  snapshot=complete();assert snapshot['files']==2 and snapshot['folders']==2
  assert snapshot['nodes'][0]['logical']==35801
  report['scan']={'passed':True,'files':snapshot['files'],'logical':snapshot['nodes'][0]['logical']}
  start=time.monotonic();(root/'changed.txt').write_bytes(b'c'*4567)
  snapshot=complete();assert snapshot['files']==3 and snapshot['nodes'][0]['logical']==40368
  report['watch']={'passed':True,'files':snapshot['files'],'detectionToResultMs':round((time.monotonic()-start)*1000,2)}
  child.stdin.write('quit\n');child.stdin.flush();child.wait(timeout=5);assert child.returncode==0
  report['shutdown']={'passed':True,'exitCode':child.returncode}
 finally:
  if child.poll() is None:child.kill();child.wait()
pathlib.Path(a.output).write_text(json.dumps(report,ensure_ascii=False,indent=2));print(json.dumps(report,ensure_ascii=False))
