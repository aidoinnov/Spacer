#!/usr/bin/env python3
"""Owned-fixture ARM/Intel CLI and SNS/TXT interoperability; not a latency test."""
import argparse,hashlib,json,shutil,subprocess,tempfile
from pathlib import Path

def main():
 p=argparse.ArgumentParser();p.add_argument('--arm-binary',type=Path,required=True);p.add_argument('--intel-binary',type=Path,required=True);p.add_argument('--proof',type=Path,required=True);a=p.parse_args()
 assert not a.proof.exists(),'refusing proof overwrite'
 a.proof.mkdir(parents=True)
 binaries={'arm64':a.arm_binary,'x86_64':a.intel_binary}
 r={'status':'running','scope':'functional Mac ARM/Intel CLI; not latency or native Windows validation','binaries':{k:{'path':str(v),'sha256':hashlib.sha256(v.read_bytes()).hexdigest()} for k,v in binaries.items()},'architectures':{}}
 root=Path(tempfile.mkdtemp(prefix='sniffer-cli-contract-',dir='/private/tmp'))
 def run(arch,args):
  proc=subprocess.run(['/usr/bin/arch','-'+arch,str(binaries[arch]),'--cli',*args],capture_output=True,text=True,timeout=120)
  if proc.returncode:raise RuntimeError(f'{arch} exit {proc.returncode}: {proc.stderr}')
  return json.loads(proc.stdout)
 try:
  logical=allocated=0
  for branch in range(100):
   folder=root/f'b{branch:03}';folder.mkdir()
   for index in range(96):
    path=folder/f'f{index:03}';path.write_bytes(b'x'*(index+1));s=path.stat();logical+=s.st_size;allocated+=s.st_blocks*512
  expected=dict(files=9600,folders=101,logicalBytes=logical,allocatedBytes=allocated,issues=0);r['oracle']=expected
  for arch in binaries:
   result=run(arch,['--scan',str(root),'--output',str(a.proof/(arch+'.txt'))]);assert all(result[k]==v for k,v in expected.items()),(arch,result)
   r['architectures'][arch]={'scan':result}
  assert (a.proof/'arm64.txt').read_bytes()==(a.proof/'x86_64.txt').read_bytes()
  saved=run('arm64',['--scan',str(root),'--output',str(a.proof/'arm64.sns')]);assert all(saved[k]==v for k,v in expected.items())
  for arch in binaries:
   loaded=run(arch,['--load',str(a.proof/'arm64.sns'),'--output',str(a.proof/(arch+'-loaded.txt'))]);assert all(loaded[k]==v for k,v in expected.items())
   r['architectures'][arch]['loaded']=loaded
  assert (a.proof/'arm64-loaded.txt').read_bytes()==(a.proof/'x86_64-loaded.txt').read_bytes()
  r.update(status='passed',txt_identical=True,cross_arch_sns=True)
 except BaseException as error:
  r.update(status='failed',error=repr(error));raise
 finally:
  shutil.rmtree(root);r['cleanup']={'path':str(root),'removed':not root.exists()};(a.proof/'cross-arch.json').write_text(json.dumps(r,indent=2)+'\n')
 print('PASS: ARM/Intel oracle, TXT bytes and cross-architecture SNS load')
if __name__=='__main__':main()
