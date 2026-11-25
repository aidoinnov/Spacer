#!/usr/bin/env python3
"""Owned macOS native fixture: verify intermediate root attribution, wire bounds and cleanup.

Run against a separately built candidate. Never launches or changes the installed GUI.
This is an accounting regression test, not a performance admission benchmark.
"""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import queue
import subprocess
import tempfile
import threading
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--backend', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--files-per-folder', type=int, default=8192)
    args = parser.parse_args()
    if args.files_per_folder <= 0:
        parser.error('files-per-folder must be positive')
    args.output.mkdir(parents=True, exist_ok=True)
    backend = args.backend.resolve()
    report = {'passed': False, 'backend': str(backend),
              'backendSHA256': hashlib.sha256(backend.read_bytes()).hexdigest(),
              'scope': 'native accounting regression; not GUI or speed acceptance'}
    rows = []
    wire_sizes = []
    try:
        with tempfile.TemporaryDirectory(prefix='spacer-overview-owned-') as temp:
            work = Path(temp)
            root = work / 'input'
            root.mkdir()
            for branch in range(8):
                folder = root / f'group-{branch}'
                folder.mkdir()
                for index in range(args.files_per_folder):
                    (folder / f'f{index:05}').write_bytes(b'x')
            # Independent final oracle: no link dedup, sparse files or directory allocations.
            logical = 8 * args.files_per_folder
            allocated = sum(p.stat().st_blocks * 512 for p in root.glob('*/*'))
            started = time.monotonic()
            with (args.output / 'stderr.log').open('wb') as errors:
                process = subprocess.Popen([
                    str(backend), '--scan', str(root), '--output', str(work / 'snapshot.ssw'),
                    '--wire', 'binary', '--watch', 'false', '--parent', str(os.getpid()),
                    '--volumes', 'selectedVolume'], stdin=subprocess.PIPE,
                    stdout=subprocess.PIPE, stderr=errors)
                incoming = queue.Queue()

                def read():
                    for line in process.stdout:
                        try:
                            event = json.loads(line)
                            if event.get('type') == 'progress' and event.get('overviewVersion') == 1:
                                wire_sizes.append(len(line))
                            incoming.put(event)
                        except ValueError:
                            continue
                    incoming.put(None)

                reader = threading.Thread(target=read, daemon=True)
                reader.start()

                def receive():
                    row = incoming.get(timeout=45)
                    assert row is not None, 'native exited before response'
                    rows.append(row)
                    assert row.get('type') != 'failure', row
                    return row

                try:
                    while True:
                        row = receive()
                        if row.get('type') == 'complete':
                            break
                    elapsed = time.monotonic() - started
                    request = {'request': 'overview-oracle', 'version': row['version'],
                               'operation': 'query', 'query': 'tree_children',
                               'queryRevision': row['version'], 'root': 0, 'tags': {},
                               'filter': '', 'logical': False, 'hidden': True,
                               'arguments': {'filtered': False, 'limit': 500}}
                    process.stdin.write((json.dumps(request) + '\n').encode())
                    process.stdin.flush()
                    data = bytearray()
                    while True:
                        row = receive()
                        if row.get('request') != 'overview-oracle':
                            continue
                        assert row['type'] != 'documentError', row
                        if row['type'] == 'documentData':
                            data.extend(base64.b64decode(row['data']))
                        if row['type'] == 'documentEnd':
                            break
                    final = json.loads(data)['items']
                    assert len(final) == 8
                    assert sum(v['logical_bytes'] for v in final) == logical
                    assert sum(v['allocated_bytes'] for v in final) == allocated
                    useful = [r for r in rows if r.get('type') == 'progress'
                              and r.get('overviewVersion') == 1]
                    assert useful, 'no current-version overview events; enlarge fixture if scan is too short'
                    lag = []
                    for event in useful:
                        roots = event['roots']
                        assert len(roots) <= 64
                        assert len({r['path'] for r in roots}) == len(roots)
                        folders = [r for r in roots if r['directory']]
                        for folder in folders:
                            assert Path(folder['path']).parent == root
                        for metric in ['logical', 'allocated']:
                            lag.append(abs(event[metric] - sum(r[metric] for r in folders)))
                    last = useful[-1]
                    # Progress delivery may coalesce the final heartbeat; the complete
                    # document above is the final oracle, not the last progress event.
                    assert last['files'] <= logical
                    assert last['rootFolderCount'] == 8
                    assert len([r for r in last['roots'] if r['directory']]) == 8
                    assert max(lag) == 0, f'stale or missing root bytes: {max(lag)}'
                    report.update(passed=True, files=logical, rootFolders=8,
                                  usefulEvents=len(useful), lastObservedFiles=last['files'], maxFolderLagBytes=max(lag),
                                  unexplainedRemainderBytes=max(lag),
                                  maxWireBytes=max(wire_sizes),
                                  finalLogical=logical, finalAllocated=allocated,
                                  elapsedSeconds=elapsed)
                finally:
                    if process.poll() is None:
                        try:
                            process.stdin.write(b'quit\n')
                            process.stdin.flush()
                        except BrokenPipeError:
                            pass
                        try:
                            process.wait(timeout=8)
                        except subprocess.TimeoutExpired:
                            process.kill()
                            process.wait(timeout=8)
                    process.stdin.close()
                    reader.join(timeout=2)
                    process.stdout.close()
                    report['nativeExitCode'] = process.returncode
                    report['readerStopped'] = not reader.is_alive()
            assert report['nativeExitCode'] == 0 and report['readerStopped']
        report['fixtureRemoved'] = not work.exists()
    except Exception as error:
        report['passed'] = False
        report['error'] = repr(error)
        raise
    finally:
        if 'work' in locals():
            report['fixtureRemoved'] = not work.exists()
        (args.output / 'progress.json').write_text(json.dumps(rows, indent=2) + '\n')
        (args.output / 'summary.json').write_text(json.dumps(report, indent=2) + '\n')
        print(json.dumps(report))


if __name__ == '__main__':
    main()
