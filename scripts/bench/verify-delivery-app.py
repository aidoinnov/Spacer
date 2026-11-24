#!/usr/bin/env python3
"""Exercise an explicitly selected running QA app; mutate only an owned fixture."""
import argparse, base64, importlib.util, json, shutil, sys, tempfile, time, os, math, statistics
from pathlib import Path

sys.dont_write_bytecode = True
p = argparse.ArgumentParser()
p.add_argument('--app', type=Path, required=True)
p.add_argument('--bundle-id', required=True)
p.add_argument('--proof', type=Path, required=True)
p.add_argument('--latency-runs', type=int, default=20)
a = p.parse_args()
spec = importlib.util.spec_from_file_location('delivery_bridge', a.app/'Contents/Resources/MCP/space_sniffer_mcp.py')
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
b = m.Bridge(a.bundle_id)
b.handle(dict(jsonrpc='2.0', id=1, method='initialize', params=dict(protocolVersion=m.LEGACY[0], capabilities={}, clientInfo=dict(name='delivery-qa',version='1'))))
instances = b.instances(); assert len(instances) == 1, instances
pid = instances[0]['pid']
def request(name, **args):
    result = b.handle(dict(jsonrpc='2.0', id=2, method='tools/call', params=dict(name=name,arguments=dict(instance_id=pid,**args))))
    assert not result.get('isError'), result
    return result
def call(name, **args): return request(name, **args)['structuredContent']
call('app_instances'); state = call('app_status')
window = state['windows'][0]['window_id']
def current(): return next(w for w in call('app_status')['windows'] if w['window_id'] == window)
def wait_for(predicate, timeout=30):
    until = time.monotonic()+timeout
    while time.monotonic() < until:
        w = current()
        if predicate(w): return w
        time.sleep(.01)
    raise RuntimeError('app did not settle: '+json.dumps(w))
def capture(name):
    item = next(x for x in request('view_capture',window_id=window)['content'] if x['type']=='image')
    (a.proof/(name+'.png')).write_bytes(base64.b64decode(item['data']))
    return time.monotonic()

assert shutil.disk_usage('/private/tmp').free > 2*1024**3
parent = Path(tempfile.mkdtemp(prefix='sniffer-delivery-gui-', dir='/private/tmp'))
root = parent/'input'; root.mkdir()
record = dict(app=str(a.app.resolve()), pid=pid, root=str(root), parent=str(parent), removed=False, checks={})
proof = a.proof/'gui-delivery.json'
def save(): proof.write_text(json.dumps(record,indent=2)+'\n')
save()
try:
    for branch in range(200):
        if branch%10 == 0: assert shutil.disk_usage(parent).free > 2*1024**3
        folder = root/f'b{branch:03}'; folder.mkdir()
        for index in range(1000): (folder/f'f{index:04}').write_bytes(b'x'*(1+index%100))
    record['expected'] = dict(files=200000, folders=201, logical=10100000, allocated=819200000)
    os.sync(); time.sleep(1)
    record['latency_trials'] = []
    cancelled = 0
    for trial in range(a.latency_runs):
        start = time.monotonic()
        call('scan_start',path=str(root),watching=True,window_id=window)
        early = wait_for(lambda w: w['phase']=='scanning' and bool(w.get('overview_painted_at_uptime_ns')) and bool(((w.get('progress') or {}).get('overview') or {}).get('large_files')))
        row = dict(trial=trial, draw_observed_upper_bound_ms=(time.monotonic()-start)*1000,
                   native_draw_uptime_ns=early['overview_painted_at_uptime_ns'], session=early['scan_session_id'])
        assert early['progress']['files'] < 200000
        overview = early['progress']['overview']
        assert overview['source']=='current_scan_observed' and len(overview['folders']) <= 16 and len(overview['large_files']) <= 16
        assert overview['observed_nodes'] <= early['progress']['files']+early['progress']['folders']
        if trial == 0:
            record['first_overview_state'] = early
            row['capture_return_ms'] = (capture('gui-overview')-start)*1000
        before_stop = current()
        if before_stop['phase']=='scanning':
            stopped_at = time.monotonic(); call('scan_stop',window_id=window)
            stopped = wait_for(lambda w: w['phase']=='cancelled' and not w['projection_pending'])
            row['cancel_settled_ms'] = (time.monotonic()-stopped_at)*1000
            assert stopped['cancelled']; cancelled += 1
        else:
            wait_for(lambda w: w['phase']=='completed' and not w['projection_pending'])
            row['finished_before_cancel'] = True
        record['latency_trials'].append(row); save()
    assert cancelled > 0
    times = sorted(r['draw_observed_upper_bound_ms'] for r in record['latency_trials'])
    record['draw_latency_ms'] = dict(runs=len(times), p50=statistics.median(times), p95=times[math.ceil(len(times)*.95)-1],
                                   scope='native draw observed by MCP; includes transport/polling; warm fixture, same running app')
    record['checks']['overview_before_completion_and_cancel'] = True
    capture('gui-cancelled')
    start = time.monotonic()
    call('scan_start',path=str(root),watching=True,window_id=window)
    final = wait_for(lambda w: w['phase']=='completed' and not w['projection_pending'] and w['snapshot_files']==200000)
    record['rescan_settled_ms'] = (time.monotonic()-start)*1000
    assert final['snapshot_folders']==201 and final['snapshot_logical_bytes']==10100000 and final['snapshot_allocated_bytes']==819200000
    assert final['scan_session_id'] != early['scan_session_id'] and final['volume_traversal']=='selectedVolume'
    record['final_state'] = final; record['checks']['exact_detail_and_replacement_generation'] = True
    capture('gui-detail')
    delta = root/'b000/deploy-watch.bin'; renamed = root/'b000/deploy-renamed.bin'
    delta.write_bytes(b'delta'); delta.rename(renamed)
    updated = wait_for(lambda w: w['phase']=='completed' and not w['projection_pending'] and w['snapshot_files']==200001)
    assert updated['snapshot_logical_bytes']==10100005
    info = call('node_info',path=str(Path(final['root'])/'b000/deploy-renamed.bin'),window_id=window)
    record['watch_node'] = info; record['checks']['create_rename_watch_converged'] = True
    record['resources'] = call('app_resources')
    # Detach from this temporary tree before removing it. This is also a second
    # root replacement check; no former root progress may replace the new root.
    empty = parent/'empty'; empty.mkdir()
    call('scan_start',path=str(empty),watching=False,window_id=window)
    empty_state = wait_for(lambda w: w['phase']=='completed' and not w['projection_pending'] and w['snapshot_files']==0)
    assert Path(empty_state['root']).resolve()==empty.resolve()
    assert empty_state.get('overview_painted_at_uptime_ns') is None
    record['checks']['empty_root_replacement'] = True
    record['status'] = 'passed'
finally:
    # All paths here were created under the uniquely named owned fixture.
    if record.get('status')=='passed':
        shutil.rmtree(parent); record['removed'] = not parent.exists()
    save()
print(json.dumps({k:v for k,v in record.items() if k.endswith('_ms') or k in ['checks','status','removed']}))
