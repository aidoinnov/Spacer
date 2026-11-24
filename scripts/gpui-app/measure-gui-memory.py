#!/usr/bin/env python3
"""Paired snapshot/directory load, paint and close in owned hidden QA, no OS input."""
import argparse
import hashlib
import json
import pathlib
import statistics
import subprocess
import sys
import time
import os

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / 'mcp'))
from space_sniffer_mcp import Bridge
from qa_process_metrics import create_probe, owned_snapshot


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--gui', type=pathlib.Path, required=True)
    p.add_argument('--sns', type=pathlib.Path, required=True)
    p.add_argument('--before-native', type=pathlib.Path, required=True)
    p.add_argument('--candidate-native', type=pathlib.Path, required=True)
    p.add_argument('--input-kind', choices=['snapshot','directory'], default='snapshot')
    p.add_argument('--pairs', type=int, default=3)
    p.add_argument('--expected-files', type=int, default=1000000)
    p.add_argument('--max-tree-mib', type=int, default=2200)
    p.add_argument('--output', type=pathlib.Path, required=True)
    a = p.parse_args()
    assert not a.output.exists() and a.pairs > 0
    a.output.parent.mkdir(parents=True, exist_ok=True)
    probe = create_probe(); bridge = Bridge()
    if a.input_kind == 'directory':
        entries = sorted(a.sns.rglob('*'))
        files = [path for path in entries if path.is_file()]
        expected_folders = 1 + sum(path.is_dir() for path in entries)
        expected_logical = sum(path.stat().st_size for path in files)
        assert len(files) == a.expected_files
        digest = hashlib.sha256()
        for path in entries:
            digest.update((str(path.relative_to(a.sns))+'\t'+str(path.is_dir())+'\t'+str(path.stat().st_size if path.is_file() else 0)+'\n').encode())
        input_digest = digest.hexdigest()
    else:
        input_digest = hashlib.sha256(a.sns.read_bytes()).hexdigest()
        expected_folders = expected_logical = None
    expected_phase = 'offline' if a.input_kind == 'snapshot' else 'completed' 
    variants = [('before184', a.before_native), ('candidate168', a.candidate_native)]
    report = {'passed': False, 'platform': sys.platform, 'pairs': a.pairs, 'rows': [],
              'scope': 'Owned hidden QA; identical frontend, input and API paint sequence; settled resident/footprint or private commit. Summed RSS double counts shared pages; no scan speed/visible OS-input acceptance claim.',
              'inputKind': a.input_kind, 'inputSHA256': input_digest,
              'guiSHA256': hashlib.sha256(a.gui.read_bytes()).hexdigest(),
              'nativeSHA256': {name: hashlib.sha256(path.read_bytes()).hexdigest() for name, path in variants}}

    def save():
        stage = a.output.with_suffix('.tmp'); stage.write_text(json.dumps(report, indent=2)+'\n'); stage.replace(a.output)

    save()
    try:
        for pair in range(a.pairs):
            for name, native in (variants if pair % 2 == 0 else list(reversed(variants))):
                env = os.environ.copy(); env['SNIFFER_SCAN_BACKEND'] = str(native.resolve())
                row = {'pair': pair, 'variant': name, 'passed': False}
                log_path = a.output.with_name(a.output.stem+f'-{pair}-{name}.app.log')
                with log_path.open('w') as log:
                    child = subprocess.Popen([str(a.gui.resolve()), '--qa-background', '--scan', str(a.sns.resolve())], env=env, stdout=log, stderr=subprocess.STDOUT)
                    row['ownedPid'] = child.pid; known = {}; samples = []
                    def call(command, **args):
                        assert child.poll() is None, 'Owned GUI exited early'
                        return bridge.call_app(command, dict(instance_id=child.pid, **args))
                    try:
                        deadline = time.monotonic()+180
                        while not any(i['pid'] == child.pid for i in bridge.instances()):
                            assert child.poll() is None and time.monotonic()<deadline
                            time.sleep(.1)
                        while True:
                            s = call('app_status')['windows'][0]
                            assert not s['window_visible'] and not s['error'], s
                            metrics = owned_snapshot(probe, child.pid, str(native))
                            assert metrics['summed_resident_bytes'] <= a.max_tree_mib*2**20, metrics
                            known.update({v['pid']:v['creation_token'] for v in metrics['native']})
                            call('view_capture')
                            if s['phase'] == expected_phase and not s['projection_pending'] and not s['geometry_pending']:
                                assert s['files'] == a.expected_files and s['issue_count'] == 0, s
                                if a.input_kind == 'directory':
                                    assert s['folders'] == expected_folders and s['snapshot_logical_bytes'] == expected_logical, s
                                break
                            assert time.monotonic()<deadline, 'Import/paint deadline'
                            time.sleep(.2)
                        call('view_set', list_mode=True); call('view_capture')
                        call('view_set', list_mode=False); call('view_capture')
                        time.sleep(3)
                        for _ in range(3):
                            s = call('app_status')['windows'][0]
                            assert not s['window_visible'] and s['files'] == a.expected_files and not s['error'], s
                            call('view_capture'); value = owned_snapshot(probe, child.pid, str(native))
                            assert value['summed_resident_bytes'] <= a.max_tree_mib*2**20, value
                            known.update({v['pid']:v['creation_token'] for v in value['native']})
                            samples.append(value); time.sleep(.5)
                        row.update(files=s['files'], folders=s['folders'], samples=samples)
                        try:
                            call('window_close', window_id=s['window_id']); row['closeReplyAcknowledged'] = True
                        except RuntimeError as error:
                            if 'disconnected before responding' not in str(error): raise
                            row['closeReplyAcknowledged'] = False
                        start = time.monotonic()
                        try:
                            child.wait(timeout=8)
                        except subprocess.TimeoutExpired:
                            row['closeTimedOut'] = True
                            if sys.platform == 'darwin':
                                sample_path = a.output.with_name(a.output.stem+f'-{pair}-{name}.timeout.txt')
                                subprocess.run(['/usr/bin/sample',str(child.pid),'1','1','-file',str(sample_path)],capture_output=True,timeout=5)
                            raise
                        assert child.returncode == 0, child.returncode
                        row.update(closeMs=round((time.monotonic()-start)*1000,3), exitCode=child.returncode)
                        deadline = time.monotonic()+5
                        while True:
                            alive = []
                            for pid, token in known.items():
                                try:
                                    if probe.info(pid)['creation_token'] == token: alive.append(pid)
                                except ProcessLookupError:
                                    pass
                            if not alive: break
                            assert time.monotonic()<deadline, ('Owned native remains', alive)
                            time.sleep(.1)
                        row.update(passed=True, nativeChildrenAfterClose=0)
                    except BaseException as error:
                        row['error'] = repr(error); raise
                    finally:
                        if child.poll() is None:
                            child.terminate()
                            try: child.wait(timeout=8)
                            except subprocess.TimeoutExpired: child.kill(); child.wait(timeout=3)
                        report['rows'].append(row); save()
        assert len({(r['files'],r['folders']) for r in report['rows']}) == 1
        report['summary'] = {}
        for name, _ in variants:
            rows = [r for r in report['rows'] if r['variant'] == name]
            report['summary'][name] = {
                'guiResidentBytesMedian': statistics.median(statistics.median(s['gui']['resident_bytes'] for s in r['samples']) for r in rows),
                'nativeResidentBytesMedian': statistics.median(statistics.median(sum(n['resident_bytes'] for n in s['native']) for s in r['samples']) for r in rows),
                'summedResidentBytesMedian': statistics.median(statistics.median(s['summed_resident_bytes'] for s in r['samples']) for r in rows)}
        report['passed'] = True
    finally:
        save()
    print(json.dumps({'passed':report['passed'],'summary':report['summary']}))


if __name__ == '__main__': main()
