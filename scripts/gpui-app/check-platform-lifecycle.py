#!/usr/bin/env python3
"""Own hidden GUI large import/replacement/close with independent OS exit witness."""
import argparse, json, pathlib, subprocess, sys, time, os, hashlib
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]/'mcp'))
from space_sniffer_mcp import Bridge
from qa_process_metrics import create_probe, owned_snapshot, same_path, ExitWitness, diagnose_exit_timeout


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--gui',type=pathlib.Path,required=True)
    p.add_argument('--backend',type=pathlib.Path,required=True)
    p.add_argument('--large-sns',type=pathlib.Path,required=True)
    p.add_argument('--small-sns',type=pathlib.Path,required=True)
    p.add_argument('--rounds',type=int,default=5)
    p.add_argument('--close-case', choices=['replace-small', 'large-ready', 'import-inflight'], default='replace-small')
    p.add_argument('--visible', action='store_true', help='Exercise a real visible window, including a production binary')
    p.add_argument('--output',type=pathlib.Path,required=True)
    a=p.parse_args();assert not a.output.exists()
    bridge=Bridge();probe=create_probe();report={'passed':False,'platform':sys.platform,'closeCase':a.close_case,'visible':a.visible,'rows':[],
        'guiSHA256':hashlib.sha256(a.gui.read_bytes()).hexdigest(),
        'backendSHA256':hashlib.sha256(a.backend.read_bytes()).hexdigest()}
    def save():
        stage=a.output.with_suffix('.tmp');stage.write_text(json.dumps(report,indent=2)+'\n');stage.replace(a.output)
    save()
    try:
        for index in range(a.rounds):
            row={'round':index,'passed':False};known={};witness=None
            prior_native={}
            for pid,(_,path) in probe.processes().items():
                if pathlib.Path(path).name.casefold()!=a.backend.name.casefold():continue
                try:
                    path=probe.path(pid) if hasattr(probe,'path') else path
                    if same_path(path,str(a.backend)):prior_native[pid]=probe.info(pid)['creation_token']
                except ProcessLookupError:pass
            env=os.environ.copy();env['SNIFFER_SCAN_BACKEND']=str(a.backend.resolve())
            with a.output.with_name(a.output.stem+f'-{index}.app.log').open('w') as log:
                initial=a.small_sns if a.close_case=='import-inflight' else a.large_sns
                launch=[str(a.gui.resolve()),'--scan',str(initial.resolve())]
                if not a.visible:launch.append('--qa-background')
                child=subprocess.Popen(launch,env=env,stdout=log,stderr=subprocess.STDOUT)
                row['ownedPid']=child.pid
                def call(command,**values):
                    assert child.poll() is None,'Owned GUI exited early'
                    return bridge.call_app(command,dict(instance_id=child.pid,**values))
                def observe():
                    metrics=owned_snapshot(probe,child.pid,str(a.backend));known.update({n['pid']:n['creation_token'] for n in metrics['native']})
                    assert metrics['summed_resident_bytes']<2300*2**20,metrics
                    return metrics
                def wait(check):
                    deadline=time.monotonic()+180
                    while time.monotonic()<deadline:
                        assert child.poll() is None,'Owned GUI exited early'
                        value=check()
                        if value:return value
                        time.sleep(.1)
                    raise TimeoutError('Lifecycle state deadline')
                def ready(count=None):
                    s=call('app_status')['windows'][0]
                    assert bool(s['window_visible'])==a.visible and not s['error'],s
                    observe();call('view_capture')
                    if s['phase']=='offline' and not s['projection_pending'] and not s['geometry_pending'] and (count is None or s['files']==count):return s
                def finished(job):
                    s=call('task_status',job_id=job)
                    return s if s['phase'] not in ('pending','running') else None
                try:
                    wait(lambda:any(v['pid']==child.pid for v in bridge.instances()))
                    state=wait(lambda:ready(None if a.close_case=='import-inflight' else 1000000))
                    if a.close_case=='replace-small':
                        for _ in range(2):
                            job=call('snapshot_load',path=str(a.large_sns.resolve()))['job_id'];assert wait(lambda:finished(job))['phase']=='completed';wait(lambda:ready(1000000))
                        old=call('snapshot_load',path=str(a.large_sns.resolve()))['job_id']
                        new=call('snapshot_load',path=str(a.small_sns.resolve()))['job_id']
                        assert wait(lambda:finished(new))['phase']=='completed'
                        state=wait(lambda:ready());assert state['files']<1000 and not state['watch_active'],state
                        assert wait(lambda:finished(old))['phase']=='cancelled'
                        row.update(repeatedMillionImports=2,replacedLargeImport='cancelled')
                    revision=state['snapshot_revision'];call('view_set',width=1200,height=760)
                    assert call('app_status')['windows'][0]['snapshot_revision']==revision
                    row['stateBeforeClose']={'files':state['files'],'revisionPreserved':True}
                    if a.close_case=='import-inflight':
                        job=call('snapshot_load',path=str(a.large_sns.resolve()))['job_id']
                        phase=call('task_status',job_id=job)['phase']
                        row['importPhaseAtClose']=phase
                        assert phase in ('pending','running'),'Import already completed; in-flight case was not exercised'
                        observe()
                    witness=ExitWitness(probe,child.pid);start=time.monotonic()
                    try:call('window_close',window_id=state['window_id'])
                    except RuntimeError as error:
                        if 'disconnected before responding' not in str(error):raise
                    try:child.wait(timeout=8)
                    except subprocess.TimeoutExpired:
                        row['closeTimedOut']=True;row['exitWitness']=witness.result
                        row['diagnostic']=diagnose_exit_timeout(probe,child.pid,a.output.with_name(a.output.stem+f'-{index}.timeout'))
                        row['exitWitnessAfterDiagnostic']=witness.result
                        row['returnCodeAfterDiagnostic']=child.poll()
                        raise
                    assert child.returncode==0,child.returncode
                    deadline=time.monotonic()+2
                    while witness.result is None and time.monotonic()<deadline:time.sleep(.02)
                    assert witness.result and witness.result.get('statusPresent') and witness.result.get('exitCode')==0,witness.result
                    row.update(closeMs=round((time.monotonic()-start)*1000,3),exitCode=child.returncode,exitWitness=witness.result)
                    deadline=time.monotonic()+5
                    while True:
                        alive=[]
                        for pid,token in known.items():
                            try:
                                if probe.info(pid)['creation_token']==token:alive.append(pid)
                            except ProcessLookupError:pass
                        # Also catch late-born import workers, after their GUI parent exited.
                        for pid,(_,path) in probe.processes().items():
                            if pathlib.Path(path).name.casefold()!=a.backend.name.casefold():continue
                            try:
                                path=probe.path(pid) if hasattr(probe,'path') else path
                                if same_path(path,str(a.backend)) and probe.info(pid)['creation_token']!=prior_native.get(pid) and pid not in alive:alive.append(pid)
                            except ProcessLookupError:pass
                        if not alive:break
                        assert time.monotonic()<deadline,('Owned native remains',alive)
                        time.sleep(.1)
                    row.update(passed=True,nativeChildrenAfterClose=0)
                except BaseException as error:
                    row['error']=repr(error);raise
                finally:
                    if witness:witness.close()
                    if child.poll() is None:
                        child.terminate()
                        try:child.wait(timeout=8)
                        except subprocess.TimeoutExpired:child.kill();child.wait(timeout=3)
                    report['rows'].append(row);save()
        report['passed']=True
    finally:save()
    print(json.dumps({'passed':report['passed'],'closeMs':[r.get('closeMs') for r in report['rows']]}))


if __name__=='__main__':main()
