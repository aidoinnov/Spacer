#!/usr/bin/env python3
"""Independent official Python SDK interoperability on an owned hidden Mac QA app.

Run with uv run --no-project --with mcp==2.3.0 python scripts/mcp/check_sdk.py ...
The SDK is a test dependency only; the shipped bridge remains dependency-free.
"""
import argparse
import asyncio
import importlib.metadata
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

from mcp import Client, StdioServerParameters
from space_sniffer_mcp import Bridge, TOOLS


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--gui',type=Path,required=True);p.add_argument('--backend',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    a=p.parse_args();assert not a.output.exists();a.output.mkdir(parents=True)
    report={'passed':False,'sdkVersion':importlib.metadata.version('mcp'),'connections':[]}
    bridge=Bridge();child=None
    with tempfile.TemporaryDirectory(prefix='spacer-sdk-owned-') as directory:
        work=Path(directory);fixture=work/'fixture';fixture.mkdir()
        (fixture/'한글.txt').write_bytes(b'owned sdk fixture')
        native=work/a.backend.name;shutil.copy2(a.backend,native)
        with (a.output/'app.log').open('w') as log:
            try:
                env={**os.environ,'SNIFFER_SCAN_BACKEND':str(native)}
                child=subprocess.Popen([str(a.gui.resolve()),'--qa-background','--scan',str(fixture)],env=env,stdout=log,stderr=log)
                report['ownedPid']=child.pid
                deadline=time.monotonic()+90
                while time.monotonic()<deadline:
                    assert child.poll() is None
                    if any(d['pid']==child.pid for d in bridge.instances()):
                        state=bridge.call_app('app_status',{'instance_id':child.pid})['windows'][0]
                        if state['phase']=='completed' and not state['projection_pending']:break
                    time.sleep(.1)
                else:raise TimeoutError('Owned QA did not finish scanning')
                assert state['files']==1 and not state['window_visible'],state
                async def check():
                    for mode,version in [('auto','2026-07-28'),('legacy','2025-11-25')]:
                        params=StdioServerParameters(command=sys.executable,
                            args=[str(Path(__file__).with_name('space_sniffer_mcp.py'))],
                            env={**os.environ,'PYTHONIOENCODING':'ascii'})
                        async with Client(params,mode=mode,read_timeout_seconds=30) as client:
                            assert client.protocol_version==version,client.protocol_version
                            catalog=await client.list_tools()
                            assert {t.name for t in catalog.tools}=={t['name'] for t in TOOLS}
                            status=await client.call_tool('app_status',{'instance_id':child.pid})
                            assert not status.is_error and status.structured_content['windows'][0]['files']==1
                            details=await client.call_tool('node_info',{'instance_id':child.pid,'path':str(Path(state['root'])/'한글.txt')})
                            assert not details.is_error and details.structured_content['node']['name']=='한글.txt'
                            image=await client.call_tool('view_capture',{'instance_id':child.pid})
                            assert not image.is_error and any(block.type=='image' for block in image.content)
                            bad=await client.call_tool('node_info',{'instance_id':child.pid,'path':str(fixture/'missing')})
                            assert bad.is_error
                            report['connections'].append({'mode':mode,'protocolVersion':version,'tools':len(catalog.tools),
                                'unicodeStructuredContent':True,'imageBlock':True,'toolErrorEnvelope':True})
                asyncio.run(check());report['passed']=True
            except BaseException as error:report['error']=repr(error)
            finally:
                if child and child.poll() is None:
                    try:bridge.call_app('window_close',{'instance_id':child.pid})
                    except Exception:pass
                    try:child.wait(timeout=8)
                    except subprocess.TimeoutExpired:child.terminate();child.wait(timeout=8)
                report['guiExitCode']=child.returncode if child else None
                report['passed'] &= report['guiExitCode']==0
                (a.output/'results.json').write_text(json.dumps(report,indent=2)+'\n')
    report['fixtureRemoved']=not work.exists()
    (a.output/'results.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))
    raise SystemExit(0 if report['passed'] else 1)


if __name__=='__main__':main()
