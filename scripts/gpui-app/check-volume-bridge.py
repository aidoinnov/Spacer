#!/usr/bin/env python3
"""Use a provisioned, owned nested-volume fixture; never touch user mounts."""
import argparse,json,pathlib,queue,subprocess,tempfile,threading,time
p=argparse.ArgumentParser();p.add_argument('bridge');p.add_argument('--fixture',required=True,type=pathlib.Path);p.add_argument('--output',required=True,type=pathlib.Path);a=p.parse_args()
fixture=json.loads(a.fixture.read_text());assert not fixture['removed'];root=fixture['root'];assert root.startswith('/private/tmp/sniffer-scope-native-')
results=[]
for mode,expected in [('selectedVolume',fixture['expected']['selected']),('allVolumes',fixture['expected']['all']),('selectedVolume',fixture['expected']['selected'])]:
 with tempfile.TemporaryDirectory(prefix='sniffer-volume-wire-') as temp:
  output=pathlib.Path(temp)/'snapshot.json';events=queue.Queue();started=time.monotonic()
  child=subprocess.Popen([a.bridge,'--scan',root,'--output',str(output),'--watch','false','--volumes',mode],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
  def receive():
   for line in child.stdout:events.put(json.loads(line))
  reader=threading.Thread(target=receive,daemon=True);reader.start()
  try:
   while True:
    event=events.get(timeout=30)
    if event['type']=='failure':raise RuntimeError(event)
    if event['type']=='complete':break
   data=json.loads(output.read_text());assert data['volumeTraversal']==mode
   assert (data['files'],data['folders'],data['nodes'][0]['logical'],data['excluded'])==(expected['files'],expected['folders'],expected['logical'],expected['excluded'])
   results.append(dict(mode=mode,files=data['files'],folders=data['folders'],logical=data['nodes'][0]['logical'],excluded=data['excluded'],elapsedMs=round((time.monotonic()-started)*1000,3),passed=True))
   child.stdin.write('quit\n');child.stdin.flush();child.wait(timeout=6);assert child.returncode==0
  finally:
   if child.poll() is None:child.kill();child.wait()
report=dict(passed=True,checks=results);a.output.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report))
