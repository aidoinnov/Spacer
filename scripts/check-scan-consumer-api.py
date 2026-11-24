#!/usr/bin/env python3
"""Compile ordinary consumers: tickets are readable but only producers complete them."""
import argparse,json,subprocess,tempfile
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--module-path',type=Path,required=True);p.add_argument('--proof',type=Path);a=p.parse_args()
cases={
 'consumer_wait':('import SpaceSnifferScanEngine\nfunc read(_ t: DirectoryReadTicket<Int>) -> Int { t.wait() }\n',True),
 'consumer_finish':('import SpaceSnifferScanEngine\nfunc forge(_ t: DirectoryReadTicket<Int>) { t.finish(7) }\n',False),
 'consumer_construct':('import SpaceSnifferScanEngine\nfunc forge() -> DirectoryReadTicket<Int> { DirectoryReadTicket<Int>() }\n',False)
}
r={'scope':'Swift source API enforcement; not a binary/security boundary','cases':{}}
with tempfile.TemporaryDirectory(prefix='sniffer-consumer-api-',dir='/private/tmp') as work:
 for name,(source,allowed) in cases.items():
  f=Path(work)/(name+'.swift');f.write_text(source)
  result=subprocess.run(['swiftc','-swift-version','6','-typecheck','-I',str(a.module_path),str(f)],capture_output=True,text=True)
  inaccessible='inaccessible' in result.stderr or 'no accessible initializer' in result.stderr
  assert (result.returncode==0 if allowed else result.returncode!=0 and inaccessible),(name,result.stderr)
  r['cases'][name]={'expected_allowed':allowed,'exit_status':result.returncode,'diagnostic':result.stderr}
r['status']='passed'
if a.proof:a.proof.write_text(json.dumps(r,indent=2)+'\n')
print('PASS: ordinary consumers can wait; ticket construction/completion are compiler-rejected')
