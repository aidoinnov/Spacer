#!/usr/bin/env python3
"""Temporarily stop one identified app process; always resume, with a watchdog.
No app is quit/restarted. A changed process identity is never signalled.
"""
import argparse,json,os,signal,subprocess,sys,time,platform
from pathlib import Path

def identity(pid):
 p=subprocess.run(['ps','-p',str(pid),'-o','lstart=,comm='],capture_output=True,text=True)
 return p.stdout.strip() if p.returncode==0 else None

def state(pid):
 return subprocess.run(['ps','-p',str(pid),'-o','stat='],capture_output=True,text=True).stdout.strip()

def save(path,value):
 tmp=path.with_name(path.name+f'.{os.getpid()}.tmp');tmp.write_text(json.dumps(value,indent=2)+'\n');tmp.replace(path)

def main():
 p=argparse.ArgumentParser();p.add_argument('--pid',type=int,required=True);p.add_argument('--lease',type=Path,required=True);p.add_argument('--timeout',type=int,default=600);p.add_argument('--watchdog',action='store_true');p.add_argument('--target-kind',choices=['sniffer','docker-vm'],default='sniffer');p.add_argument('--parent',type=int);p.add_argument('command',nargs=argparse.REMAINDER);a=p.parse_args()
 if a.watchdog:
  deadline=time.monotonic()+a.timeout
  while True:
   data=json.loads(a.lease.read_text())
   if data['status'] in ['resumed','failed_before_pause']:return 0
   try:os.kill(a.parent,0);alive=True
   except ProcessLookupError:alive=False
   if not alive or time.monotonic()>=deadline:
    if identity(a.pid)==data['identity']:os.kill(a.pid,signal.SIGCONT)
    data.update(status='watchdog_resumed',watchdog_resumed_at=time.time());save(a.lease,data);return 0
   time.sleep(1)
 assert not a.lease.exists(),'refusing lease overwrite'
 before=identity(a.pid)
 assert before,'target no longer exists'
 if a.target_kind=='docker-vm':
  assert platform.system()=='Darwin','Docker VM pause is a macOS host adapter'
  executable=subprocess.check_output(['ps','-p',str(a.pid),'-o','comm='],text=True).strip()
  expected='/System/Library/Frameworks/Virtualization.framework/Versions/A/XPCServices/com.apple.Virtualization.VirtualMachine.xpc/Contents/MacOS/com.apple.Virtualization.VirtualMachine'
  assert executable==expected,'not the identified Apple virtualization process'
  assert int(subprocess.check_output(['ps','-p',str(a.pid),'-o','uid='],text=True))==os.getuid(),'not owned by current user'
  opened=subprocess.check_output(['lsof','-p',str(a.pid),'-Fn'],text=True,timeout=10).splitlines()
  disk=Path.home()/'Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw'
  assert 'n'+str(disk) in opened,'VM is not using the identified Docker disk'
 else:
  assert 'MacSpaceSniffer' in before,'target is not the identified app'
 assert 'T' not in state(a.pid),'already stopped by another actor'
 command=a.command[1:] if a.command[:1]==['--'] else a.command
 assert command
 data={'target_kind':a.target_kind,'pid':a.pid,'identity':before,'status':'preparing','command':command,'timeout_seconds':a.timeout,'started':time.time()};save(a.lease,data)
 watcher=subprocess.Popen([sys.executable,__file__,'--pid',str(a.pid),'--lease',str(a.lease),'--timeout',str(a.timeout),'--watchdog','--parent',str(os.getpid())],start_new_session=True)
 child=None;paused=False
 try:
  os.kill(a.pid,signal.SIGSTOP);paused=True
  for _ in range(30):
   if 'T' in state(a.pid):break
   time.sleep(.1)
  assert 'T' in state(a.pid),'process did not stop'
  data.update(status='paused',paused_at=time.time());save(a.lease,data)
  print('Paused identified app; watchdog active',flush=True)
  child=subprocess.Popen(command);rc=child.wait()
  # If a watchdog or user resumed it early, this is not a quiet collection.
  latest=json.loads(a.lease.read_text());data['quiet_condition_held']=latest['status']=='paused' and 'T' in state(a.pid)
  data['child_exit_status']=rc
  return rc if data['quiet_condition_held'] else 2
 finally:
  if paused and identity(a.pid)==before:os.kill(a.pid,signal.SIGCONT)
  data.update(status='resumed' if paused else 'failed_before_pause',resumed_at=time.time(),resumed_state=state(a.pid));save(a.lease,data)
  if child and child.poll() is None:
   child.send_signal(signal.SIGINT)
  # Do not wait on a sleeping watchdog; it notices the final lease next tick.
  print('Resumed identified app',flush=True)
if __name__=='__main__':raise SystemExit(main())
