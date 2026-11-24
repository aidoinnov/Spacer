#!/usr/bin/env python3
"""Own hidden QA only: verify scoped refresh, unchanged view, and parked ownership."""
import argparse
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import time
import uuid

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / 'mcp'))
from space_sniffer_mcp import Bridge


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('binary', type=pathlib.Path)
    p.add_argument('--output', type=pathlib.Path, required=True)
    a = p.parse_args()
    assert not a.output.exists()
    directory = pathlib.Path(tempfile.gettempdir()) / ('sniffer-owned-rescan-' + uuid.uuid4().hex)
    directory.mkdir(mode=0o755)  # Inherit user Temp ACL for the limited Windows GUI.
    root = directory / 'input'
    for name in ('alpha', 'beta'):
        (root / name).mkdir(parents=True)
        (root / name / 'original.txt').write_text('owned ' + name)
    newline = root / 'line\nquit'
    if os.name != 'nt':
        newline.mkdir()
        (newline / 'original.txt').write_text('owned newline scope')
    initial_files = 3 if os.name != 'nt' else 2
    bridge = Bridge()
    log = a.output.with_suffix('.app.log').open('w')
    child = subprocess.Popen([str(a.binary.resolve()), '--qa-background'], stdout=log, stderr=subprocess.STDOUT)
    report = {'passed': False, 'checks': [], 'platform': sys.platform, 'ownedPid': child.pid}

    def call(command, **args):
        assert child.poll() is None, 'Owned QA exited'
        return bridge.call_app(command, dict(instance_id=child.pid, **args))

    def wait(check, seconds=90):
        end = time.monotonic() + seconds
        while time.monotonic() < end:
            value = check()
            if value:
                return value
            time.sleep(.1)
        raise TimeoutError('Scoped rescan acceptance timed out')

    def state():
        s = call('app_status')['windows'][0]
        assert not s['window_visible'] and not s['error'], s
        return s

    def ready(files=None):
        s = state()
        call('view_capture')
        if s['phase'] in ('completed', 'offline') and not s['projection_pending'] and not s['geometry_pending'] and (files is None or s['files'] == files):
            return s

    def same(a, b):
        return pathlib.Path(a).resolve() == pathlib.Path(b).resolve()

    def refresh(path=None):
        before = state()
        accepted = call('scan_rescan', **({'path': str(path)} if path else {}))
        assert accepted['accepted'] and accepted['previous_version']

        def changed():
            s = state()
            call('view_capture')
            owner = next(d for d in s['scan_documents'] if same(d['document_root'], accepted['document_root']))
            assert not owner['offline'] and not owner['cancelled'], owner
            if not owner['scanning'] and owner['version'] != accepted['previous_version']:
                assert owner['issues'] == 0, owner
                return s, owner

        after, owner = wait(changed)
        assert after['focus_path'] == before['focus_path'] and after['history_count'] == before['history_count'], (before, after)
        report['checks'].append({'request': accepted, 'completedOwner': owner, 'focusAndHistoryPreserved': True})
        return accepted, owner

    try:
        wait(lambda: any(i['pid'] == child.pid for i in bridge.instances()))
        call('scan_start', path=str(root), watching=False)
        first = wait(lambda: ready(initial_files))
        canonical_root = pathlib.Path(first['root'])
        call('view_set', path=str(canonical_root / 'beta'))
        wait(ready)
        (root / 'alpha/new.txt').write_text('scoped alpha change')
        (root / 'beta/outside.txt').write_text('outside requested subtree')
        result, owner = refresh(root / 'alpha')
        if result['scope_mode'] == 'subtree':
            assert owner['files'] == initial_files + 1, owner
            assert same(result['effective_path'], root / 'alpha')
        else:
            assert result['scope_mode'] == 'root' and owner['files'] == initial_files + 2, owner
            assert same(result['effective_path'], root)
        result, owner = refresh()
        assert result['scope_mode'] == 'root' and owner['files'] == initial_files + 2

        for path, expected in [(root / 'alpha/original.txt', 'not_directory'), (root / 'missing', 'not_found'), (directory, 'outside_scope')]:
            before = state()
            try:
                call('scan_rescan', path=str(path))
            except RuntimeError as error:
                assert expected in str(error), error
            else:
                raise AssertionError('Invalid scope accepted')
            after = state()
            assert before['snapshot_revision'] == after['snapshot_revision'] and before['focus_path'] == after['focus_path']
            report['checks'].append({'rejected': expected, 'statePreserved': True})

        if os.name != 'nt':
            (newline / 'added.txt').write_text('newline is data, not quit')
            _, owner = refresh(newline)
            assert owner['files'] == initial_files + 3
            report['checks'].append('newline scope refreshed and controller remains alive')

        # Watch is off: this branch is definitely absent from the original cache.
        branch = root / 'uncached-branch'
        branch.mkdir()
        (branch / 'leaf.txt').write_text('owned separate document')
        # view_set addresses snapshot paths; retain the root spelling returned
        # by the app (Python's Windows TEMP environment may use another case).
        call('view_set', path=str(canonical_root / 'uncached-branch'))
        focused = wait(lambda: ready(1))
        assert same(focused['root'], branch), focused
        result, owner = refresh()
        assert result['background'] and same(result['document_root'], root), result
        assert same(state()['root'], branch)
        report['checks'].append('explicitly parked original document refreshed without navigating')
        call('view_set', action='root')
        wait(ready)
        sns = directory / 'saved.sns'
        job = call('snapshot_save', output=str(sns))['job_id']
        wait(lambda: call('task_status', job_id=job)['phase'] == 'completed')
        job = call('snapshot_load', path=str(sns))['job_id']
        wait(lambda: call('task_status', job_id=job)['phase'] == 'completed')
        wait(ready)
        try:
            call('scan_rescan')
        except RuntimeError as error:
            assert 'offline_document' in str(error), error
        else:
            raise AssertionError('Offline refresh accepted')
        report['checks'].append('offline document rejected')
        last = state()
        try:
            call('window_close', window_id=last['window_id'])
            report['closeReplyAcknowledged'] = True
        except RuntimeError as error:
            if 'disconnected before responding' not in str(error):
                raise
            # Closing the last window can close its transport before the reply;
            # require the owned process to exit normally, not merely disappear.
            report['closeReplyAcknowledged'] = False
        child.wait(timeout=8)
        assert child.returncode == 0, child.returncode
        report.update(passed=True, normalExit=child.returncode == 0)
    except BaseException as error:
        report['error'] = repr(error)
        raise
    finally:
        if child.poll() is None:
            child.terminate()
            try:
                child.wait(timeout=8)
            except subprocess.TimeoutExpired:
                child.kill()
        log.close()
        shutil.rmtree(directory)
        report['ownedFixtureRemoved'] = not directory.exists()
        a.output.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report))


if __name__ == '__main__':
    main()
