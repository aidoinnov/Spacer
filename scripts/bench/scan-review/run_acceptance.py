#!/usr/bin/env python3
"""Run frozen probes through host admission, A/A and the unchanged scan gates."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[3]
SCENARIOS = ['small1000', 'normal10000', 'wide4100', 'wide100000',
             'overbudget131073', 'tinyfolders1000', 'deep200']


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--baseline', type=Path, required=True)
    p.add_argument('--candidate', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    a = p.parse_args()
    baseline, candidate, output = a.baseline.resolve(), a.candidate.resolve(), a.output.resolve()
    assert baseline.is_file() and candidate.is_file()
    output.mkdir(parents=True, exist_ok=False)
    report = {'status': 'starting', 'commands': [], 'started': time.time(),
              'plan': {'scenarios': SCENARIOS, 'aa_pairs': 100, 'standard_pairs': 21,
                       'warmup_pairs': 3, 'minimum_reserve_gib': 2,
                       'host_policy': 'host_preflight.py unchanged defaults',
                       'aa': 'identical candidate binary and parallel4 mode; alternating order',
                       'gates': 'unchanged latency/CI/CPU/RSS; all seven scenarios required'},
              'scope': 'warm/unknown shared host release engine; not GUI or deployment',
              'binaries': {key: {'path': str(path), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
                           for key, path in [('baseline', baseline), ('candidate', candidate)]}}

    def save():
        tmp = output / 'status.tmp'
        tmp.write_text(json.dumps(report, indent=2) + '\n')
        tmp.replace(output / 'status.json')

    def run(label, args, env=None):
        row = {'label': label, 'command': list(map(str, args)), 'started': time.time()}
        report['commands'].append(row)
        report['status'] = label
        save()
        with (output / (label + '.log')).open('w') as log:
            result = subprocess.run(row['command'], cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT)
        row.update(exit_status=result.returncode, finished=time.time())
        save()
        return result.returncode == 0

    def host(label):
        if not run(label, [sys.executable, ROOT / 'scripts/bench/scan-review/host_preflight.py',
                           '--output', output / (label + '.json')]):
            report.update(status='host_not_admitted', failed_stage=label)
            save()
            return False
        return True

    def gates(path, key):
        data = json.loads(path.read_text())
        assert data['status'] == 'measured' and data['cleanup']['removed'], data.get('status')
        assert all(row['status'] == 'ok' and row['pair_equal'] for row in data['rows'] + data['warmup_rows'])
        assert set(data['summary']) == set(SCENARIOS)
        return {name: value['comparisons'][key]['passed'] for name, value in data['summary'].items()}

    save()
    # Caller must finish their builds/tests first; no unrelated process is stopped.
    try:
        if not host('host-before-aa'):
            return 2
        env = os.environ.copy()
        env.pop('SNIFFER_BENCH_VARIANTS', None)
        env.pop('SNIFFER_BENCH_CLONE_FILES', None)
        env['SNIFFER_BENCH_SYNC_FIXTURE'] = '1'
        env['SNIFFER_BENCH_RESERVE_GIB'] = '2'
        compare = [sys.executable, ROOT / 'scripts/bench/scan-parallel/compare.py']
        if not run('aa', compare + ['--before', candidate, '--candidate', candidate,
                                   '--same-binary-aa', '--output', output / 'aa.json',
                                   '--pairs', '100', '--warmup-pairs', '3', '--scenarios', *SCENARIOS], env):
            report['status'] = 'aa_collection_failed'
            return 2
        report['aa_gates'] = gates(output / 'aa.json', 'aa_vs_before')
        if not all(report['aa_gates'].values()):
            report['status'] = 'aa_gates_failed'
            return 2
        if not host('host-before-standard'):
            return 2
        env['SNIFFER_BENCH_VARIANTS'] = 'before,serial,parallel4'
        if not run('standard', compare + ['--before', baseline, '--before-mode', 'parallel4',
                                         '--candidate', candidate, '--output', output / 'standard.json',
                                         '--pairs', '21', '--warmup-pairs', '3', '--scenarios', *SCENARIOS], env):
            report['status'] = 'standard_collection_failed'
            return 2
        report['standard_gates'] = gates(output / 'standard.json', 'parallel4_vs_before')
        if not all(report['standard_gates'].values()):
            report['status'] = 'standard_gates_failed'
            return 2
        if not host('host-after-standard'):
            return 2
        report['status'] = 'engine_gates_passed_deployment_not_performed'
        return 0
    except Exception as error:
        report.update(status='failed', error=repr(error))
        raise
    finally:
        report['finished'] = time.time()
        save()
        print(json.dumps({'status': report['status'], 'output': str(output)}))


if __name__ == '__main__':
    raise SystemExit(main())
