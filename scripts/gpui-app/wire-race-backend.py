#!/usr/bin/env python3
"""QA proxy: deliberately deliver an old completion after a newer file publication."""
import json,os,pathlib,queue,subprocess,sys,threading
arguments=sys.argv[1:]
if '--scan' not in arguments:os.execv(os.environ['SNIFFER_TEST_NATIVE_BRIDGE'],[os.environ['SNIFFER_TEST_NATIVE_BRIDGE'],*arguments])
root=pathlib.Path(arguments[arguments.index('--scan')+1]).resolve()
assert root.parent.name.startswith('sniffer-wire-race-'), 'only an owned race fixture is allowed'
if '--watch' in arguments:arguments[arguments.index('--watch')+1]='false'
if '--wire' not in arguments:arguments+=['--wire','binary']
engine=subprocess.Popen([os.environ['SNIFFER_TEST_NATIVE_BRIDGE'],*arguments],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=sys.stderr,text=True,bufsize=1)
lock=threading.Lock()
def send(line):
 with lock:engine.stdin.write(line+'\n');engine.stdin.flush()
def forward():
 first=True
 try:
  for line in sys.stdin:
   if first and line.startswith('{'):
    request=json.loads(line)
    if request.get('operation')=='weights':
     path=pathlib.Path(os.environ['SNIFFER_TEST_RACE_REPORT']);report=json.loads(path.read_text());report['firstWeightsVersion']=request['version'];path.write_text(json.dumps(report,indent=2));first=False
   send(line.rstrip('\n'))
 except (BrokenPipeError,ValueError):pass
threading.Thread(target=forward,daemon=True).start()
held=None;released=False
try:
 for line in engine.stdout:
  event=json.loads(line)
  if event.get('type')=='complete' and not released:
   if held is None:
    held=line;(root/'new-revision-owned.txt').write_bytes(b'new immutable source');send('rescan');continue
   pathlib.Path(os.environ['SNIFFER_TEST_RACE_REPORT']).write_text(json.dumps({'forcedOverwrittenFile':True,'firstVersion':json.loads(held)['version'],'secondVersion':event['version']},indent=2))
   sys.stdout.write(held);released=True
  sys.stdout.write(line);sys.stdout.flush()
finally:
 if engine.poll() is None:
  try:send('quit');engine.wait(timeout=6)
  except (BrokenPipeError,subprocess.TimeoutExpired):engine.kill();engine.wait()
