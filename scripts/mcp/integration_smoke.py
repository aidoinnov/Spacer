#!/usr/bin/env python3
"""Exercise the real STDIO bridge against a running disposable QA app instance."""
import argparse, base64, json, os, pathlib, select, subprocess, sys, time

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--bundle-id',required=True); ap.add_argument('--output',required=True); ap.add_argument('--verify-projection-reuse',action='store_true'); ap.add_argument('--verify-scan-admission',action='store_true')
    args=ap.parse_args(); out=pathlib.Path(args.output).resolve(); out.mkdir(parents=True,exist_ok=False)
    fixture=out/'fixture'; (fixture/'a').mkdir(parents=True); (fixture/'b').mkdir()
    (fixture/'a'/'one.bin').write_bytes(b'a'*1048576); (fixture/'b'/'two.txt').write_bytes(b'b'*2097152)
    p=subprocess.Popen([sys.executable,str(pathlib.Path(__file__).with_name('space_sniffer_mcp.py')),'--bundle-id',args.bundle_id],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    count=0; checks=[]; window={}
    def rpc(method,params=None):
        nonlocal count
        count+=1; p.stdin.write((json.dumps(dict(jsonrpc='2.0',id=count,method=method,params=params or {}))+'\n').encode());p.stdin.flush()
        assert select.select([p.stdout],[],[],35)[0], 'MCP response timeout'
        r=json.loads(p.stdout.readline()); assert r.get('id')==count and 'error' not in r,r
        return r['result']
    def call(name,extra=None,expect_error=False):
        r=rpc('tools/call',{'name':name,'arguments':window|(extra or {})})
        assert bool(r.get('isError'))==expect_error,(name,r)
        return r if expect_error or name=='view_capture' else r['structuredContent']
    def settled():
        deadline=time.monotonic()+25
        while time.monotonic()<deadline:
            s=call('app_status')
            if s['phase'] not in ('idle','scanning') and not s['projection_pending']: return s
            time.sleep(.05)
        raise AssertionError(('scan/projection timeout',s))
    def job(name,extra):
        j=call(name,extra); deadline=time.monotonic()+25
        while time.monotonic()<deadline:
            s=call('task_status',{'job_id':j['job_id']})
            if s['phase'] not in ('pending','running'): assert s['phase']=='completed',s; return s
            time.sleep(.05)
        raise AssertionError(('artifact timeout',s))
    try:
        rpc('initialize',{'protocolVersion':'2025-11-25','capabilities':{},'clientInfo':{'name':'integration-smoke','version':'1'}})
        from space_sniffer_mcp import TOOL_MAP
        catalog=rpc('tools/list'); assert {t['name'] for t in catalog['tools']}==set(TOOL_MAP)
        instances=call('app_instances'); assert len(instances['instances'])==1,instances
        s=call('app_status'); assert len(s['windows'])==1,s
        window['window_id']=s['windows'][0]['window_id']; checks.append('discovery/catalog/window targeting')
        call('scan_start',{'path':str(fixture),'watching':False}); s=settled()
        assert s['phase']=='completed' and s['snapshot_logical_bytes']==3145728 and s['snapshot_files']==2,s
        # Query paths are snapshot paths. Foundation canonicalizes /private/tmp
        # to /tmp on this host; reuse the root actually reported by the engine.
        fixture=pathlib.Path(s['root'])
        checks.append('real GUI scan: exact 3145728 bytes, 2 files')
        root=call('node_info'); assert root['node']['logical_bytes']==3145728
        page=call('tree_children',{'limit':1}); assert len(page['items'])==1 and page['next_offset'] is not None
        page2=call('tree_children',{'limit':1,'revision':page['revision'],'offset':page['next_offset']}); assert len(page2['items'])==1
        call('tree_children',{'revision':'stale'},expect_error=True)
        largest=call('largest_nodes',{'limit':1}); assert largest['items'][0]['logical_bytes']==2097152,largest
        found=call('query_nodes',{'expression':'*.txt'}); assert len(found['items'])==1,found
        assert call('scan_issues')['issue_count']==0
        checks.append('node details/pagination/stale revision/largest/native filter/issues')
        before_navigation=call('app_resources') if args.verify_projection_reuse else None
        call('view_set',{'path':str(fixture/'a')}); assert settled()['focus_path']==str(fixture/'a')
        call('view_set',{'action':'up'}); assert settled()['focus_path']==str(fixture)
        call('view_set',{'action':'back'}); assert settled()['focus_path']==str(fixture/'a')
        if args.verify_projection_reuse:
            after_navigation=call('app_resources')
            assert before_navigation['workers']['filter.membership']['runs']==after_navigation['workers']['filter.membership']['runs'],(before_navigation,after_navigation)
            assert after_navigation['workers']['filter.projection']['runs']==before_navigation['workers']['filter.projection']['runs']+3
            checks.append('three real UI navigation requests reuse membership/weights')
        call('view_set',{'action':'root','expression':'*.txt','size_mode':'logical'}); s=settled(); assert s['displayed_bytes']==2097152,s
        if args.verify_projection_reuse:
            after_combined=call('app_resources')
            for stage in ['filter.projection','filter.membership']:
                assert after_combined['workers'][stage]['runs']==after_navigation['workers'][stage]['runs']+1,(stage,after_navigation,after_combined)
            call('view_set',{'size_mode':'logical','show_hidden':True}); settled()
            after_same=call('app_resources')
            assert after_same['workers']['filter.projection']['runs']==after_combined['workers']['filter.projection']['runs']
            checks.append('combined root/filter/mode has one pass; identical mode/hidden has zero submits')
        call('view_set',{'expression':'','size_mode':'allocated','depth':3,'list_mode':False}); settled()
        call('node_tag',{'path':str(fixture/'a'/'one.bin'),'color':1}); settled(); assert call('node_info',{'path':str(fixture/'a'/'one.bin')})['node']['own_tag']!=0
        call('node_tag',{'path':str(fixture/'a'/'one.bin'),'color':1}); settled(); assert call('node_info',{'path':str(fixture/'a'/'one.bin')})['node']['own_tag']==0
        call('node_tag',{'path':str(fixture/'a'/'one.bin'),'color':1}); settled(); assert call('node_info',{'path':str(fixture/'a'/'one.bin')})['node']['own_tag']!=0
        checks.append('UI navigation up/back/root/filter/mode/depth/tag including same-color toggle')
        resources=call('app_resources'); assert resources['process']['resident_bytes']>0,resources
        if args.verify_scan_admission:
            engine=resources['engine']
            assert engine['scan_limit']==8 and engine['scan_queue_capacity']==64,engine
            assert 0<=engine['active_scans']<=engine['scan_limit'] and 0<=engine['queued_scans']<=engine['scan_queue_capacity'],engine
            assert engine['peak_active_scans']<=engine['scan_limit'] and engine['finished_scan_workers']<=engine['admitted_scans'],engine
            assert 'scan_scheduling_error' in s and s['scan_scheduling_error'] is None,s
            checks.append('real admission metrics and explicit scheduling-error field')
        volume=call('volume_info',{'path':str(fixture)}); assert volume['total_bytes']>0
        assert call('volumes_list')['volumes']
        rpc('resources/read',{'uri':'space-sniffer://status'}); checks.append('process metrics/worker stats/volumes/MCP resources')
        job('snapshot_save',{'output':str(out/'saved.sns')}); job('report_export',{'output':str(out/'files.txt')})
        call('snapshot_save',{'output':str(out/'saved.sns')},expect_error=True)
        job('snapshot_load',{'path':str(out/'saved.sns')}); assert settled()['offline']
        checks.append('SNS save/load + TXT jobs + existing-output rejection')
        capture=call('view_capture'); image=next(c for c in capture['content'] if c['type']=='image')
        png=base64.b64decode(image['data']); assert png.startswith(b'\x89PNG\r\n\x1a\n') and len(png)>5000
        (out/'mcp-capture.png').write_bytes(png); checks.append('actual app PNG capture')
        call('scan_start',{'path':str(fixture),'watching':False}); settled()
        call('scan_rescan',{'path':str(fixture/'a')}); settled(); call('scan_stop'); checks.append('scoped rescan + stop')
        result={'passed':checks,'rpc_requests':count,'tools':len(catalog['tools']),'resource_sample':resources,'volume_sample':volume}
        if args.verify_projection_reuse:
            result['projection_samples']={'before_navigation':before_navigation,'after_navigation':after_navigation,'after_combined':after_combined,'after_same_values':after_same}
        (out/'results.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n'); print(json.dumps(result,ensure_ascii=False,indent=2))
    finally:
        p.stdin.close(); p.wait(timeout=5)
        error=p.stderr.read(); assert not error,error
if __name__=='__main__': main()
