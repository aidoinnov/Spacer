#!/usr/bin/env python3
"""Real STDIO MCP acceptance against an owned, hidden QA app. No user UI input."""
import argparse
import base64
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import queue
import shutil
import subprocess
import sys
import tempfile
import threading
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'gpui-app'))
from qa_process_metrics import create_probe, owned_snapshot, same_path, foreground_pid, hidden_process_options
from space_sniffer_mcp import Bridge, TOOLS


@contextmanager
def owned_directory():
    temporary=tempfile.TemporaryDirectory(prefix='spacer-mcp-owned-')
    try:yield temporary.name
    finally:
        deadline=time.monotonic()+8
        while True:
            try:temporary.cleanup();break
            except PermissionError:
                # A released Windows image can remain briefly locked by the OS.
                if time.monotonic()>=deadline:raise
                time.sleep(.1)


class Client:
    def __init__(self, bundle):
        self.child = subprocess.Popen([sys.executable, str(Path(__file__).with_name('space_sniffer_mcp.py')),
                                       '--bundle-id', bundle], stdin=subprocess.PIPE,
                                      stdout=subprocess.PIPE, stderr=subprocess.PIPE,**hidden_process_options())
        self.rows = queue.Queue()
        self.errors = bytearray()
        self.counter = 0
        def read():
            for line in self.child.stdout:
                try: self.rows.put(json.loads(line))
                except ValueError as error: self.rows.put(error)
            self.rows.put(EOFError('MCP stdout closed'))
        def stderr():
            self.errors.extend(self.child.stderr.read())
        self.reader = threading.Thread(target=read, daemon=True)
        self.error_reader = threading.Thread(target=stderr, daemon=True)
        self.reader.start(); self.error_reader.start()

    def raw(self, value):
        self.child.stdin.write(value + b'\n'); self.child.stdin.flush()
        row = self.rows.get(timeout=45)
        if isinstance(row, BaseException): raise row
        return row

    def rpc(self, method, params=None):
        self.counter += 1
        row = self.raw(json.dumps({'jsonrpc':'2.0', 'id':self.counter,
                                  'method':method, 'params':{} if params is None else params}).encode())
        assert row.get('id') == self.counter, row
        return row

    def result(self, method, params=None):
        row = self.rpc(method, params)
        assert 'error' not in row, row
        return row['result']

    def close(self):
        try:self.child.stdin.close()
        except BrokenPipeError:pass
        try: self.child.wait(timeout=8)
        except subprocess.TimeoutExpired: self.child.kill(); self.child.wait(timeout=8)
        self.reader.join(timeout=2); self.error_reader.join(timeout=2)
        self.child.stdout.close(); self.child.stderr.close()
        assert self.child.returncode == 0 and not self.errors, (self.child.returncode, bytes(self.errors))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--gui', type=Path, required=True)
    parser.add_argument('--backend', type=Path, required=True)
    parser.add_argument('--bundle-id', default='local.macspacesniffer.app')
    parser.add_argument('--large-sns', type=Path, help='Optional owned SNS fixture for in-flight import cancellation')
    parser.add_argument('--cancel-files',type=int,default=65536,help='Owned cancellation fixture file count (up to 1048576)')
    parser.add_argument('--cancel-branches',type=int,default=128,help='Cancellation fixture branches; must divide the file count')
    parser.add_argument('--require-progress',action='store_true',help='Require observed file-reading progress before cancellation')
    parser.add_argument('--immediate-stop',action='store_true',help='Send stop directly after accepted start without a status round trip')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    assert 1<=args.cancel_files<=1048576 and 1<=args.cancel_branches<=args.cancel_files and args.cancel_files%args.cancel_branches==0
    assert not(args.require_progress and args.immediate_stop)
    assert not args.output.exists()
    args.output.mkdir(parents=True)
    report = {'passed':False, 'checks':[], 'platform':sys.platform, 'scope':'Owned hidden QA app and real STDIO MCP; not performance acceptance',
              'inputs':{str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in [args.gui,args.backend]}, 'skipped':[]}
    report['python']=sys.version
    report['mcpSourceSHA256']={name:hashlib.sha256(Path(__file__).with_name(name).read_bytes()).hexdigest()
                               for name in ['space_sniffer_mcp.py','control_transport.py','acceptance.py']}
    def save(): (args.output/'results.json').write_text(json.dumps(report, indent=2)+'\n')
    def check(name, function):
        start=time.monotonic()
        try: value=function(); row={'name':name,'passed':True,'result':value}
        except Exception as error: row={'name':name,'passed':False,'error':repr(error)}
        row['elapsedMs']=round((time.monotonic()-start)*1000,2)
        report['checks'].append(row); save()
        print(json.dumps(row),flush=True)
        return row['passed']
    child=client=None
    probe=create_probe(); known={}
    bridge=Bridge(args.bundle_id)
    prior={d['pid'] for d in bridge.instances()}
    with owned_directory() as temporary:
        work=Path(temporary); root=work/'fixture'
        files={'alpha/a.txt':17,'alpha/archive.zip':8193,'beta/한국어 파일.txt':33,
               'beta/space name.txt':41,'.hidden.txt':13,'empty.bin':0}
        for name,size in files.items():
            path=root/name; path.parent.mkdir(parents=True,exist_ok=True); path.write_bytes(b'x'*size)
        expected=sum(files.values())
        gui=work/'gui'/args.gui.name; gui.parent.mkdir(); shutil.copy2(args.gui,gui)
        native=work/'native'/args.backend.name; native.parent.mkdir(); shutil.copy2(args.backend,native)
        for dll in args.backend.parent.glob('*.dll'):
            shutil.copy2(dll,native.parent/dll.name)
        preview=args.backend.with_name('libMacPreviewSupport.dylib')
        if preview.exists(): shutil.copy2(preview,gui.parent/preview.name)
        log=(args.output/'app.log').open('w')
        try:
            runtime=work/'runtime';runtime.mkdir()
            env={**os.environ,'SNIFFER_SCAN_BACKEND':str(native),**{key:str(runtime)+os.sep for key in ('TMPDIR','TEMP','TMP')}}
            child=subprocess.Popen([str(gui),'--qa-background','--scan',str(root)],env=env,stdout=log,stderr=log)
            report['ownedPid']=child.pid
            def wait(function,timeout=90):
                end=time.monotonic()+timeout
                while time.monotonic()<end:
                    assert child.poll() is None, ('GUI exited',child.returncode)
                    value=function()
                    if value:return value
                    time.sleep(.1)
                raise TimeoutError('App state did not settle')
            wait(lambda:any(d['pid']==child.pid for d in bridge.instances()))
            client=Client(args.bundle_id)
            initialized=client.result('initialize',{'protocolVersion':'2025-11-25','capabilities':{},'clientInfo':{'name':'spacer-acceptance','version':'1'}})
            assert initialized['protocolVersion']=='2025-11-25'
            client.child.stdin.write(b'{"jsonrpc":"2.0","method":"notifications/initialized"}\n');client.child.stdin.flush()
            window={}
            used=set()
            def call(name,values=None,error=False):
                used.add(name)
                deadline=time.monotonic()+30
                while True:
                    result=client.result('tools/call',{'name':name,'arguments':{'instance_id':child.pid,**window,**(values or {})}})
                    # This explicit pre-execution rejection has not consumed a
                    # native cursor. Never retry a disconnected/written command.
                    pending=(result.get('isError') and any(v.get('text','').split(':',1)[0]=='projection_pending' for v in result.get('content',[])))
                    if name not in ('node_info','tree_children','query_nodes','largest_nodes','scan_issues') or not pending:break
                    assert time.monotonic()<deadline,'Projection readiness deadline'
                    report['projectionPendingRetries']=report.get('projectionPendingRetries',0)+1
                    time.sleep(.1)
                assert bool(result.get('isError'))==error,(name,result)
                return result if error or name=='view_capture' else result['structuredContent']
            state=call('app_status'); window['window_id']=state['windows'][0]['window_id']
            def settled():
                s=call('app_status')
                return s if s['phase'] in ('completed','completed_with_issues','offline','cancelled','failed') and not s['projection_pending'] and not s.get('geometry_pending') else None
            state=wait(settled); root=Path(state['root'])
            # Cursor release requires one immutable revision. A live filesystem
            # watcher can legitimately replace it during this fixture's setup.
            call('scan_start',{'path':str(root),'watching':False,'replace':True})
            state=wait(settled)
            assert not state['watch_active'] and not state['watch_requested'],state
            report['watchDisabledForStableQueryCases']=True
            assert state['files']==len(files) and state['logical_bytes']==expected and not state['window_visible'],state
            report['oracle']={'files':len(files),'logicalBytes':expected,'folders':3}
            def capture_native():
                snapshot=owned_snapshot(probe,child.pid,str(native))
                known.update({n['pid']:n['creation_token'] for n in snapshot['native']})
                return snapshot['summed_resident_bytes']
            check('scan oracle and hidden window',lambda:{'logicalBytes':state['logical_bytes'],'files':state['files'],'residentBytes':capture_native()})
            def catalog():
                names={t['name'] for t in client.result('tools/list')['tools']}
                assert names=={t['name'] for t in TOOLS}
                assert all('token' not in i and 'socket' not in i for i in call('app_instances')['instances'])
                return sorted(names)
            check('catalog and credential-free discovery',catalog)
            def authentication():
                before=call('app_status')['snapshot_revision']
                isolated=Bridge(args.bundle_id)
                discovered=isolated.instances
                def invalid_token(private=False):
                    return [{**d,**({'token':'0'*64} if private else {})}
                            for d in discovered(private) if d['pid']==child.pid]
                isolated.instances=invalid_token
                try:isolated.call_app('scan_start',{'instance_id':child.pid,'path':str(root)})
                except RuntimeError as error:assert 'unauthorized' in str(error),error
                else:raise AssertionError('Incorrect control token was accepted')
                assert call('app_status')['snapshot_revision']==before
                return {'badTokenRejected':True,'documentUnchanged':True}
            check('controller authentication rejects mutation with bad token',authentication)
            def query():
                assert call('node_info')['node']['logical_bytes']==expected
                first=call('tree_children',{'limit':1,'filtered':False}); rows=list(first['items']); seen=set()
                while first.get('next_offset') is not None:
                    offset=first['next_offset']; assert offset not in seen; seen.add(offset)
                    first=call('tree_children',{'limit':1,'filtered':False,'offset':offset,'revision':first['revision']});rows+=first['items']
                assert len(rows)==4,rows
                call('tree_children',{'revision':'stale-test-revision'},error=True)
                biggest=call('largest_nodes',{'limit':1})['items'][0];assert biggest['logical_bytes']==8193,biggest
                found=call('query_nodes',{'expression':'*.txt','budget':100,'limit':20})
                assert len(found['items'])==4,found
                assert call('scan_issues')['issue_count']==0
                return {'rootChildren':len(rows),'textFiles':len(found['items'])}
            check('queries, pagination, stale revision, native filter and issues',query)
            def cursor():
                report['cursorTrace']={'stage':'first-page','revisionBefore':call('app_status')['snapshot_revision']}
                page=call('query_nodes',{'traversal':'subtree','limit':1,'budget':2})
                assert 'next_cursor' in page and 'traversal_steps' in page,page
                assert page['traversal_steps']<=2 and len(page['items'])<=1,page
                report['cursorTrace']['firstPage']=page
                token=page['next_cursor']
                if token:
                    report['cursorTrace']['stage']='cancel'
                    call('query_nodes',{'traversal':'subtree','cursor':token,'cancel_cursor':True})
                    report['cursorTrace']['stage']='reuse-cancelled'
                    rejected=call('query_nodes',{'traversal':'subtree','cursor':token},error=True)
                    # Legacy control returns the native code; the GPUI native
                    # document stream currently carries its localized message.
                    assert any(marker in str(rejected) for marker in ('stale_cursor','Cursor expired')),rejected
                    report['cursorTrace']['stage']='fresh-page'
                    fresh=call('query_nodes',{'traversal':'subtree','limit':20,'budget':1000})
                    assert len(fresh['items'])==len(files) and fresh['next_cursor'] is None,fresh
                report['cursorTrace']['stage']='complete'
                return {'supported':True}
            check('bounded subtree cursor and explicit release',cursor)
            def navigation():
                call('view_set',{'path':str(root/'alpha')});assert wait(settled)['focus_path']==str(root/'alpha')
                for action,path in [('up',root),('back',root/'alpha'),('forward',root)]:
                    call('view_set',{'action':action});assert wait(settled)['focus_path']==str(path)
                call('view_set',{'expression':'*.zip','size_mode':'logical'});assert wait(settled)['displayed_bytes']==8193
                call('view_set',{'expression':'','size_mode':'allocated'});wait(settled)
                return {'navigation':4,'filterBytes':8193}
            check('navigation and view filter',navigation)
            def tags():
                path=str(root/'alpha/a.txt')
                for expected_tag in [True,False]:
                    call('node_tag',{'path':path,'color':1});wait(settled)
                    assert bool(call('node_info',{'path':path})['node']['own_tag'])==expected_tag
                return {'toggle':True}
            check('tag same-color toggle',tags)
            def background_window():
                before=call('app_status')['snapshot_revision']
                foreground_before=foreground_pid()
                second=call('window_new',{'background':True})['window_id']
                try:
                    result=client.result('tools/call',{'name':'app_status','arguments':{'instance_id':child.pid}})['structuredContent']
                    assert len(result['windows'])==2,result
                    new=next(w for w in result['windows'] if w['window_id']==second)
                    assert not new['window_visible'] and not new['scan_documents'][0]['scanning'],new
                    foreground_after=foreground_pid()
                    assert foreground_after!=child.pid,'Hidden new window stole focus'
                    assert call('app_status')['snapshot_revision']==before
                finally:call('window_close',{'window_id':second})
                result=client.result('tools/call',{'name':'app_status','arguments':{'instance_id':child.pid}})['structuredContent']
                assert len(result['windows'])==1,result
                return {'newHiddenWindowClosed':True,'originalDocumentPreserved':True,'foregroundBefore':foreground_before,'foregroundAfter':foreground_after,'focusObservationAvailable':bool(foreground_after)}
            check('background new window preserves document and does not activate',background_window)
            def resources():
                assert call('app_resources')['process']['rss_bytes']>0
                assert call('volume_info',{'path':str(root)})['total_bytes']>0
                assert call('volumes_list')['volumes']
                uris={r['uri'] for r in client.result('resources/list')['resources']}
                # Global resource URIs have no instance selector. Refuse ambiguity
                # instead of inspecting an unrelated user window.
                ambiguous=len(bridge.instances())!=1
                for uri in uris:
                    row=client.rpc('resources/read',{'uri':uri})
                    if ambiguous:assert row.get('error',{}).get('code')==-32603,row
                    else:assert json.loads(row['result']['contents'][0]['text'])
                return {'resources':sorted(uris),'globalResourceAmbiguityRejected':ambiguous}
            check('process metrics, volumes and MCP resources',resources)
            def job(name,values,success=True):
                identifier=call(name,values)['job_id']
                def finished():
                    value=call('task_status',{'job_id':identifier})
                    return value if value['phase'] not in ('pending','running') else None
                value=wait(finished)
                assert value['phase']==('completed' if success else 'failed'),value
                return value
            def artifacts():
                sns=args.output/'saved.sns';txt=args.output/'files.txt'
                job('snapshot_save',{'output':str(sns)});job('report_export',{'output':str(txt)})
                before=sns.read_bytes();call('snapshot_save',{'output':str(sns)},error=True);assert sns.read_bytes()==before
                job('snapshot_load',{'path':str(sns),'inspect_only':True})
                job('snapshot_load',{'path':str(sns)});loaded=wait(settled)
                assert loaded['offline'] and not loaded['watch_active'] and loaded['files']==len(files),loaded
                bad=args.output/'broken.sns';bad.write_bytes(b'not a snapshot')
                revision=loaded['snapshot_revision'];job('snapshot_load',{'path':str(bad)},False)
                assert call('app_status')['snapshot_revision']==revision
                job('snapshot_load',{'path':str(sns)});recovered=wait(settled)
                assert recovered['offline'] and recovered['error'] is None,recovered
                return {'snsBytes':sns.stat().st_size,'reportBytes':txt.stat().st_size,'malformedLoadPreservesDocument':True}
            check('SNS/report jobs, existing-output protection and failed-load rollback',artifacts)
            def configured_export():
                config=args.output/'format.xml'
                template=base64.b64encode('<%pathfile%>{&br}'.encode('utf-16le')).decode()
                config.write_text(f'<exportConfig version="3"><description>Owned MCP export</description><detailFormat>{template}</detailFormat><blockSorting>files</blockSorting><fineSorting>size</fineSorting><fineSortingDirection>desc</fineSortingDirection></exportConfig>')
                revision=call('app_status')['snapshot_revision']
                job('report_export',{'configuration_path':str(config),'inspect_only':True,'config_xml_code_page':65001})
                assert call('app_status')['snapshot_revision']==revision
                output=args.output/'configured.txt'
                job('report_export',{'output':str(output),'configuration_path':str(config),'configuration_index':0,'config_xml_code_page':65001})
                assert '한국어 파일.txt' in output.read_text(encoding='utf-8')
                capped=args.output/'capped.txt'
                job('report_export',{'output':str(capped),'configuration_path':str(config),'max_output_bytes':1},False)
                assert not capped.exists() and call('app_status')['snapshot_revision']==revision
                return {'configurationInspection':True,'unicodeExport':True,'failedCapLeavesNoOutput':True}
            check('configured report, byte cap and atomic failed export',configured_export)
            def png():
                image=next(v for v in call('view_capture')['content'] if v['type']=='image')
                data=base64.b64decode(image['data'],validate=True);assert data.startswith(b'\x89PNG\r\n\x1a\n')
                (args.output/'capture.png').write_bytes(data)
                return {'bytes':len(data)}
            check('real app PNG over MCP',png)
            def rescan():
                call('scan_start',{'path':str(root),'watching':False}); recovered=wait(settled)
                assert recovered['phase']=='completed' and recovered['error'] is None,recovered
                (root/'alpha/new.txt').write_bytes(b'new')
                prior_version=call('app_status')['snapshot_revision']
                receipt=call('scan_rescan',{'path':str(root/'alpha')})
                def refreshed():
                    s=settled();return s if s and s['files']==len(files)+1 and s['snapshot_revision']!=prior_version else None
                refreshed=wait(refreshed)
                assert refreshed['logical_bytes']==expected+3,refreshed
                call('scan_stop');wait(settled)
                return {'files':refreshed['files'],'receipt':receipt}
            check('live scan, scoped rescan and stop',rescan)
            def errors():
                for name,arguments in [('tree_children',{'limit':True}),('tree_children',{'limit':501}),('node_tag',{'color':9,'path':str(root)}),('scan_start',{}),('query_nodes',{'arbitrary_shell':'x'})]:
                    row=client.rpc('tools/call',{'name':name,'arguments':arguments});assert row['error']['code']==-32602,row
                assert client.raw(b'{broken')['error']['code']==-32700
                assert client.result('ping')=={}
                return {'invalidRequests':6,'connectionUsableAfterErrors':True}
            check('protocol errors and recovery',errors)
            def cancellation():
                cancel_root=work/'cancel-fixture';cancel_root.mkdir()
                for branch in range(args.cancel_branches):
                    folder=cancel_root/f'b{branch:03}';folder.mkdir()
                    for index in range(args.cancel_files//args.cancel_branches):(folder/f'f{index:03}').touch()
                call('scan_start',{'path':str(cancel_root),'watching':False})
                observed=None
                if args.require_progress:
                    def reading():
                        state=call('app_status')
                        assert state['phase']=='scanning',('Scan finished before observed reading progress',state)
                        progress=state.get('progress') or {}
                        return progress if progress.get('files',0)>0 else None
                    observed=wait(reading,30)
                active=None if args.immediate_stop else call('app_status')['phase']=='scanning'
                call('scan_stop');s=wait(settled)
                cancelled=bool(s['cancelled'])
                if args.require_progress:assert cancelled and active,('Observed read was not cancelled',s)
                if not(cancelled and (active or args.immediate_stop)):
                    report['skipped'].append({'case':'active cancellation','reason':'Scan completed before cancellation could be observed; idle stop is not a cancellation proof'})
                return {'filesInFixture':args.cancel_files,'readingProgress':observed,'branches':args.cancel_branches,'immediateStop':args.immediate_stop,'observedScanning':active,'cancelled':cancelled,'completedFiles':s['files'],'phase':s['phase'],'status':s['status']}
            check('active scan cancellation',cancellation)
            if args.large_sns:
                def cancel_import():
                    prior_state=call('app_status')
                    identifier=call('snapshot_load',{'path':str(args.large_sns.resolve())})['job_id']
                    initial=call('task_status',{'job_id':identifier})
                    assert initial['phase'] in ('pending','running'),('Import already finished',initial)
                    call('scan_stop')
                    def cancelled():
                        value=call('task_status',{'job_id':identifier})
                        return value if value['phase'] not in ('pending','running') else None
                    final=wait(cancelled)
                    assert final['phase']=='cancelled',final
                    assert call('app_status')['snapshot_revision']==prior_state['snapshot_revision']
                    return {'initialPhase':initial['phase'],'finalPhase':final['phase'],'previousDocumentPreserved':True}
                check('in-flight SNS import cancellation',cancel_import)
            def close_active_window():
                call('scan_start',{'path':str(work/'cancel-fixture'),'watching':False})
                def reading():
                    state=call('app_status')
                    assert state['phase']=='scanning',('Scan finished before close probe',state)
                    return state if (state.get('progress') or {}).get('files',0)>0 else None
                active=wait(reading,30)
                capture_native()
                started=time.monotonic()
                assert call('window_close')['accepted']
                child.wait(timeout=8)
                assert child.returncode==0,child.returncode
                return {'observedReading':active['progress'],'guiExitCode':child.returncode,
                        'closeMs':round((time.monotonic()-started)*1000,2)}
            check('MCP closes last window during active scan',close_active_window)
            report['toolsExercised']=sorted(used)
            report['rpcRequests']=client.counter
            if child.poll() is None:capture_native()
        except BaseException as error:
            report['fatalError']=repr(error)
        finally:
            if client:
                try:client.close();report['mcpExitCode']=client.child.returncode
                except Exception as error:report['mcpCleanupError']=repr(error)
            if child and child.poll() is None:
                try:capture_native()
                except Exception as error:report['cleanupMetricsUnavailable']=repr(error)
                try:bridge.call_app('window_close',{'instance_id':child.pid})
                except Exception:pass
                try:child.wait(timeout=8)
                except subprocess.TimeoutExpired:child.terminate();child.wait(timeout=8)
            log.close()
            report['guiExitCode']=child.returncode if child else None
            deadline=time.monotonic()+8;remaining=[]
            while True:
                remaining=[]
                for pid,(_,path) in probe.processes().items():
                    if Path(path).name.casefold()!=native.name.casefold():continue
                    try:
                        path=probe.path(pid) if hasattr(probe,'path') else path
                        if same_path(path,str(native)):known[pid]=probe.info(pid)['creation_token']
                    except ProcessLookupError:pass
                for pid,token in known.items():
                    try:
                        if probe.info(pid)['creation_token']==token:remaining.append(pid)
                    except ProcessLookupError:pass
                if not remaining or time.monotonic()>deadline:break
                time.sleep(.1)
            report['nativeRemaining']=remaining
            report['nativeScratchRemaining']=[str(p) for p in runtime.glob('sniffer-gpui-*')]
            report['userInstancesPreserved']=prior.issubset({d['pid'] for d in bridge.instances()})
            report['passed']=bool(report['checks']) and all(r['passed'] for r in report['checks']) and not report.get('fatalError') and report.get('guiExitCode')==0 and report.get('mcpExitCode')==0 and not remaining and not report['nativeScratchRemaining'] and report['userInstancesPreserved']
            save()
    report['fixtureRemoved']=not work.exists();save()
    sys.exit(0 if report['passed'] else 1)


if __name__=='__main__':main()
