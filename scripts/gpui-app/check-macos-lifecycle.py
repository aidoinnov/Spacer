#!/usr/bin/env python3
"""Own-process large import/replacement/lifetime gate. Samples combined GUI/native RSS."""
import argparse
import json
import pathlib
import subprocess
import sys
import threading
import time

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / 'mcp'))
from space_sniffer_mcp import Bridge

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('binary', type=pathlib.Path)
p.add_argument('--large-sns', type=pathlib.Path, required=True)
p.add_argument('--small-sns', type=pathlib.Path, required=True)
p.add_argument('--bundle-id', default='local.macspacesniffer.app')
p.add_argument('--output', type=pathlib.Path, required=True)
p.add_argument('--background-qa', action='store_true', help='Use a QA-feature binary without showing or activating its window')
a = p.parse_args()
assert sys.platform == 'darwin', 'This RSS sampler is macOS-specific'
bridge = Bridge(a.bundle_id)
stop = threading.Event()
peaks = {'guiRssBytes': 0, 'treeRssBytes': 0, 'samples': 0}
children = set()
log = a.output.with_suffix('.log').open('w')
launch = [str(a.binary.resolve()), '--scan', str(a.large_sns.resolve())]
if a.background_qa:
    launch.append('--qa-background')
child = subprocess.Popen(launch, stdout=log, stderr=subprocess.STDOUT)


def sample():
    while not stop.is_set():
        rows = {}
        for line in subprocess.run(['ps', '-axo', 'pid=,ppid=,rss='], capture_output=True, text=True).stdout.splitlines():
            values = line.split()
            if len(values) == 3:
                pid, parent, rss = map(int, values)
                rows[pid] = (parent, rss * 1024)
        owned = {child.pid}
        while True:
            updated = owned | {pid for pid, (parent, _) in rows.items() if parent in owned}
            if updated == owned:
                break
            owned = updated
        children.update(owned - {child.pid})
        peaks['guiRssBytes'] = max(peaks['guiRssBytes'], rows.get(child.pid, (0, 0))[1])
        peaks['treeRssBytes'] = max(peaks['treeRssBytes'], sum(rows.get(pid, (0, 0))[1] for pid in owned))
        peaks['samples'] += 1
        stop.wait(.1)


thread = threading.Thread(target=sample, daemon=True)
thread.start()


def call(command, **values):
    return bridge.call_app(command, dict(instance_id=child.pid, **values))


def wait(predicate, timeout=90):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        assert child.poll() is None, 'Owned GUI exited early'
        value = predicate()
        if value:
            return value
        time.sleep(.1)
    raise TimeoutError('Lifecycle readiness timeout')


def ready(files=None):
    v = call('app_status')['windows'][0]
    if a.background_qa:
        assert not v['window_visible'], 'QA window became visible'
        call('view_capture')
    return v if v['phase'] == 'offline' and not v['projection_pending'] and not v['geometry_pending'] and (files is None or v['files'] == files) else None


def finished(key):
    v = call('task_status', job_id=key)
    return v if v['phase'] not in ('pending', 'running') else None


report = {'passed': False, 'rss': peaks}
try:
    wait(lambda: any(v['pid'] == child.pid for v in bridge.instances()))
    state = wait(lambda: ready())
    assert state['files'] >= 1000000, state
    jobs = []
    for _ in range(2):
        key = call('snapshot_load', path=str(a.large_sns.resolve()))['job_id']
        v = wait(lambda: finished(key))
        assert v['phase'] == 'completed', v
        jobs.append(v)
        wait(lambda: ready(state['files']))
    old = call('snapshot_load', path=str(a.large_sns.resolve()))['job_id']
    new = call('snapshot_load', path=str(a.small_sns.resolve()))['job_id']
    latest = wait(lambda: finished(new))
    assert latest['phase'] == 'completed', latest
    state = wait(lambda: ready())
    assert state['files'] < 1000 and not state['watch_active'], state
    stale = wait(lambda: finished(old))
    assert stale['phase'] == 'cancelled', stale
    revision = state['snapshot_revision']
    after_replacement = call('app_resources')['process']
    call('view_set', width=1200, height=760)
    assert call('app_status')['windows'][0]['snapshot_revision'] == revision, 'Resize reprojected document'
    window = call('app_status')['windows'][0]['window_id']
    call('window_close', window_id=window)
    close_started = time.monotonic()
    try:
        child.wait(timeout=8)
    except subprocess.TimeoutExpired:
        # Keep evidence before cleanup; only sample this still-owned child.
        diagnostic = a.output.with_suffix('.timeout-sample.txt')
        report['closeTimedOut'] = True
        report['timeoutSample'] = str(diagnostic)
        try:
            sampled = subprocess.run(
                ['/usr/bin/sample', str(child.pid), '1', '1', '-file', str(diagnostic)],
                capture_output=True, text=True, timeout=5)
            report['timeoutSampleExitCode'] = sampled.returncode
            report['timeoutSampleMessage'] = (sampled.stdout + sampled.stderr)[-2000:]
        except (OSError, subprocess.TimeoutExpired) as error:
            report['timeoutSampleError'] = repr(error)
        raise
    assert child.returncode == 0, f'Owned GUI exited abnormally: {child.returncode}'
    close_ms = (time.monotonic() - close_started) * 1000
    stop.set()
    thread.join(timeout=2)
    live = set(map(int, subprocess.run(['ps', '-axo', 'pid='], capture_output=True, text=True).stdout.split()))
    assert not children & live, 'Owned backend remains after GUI exit'
    assert not any(v['pid'] == child.pid for v in bridge.instances()), 'Controller descriptor remains live'
    report = {'passed': True, 'backgroundQA': a.background_qa, 'largeFiles': 1000000, 'repeatedImports': 2, 'closeMs': round(close_ms, 3), 'closeDeadlineMs': 8000, 'replacedLargeImportPhase': stale['phase'], 'smallFiles': state['files'], 'resizePreservesRevision': True, 'ownedChildrenEnded': True, 'rss': peaks, 'afterReplacement': after_replacement, 'notes': ['100ms process-tree physical RSS sampling on a live macOS workstation; not private memory or exact peak allocation', 'No disktree or Windows memory comparison', 'Only the GUI and descendants created by this script were closed']}
    a.output.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report))
except Exception as error:
    report.update(error=repr(error), rss=peaks)
    raise
finally:
    stop.set()
    if child.poll() is None:
        child.terminate()
        try:
            child.wait(timeout=30)
        except subprocess.TimeoutExpired:
            child.kill()
            try:
                child.wait(timeout=3)
            except subprocess.TimeoutExpired:
                report['ownedProcessReapStillPending'] = True
    thread.join(timeout=2)
    log.close()
    a.output.write_text(json.dumps(report, indent=2) + '\n')
