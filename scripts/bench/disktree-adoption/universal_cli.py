#!/usr/bin/env python3
"""Exercise both universal slices and SNS/TXT interoperability on owned images."""
import argparse,hashlib,json,subprocess
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--binary',type=Path,required=True);p.add_argument('--fixture',type=Path,required=True);p.add_argument('--proof',type=Path,required=True);a=p.parse_args()
r=json.loads(a.fixture.read_text());root=Path(r['root']);assert not r['removed'] and str(root).startswith('/private/tmp/sniffer-scope-native-')
a.proof.mkdir(parents=True,exist_ok=True)
result={'binary':str(a.binary),'sha256':hashlib.sha256(a.binary.read_bytes()).hexdigest(),'architectures':{},'status':'running'}
def run(architecture,args):
 proc=subprocess.run(['/usr/bin/arch','-'+architecture,str(a.binary),'--cli',*args],capture_output=True,text=True,timeout=120)
 assert proc.returncode==0,(architecture,proc.stderr)
 return json.loads(proc.stdout)
for architecture in ['arm64','x86_64']:
 selected=run(architecture,['--scan',str(root),'--output',str(a.proof/(architecture+'-selected.txt'))])
 included=run(architecture,['--scan',str(root),'--include-mounted-volumes','--output',str(a.proof/(architecture+'-all.txt'))])
 assert selected['files']==100 and selected['folders']==5 and selected['logicalBytes']==300 and selected['excluded_boundary_count']==1
 assert included['files']==6100 and included['folders']==37 and included['logicalBytes']==30300 and included['excluded_boundary_count']==0
 result['architectures'][architecture]={'selected':selected,'all':included}
for mode in ['selected','all']:
 assert (a.proof/('arm64-'+mode+'.txt')).read_bytes()==(a.proof/('x86_64-'+mode+'.txt')).read_bytes()
 for field in ['files','folders','logicalBytes','allocatedBytes','issues']:
  assert result['architectures']['arm64'][mode][field]==result['architectures']['x86_64'][mode][field]
sns=a.proof/'arm64-saved.sns'
saved=run('arm64',['--scan',str(root),'--output',str(sns)])
for architecture in ['arm64','x86_64']:
 loaded=run(architecture,['--load',str(sns),'--output',str(a.proof/(architecture+'-loaded.txt'))])
 for field in ['files','folders','logicalBytes','allocatedBytes','issues']:assert loaded[field]==saved[field]
 result['architectures'][architecture]['loaded']=loaded
assert (a.proof/'arm64-loaded.txt').read_bytes()==(a.proof/'x86_64-loaded.txt').read_bytes()
result.update(status='passed',txt_identical=True,cross_arch_sns=True)
(a.proof/'universal-cli.json').write_text(json.dumps(result,indent=2)+'\n');print('Universal CLI/SNS/TXT passed')
