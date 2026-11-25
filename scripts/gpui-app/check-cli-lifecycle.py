#!/usr/bin/env python3
"""Cancel only owned CLI sessions; verify their native children are reaped."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
from qa_process_metrics import create_probe, hidden_process_options, same_path, ExitWitness

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--binary',type=Path,required=True)
p.add_argument('--backend',type=Path,required=True)
p.add_argument('--output',type=Path,required=True)
a=p.parse_args();assert not a.output.exists();a.output.mkdir(parents=True)
probe=create_probe();report={'passed':False,'checks':[], 'scope':'Owned CLI cancellation and child release; not speed acceptance',
    'inputs':{str(v):hashlib.sha256(v.read_bytes()).hexdigest() for v in (a.binary,a.backend)}}
with tempfile.TemporaryDirectory(prefix='spacer-cli-lifecycle-') as temp:
    root=Path(temp)/'input';root.mkdir()
    for branch in range(4096):
        folder=root/str(branch);folder.mkdir()
        for index in range(8):(folder/str(index)).touch()
    for mode in (['parent-eof','sigint','success','invalid-filter'] if sys.platform=='darwin' else ['parent-eof','success','invalid-filter']):
        runtime=Path(temp)/('runtime-'+mode);runtime.mkdir()
        env={**os.environ,'SNIFFER_SCAN_BACKEND':str(a.backend),**{key:str(runtime)+os.sep for key in ('TMPDIR','TEMP','TMP')}}
        args=[str(a.binary),'--cli','--scan',str(root)]
        if mode=='parent-eof':args+=['--parent-stdio']
        if mode=='invalid-filter':args+=['--filter','logicalsize>bad']
        child=subprocess.Popen(args,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,
            env=env,**hidden_process_options())
        known={};witnesses={};row={'name':mode,'passed':False}
        try:
            deadline=time.monotonic()+30
            while time.monotonic()<deadline:
                assert child.poll() is None,'CLI exited before cancellation'
                for pid,(parent,path) in probe.processes().items():
                    if parent!=child.pid:continue
                    try:
                        path=probe.path(pid) if hasattr(probe,'path') else path
                        if same_path(path,str(a.backend)):
                            known[pid]=probe.info(pid)['creation_token']
                            witnesses[pid]=ExitWitness(probe,pid)
                    except ProcessLookupError:pass
                if known:break
                time.sleep(.01)
            assert known,'Native session was not observed'
            started=time.monotonic()
            if mode=='parent-eof':child.stdin.close();child.stdin=None
            elif mode=='sigint':child.send_signal(signal.SIGINT)
            stdout,stderr=child.communicate(timeout=90)
            (a.output/(mode+'.stdout')).write_bytes(stdout);(a.output/(mode+'.stderr')).write_bytes(stderr)
            expected=0 if mode=='success' else 1 if mode=='invalid-filter' else 130
            assert child.returncode==expected,(child.returncode,stderr)
            deadline=time.monotonic()+5
            while any(w.result is None for w in witnesses.values()) and time.monotonic()<deadline:time.sleep(.01)
            exits={pid:w.result for pid,w in witnesses.items()}
            assert all(v and v.get('statusPresent') and 'error' not in v for v in exits.values()),exits
            for witness in witnesses.values():witness.close()
            # A signalled Windows process object can remain queryable after
            # exit. Kernel exit observation, not OpenProcess success, is proof.
            remaining=[pid for pid in known if pid in probe.processes()]
            deadline=time.monotonic()+8
            while remaining and time.monotonic()<deadline:
                time.sleep(.05);remaining=[pid for pid in known if pid in probe.processes()]
            assert not remaining,remaining
            scratch=[str(p) for p in runtime.glob('sniffer-gpui-*')]
            assert not scratch,scratch
            row.update(passed=True,exit=child.returncode,nativeObserved=len(known),nativeRemaining=remaining,nativeScratchRemaining=scratch,kernelExits=exits,
                releaseMs=round((time.monotonic()-started)*1000,2))
        except Exception as error:row['error']=repr(error)
        finally:
            for witness in witnesses.values():witness.close()
            if child.poll() is None:child.kill();child.wait(timeout=8)
            for stream in (child.stdin,child.stdout,child.stderr):
                if stream:stream.close()
        report['checks'].append(row);print(json.dumps(row),flush=True)
report['fixtureRemoved']=not root.exists();report['passed']=all(r['passed'] for r in report['checks'])
(a.output/'results.json').write_text(json.dumps(report,indent=2)+'\n')
sys.exit(0 if report['passed'] else 1)
