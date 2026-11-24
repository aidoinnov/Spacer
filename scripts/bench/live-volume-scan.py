#!/usr/bin/env python3
"""Read-only live-volume scan with frozen CLI identity and OS RSS samples."""
import argparse,hashlib,json,os,shutil,subprocess,time
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--root',required=True);p.add_argument('--binary',required=True);p.add_argument('--output',required=True);p.add_argument('--issues',action='store_true');a=p.parse_args()
out=Path(a.output).resolve();out.mkdir(parents=True,exist_ok=False)
binary=out/'frozen-cli';shutil.copyfile(a.binary,binary);binary.chmod(0o755)
def volume():
 s=os.statvfs(a.root);return {'total_bytes':s.f_frsize*s.f_blocks,'free_bytes':s.f_frsize*s.f_bfree,'available_bytes':s.f_frsize*s.f_bavail,'used_bytes':s.f_frsize*(s.f_blocks-s.f_bfree)}
manifest={'root':str(Path(a.root).resolve()),'binary_sha256':hashlib.sha256(binary.read_bytes()).hexdigest(),'started_at':time.time(),'volume_before':volume(),'scope':'live pathname sum, not an atomic filesystem snapshot; hardlink aliases count separately; symlinks excluded; concurrent host work permitted, no fair speed comparison claim'}
(out/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
stdout=(out/'summary.stdout').open('w');stderr=(out/'time.stderr').open('w');start=time.monotonic()
command=['/usr/bin/time','-lp',str(binary),'--cli','--scan',a.root,'--output',str(out/'develop.sns')]
if a.issues: command.append('--issues')
manifest['command']=command
process=subprocess.Popen(command,stdout=stdout,stderr=stderr)
samples=[]
while process.poll() is None:
 # time's child is the CLI; inspect only this explicitly owned process tree.
 children=subprocess.run(['/usr/bin/pgrep','-P',str(process.pid)],capture_output=True,text=True).stdout.split()
 for pid in children:
  if pid.isdecimal():
   result=subprocess.run(['/bin/ps','-p',pid,'-o','rss=','-o','%cpu=','-o','etime='],capture_output=True,text=True).stdout.strip()
   samples.append({'elapsed_seconds':time.monotonic()-start,'pid':int(pid),'ps_rss_kib_cpu_percent_elapsed':result})
 (out/'resources.json').write_text(json.dumps(samples,indent=2)+'\n');time.sleep(2)
stdout.close();stderr.close();manifest.update(exit_code=process.returncode,elapsed_seconds=time.monotonic()-start,finished_at=time.time(),volume_after=volume())
try:manifest['summary']=json.loads((out/'summary.stdout').read_text())
except (ValueError,OSError):manifest['summary']=None
snapshot=out/'develop.sns'
if snapshot.exists():
 digest=hashlib.sha256()
 with snapshot.open('rb') as f:
  while block:=f.read(1<<20):digest.update(block)
 manifest.update(snapshot_bytes=snapshot.stat().st_size,snapshot_sha256=digest.hexdigest())
(out/'result.json').write_text(json.dumps(manifest,indent=2)+'\n');print(json.dumps(manifest))
