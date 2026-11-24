#!/usr/bin/env python3
"""Bounded, research-only getattrlistbulk oracle and alternating profiles."""
import argparse,ctypes,hashlib,json,os,shutil,stat,statistics,subprocess,tempfile,time
from pathlib import Path

p=argparse.ArgumentParser();p.add_argument('stage',choices=['prepare','profile']);p.add_argument('--output',type=Path,required=True);a=p.parse_args();a.output.mkdir(parents=True,exist_ok=True)
binary=Path('dist/r14-bulk-metadata').resolve();manifest=a.output/'bulk-fixture.json'
def run(mode,path,iterations=25):
 result=subprocess.run([str(binary),mode,str(path),str(iterations)],capture_output=True,text=True)
 parsed=json.loads(result.stdout) if result.stdout.strip() else None
 return {'exit_code':result.returncode,'result':parsed,'stderr':result.stderr}
if a.stage=='prepare':
 assert not manifest.exists()
 capacity=os.statvfs('/private/tmp');assert capacity.f_bavail*capacity.f_frsize>32*1024*1024,'fixture requires 32MiB free'
 fixture=Path(tempfile.mkdtemp(prefix='mac-space-sniffer-r14-bulk-',dir='/private/tmp'))
 for i in range(2048):(fixture/f'file-{i:04}.bin').write_bytes(bytes([i%256])*[0,1,513,1025,4097][i%5])
 for name in ['한글-😀-cafe\u0301.bin','.'+'hidden.bin','long-'+('n'*220)+'.bin']:(fixture/name).write_bytes(b'fixture')
 (fixture/'readonly.bin').write_bytes(b'r');os.chmod(fixture/'readonly.bin',0o444)
 for i in range(4):(fixture/f'directory-{i}').mkdir()
 os.link(fixture/'file-0001.bin',fixture/'hardlink.bin')
 for name,target in [('link','file-0001.bin'),('broken-link','absent'),('cycle','.')]:os.symlink(target,fixture/name)
 os.mkfifo(fixture/'fifo')
 with (fixture/'sparse.bin').open('wb') as f:f.seek(8*1024*1024);f.write(b'x')
 notes=[]
 try:os.chflags(fixture/'.hidden.bin',stat.UF_HIDDEN)
 except OSError as e:notes.append('hidden flag unavailable: '+str(e))
 (fixture/'resource-fork.bin').write_bytes(b'data')
 libc=ctypes.CDLL(None,use_errno=True);setxattr=libc.setxattr
 setxattr.argtypes=[ctypes.c_char_p,ctypes.c_char_p,ctypes.c_void_p,ctypes.c_size_t,ctypes.c_uint32,ctypes.c_int];setxattr.restype=ctypes.c_int
 resource=ctypes.create_string_buffer(b'r'*4097)
 if setxattr(os.fsencode(fixture/'resource-fork.bin'),b'com.apple.ResourceFork',resource,4097,0,0)!=0:notes.append('resource fork unavailable errno='+str(ctypes.get_errno()))
 check=run('check',fixture);volumes=run('check','/Volumes')
 report={'fixture':str(fixture),'scope':'one flat owned APFS directory, 2048 regular baseline entries plus unicode/long/hidden/readonly/resource fork/sparse/links/FIFO/4 subdirectories; no recursive scan. /Volumes checks existing mountpoint entries read-only. Background user GUI scan and other agents remain active; not a fair whole-scan speed claim.',
  'created_entries':len(list(fixture.iterdir())),'notes':notes,'oracle':check,'mountpoint_oracle':volumes,'binary_sha256':hashlib.sha256(binary.read_bytes()).hexdigest(),'script_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
 manifest.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print(json.dumps(report,ensure_ascii=False))
 if check['exit_code']!=0:raise SystemExit(1)
else:
 original=json.loads(manifest.read_text());fixture=Path(original['fixture']);assert original['oracle']['exit_code']==0
 assert not (a.output/'bulk-profile.json').exists()
 assert hashlib.sha256(binary.read_bytes()).hexdigest()==original['binary_sha256']
 rows=[]
 for pair in range(5):
  for mode in (['baseline','bulk'] if pair%2==0 else ['bulk','baseline']):
   result=run(mode,fixture);assert result['exit_code']==0,result
   row=result['result'];row['pair']=pair;rows.append(row)
  assert rows[-2]['checksum']==rows[-1]['checksum'],rows[-2:]
 report={'scope':original['scope'],'rows':rows,'pairs':5,'iterations_per_process':25,'binary_sha256':original['binary_sha256'],'fixture_manifest_sha256':hashlib.sha256(manifest.read_bytes()).hexdigest(),
  'summary':{m:{'seconds_median':statistics.median(r['seconds'] for r in rows if r['mode']==m),'seconds_range':[min(r['seconds'] for r in rows if r['mode']==m),max(r['seconds'] for r in rows if r['mode']==m)],'max_rss_bytes_median':statistics.median(r['max_rss_bytes'] for r in rows if r['mode']==m)} for m in ['baseline','bulk']}}
 (a.output/'bulk-profile.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report['summary']))
