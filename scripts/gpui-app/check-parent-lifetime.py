#!/usr/bin/env python3
"""Kill only a launcher we create; verify its owned native child and temp files end."""
import argparse,json,os,pathlib,shutil,signal,subprocess,sys,time
p=argparse.ArgumentParser();p.add_argument('bridge');p.add_argument('--sns',required=True);p.add_argument('--output',required=True,type=pathlib.Path);p.add_argument('--expect-legacy-failure',action='store_true');a=p.parse_args()
launcher=r'''
import json,os,pathlib,subprocess,sys,tempfile,time
root=pathlib.Path(tempfile.mkdtemp(prefix=f'sniffer-gpui-{os.getpid()}-lifetime-'));(root/'owned-marker').write_text('owned')
child=subprocess.Popen([sys.argv[1],'--open',sys.argv[2],'--output',str(root/'snapshot.ssw'),'--wire','binary','--parent',str(os.getpid())],stdin=subprocess.PIPE,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
print(json.dumps({'child':child.pid,'directory':str(root)}),flush=True);time.sleep(.5);os._exit(0)
'''
parent=subprocess.Popen([sys.executable,'-c',launcher,a.bridge,a.sns],stdout=subprocess.PIPE,text=True)
info=json.loads(parent.stdout.readline());parent.wait(timeout=3);started=time.monotonic()
def alive():
 if os.name=='nt':
  import ctypes
  kernel=ctypes.WinDLL('kernel32',use_last_error=True);kernel.OpenProcess.restype=ctypes.c_void_p;kernel.CloseHandle.argtypes=[ctypes.c_void_p]
  handle=kernel.OpenProcess(0x1000,False,info['child'])
  if not handle:return False
  kernel.CloseHandle(handle);return True
 result=subprocess.run(['ps','-p',str(info['child']),'-o','stat='],capture_output=True,text=True)
 return bool(result.stdout.strip()) and not result.stdout.lstrip().startswith('Z')
while alive() and time.monotonic()-started<1.5:time.sleep(.02)
terminated=not alive();removed=not pathlib.Path(info['directory']).exists()
report={'passed':terminated and removed,'terminatedAfterOwnerExit':terminated,'ownedDirectoryRemoved':removed,'observedMs':round((time.monotonic()-started)*1000,3),'deadlineMs':1500,'bridge':a.bridge}
a.output.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report))
if not terminated:
 if os.name=='nt':subprocess.run(['taskkill','/PID',str(info['child']),'/F'],check=False,capture_output=True)
 else:os.kill(info['child'],signal.SIGKILL)
root=pathlib.Path(info['directory']);assert root.name.startswith('sniffer-gpui-') and '-lifetime-' in root.name
if root.exists():shutil.rmtree(root)
assert (not report['passed']) if a.expect_legacy_failure else report['passed']
