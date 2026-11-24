#!/usr/bin/env python3
"""Bounded, read-only admission check before A/A; never stops other work."""
import argparse
import datetime
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import time


def command(*args):
    return subprocess.check_output(args, text=True, timeout=30)


def sample():
    # The second top sample describes an interval rather than since boot.
    top = command('/usr/bin/top', '-l', '2', '-s', '1', '-n', '0')
    idle = re.findall(r'([\d.]+)% idle', top)
    vm = command('/usr/bin/vm_stat')
    swap = re.search(r'^Swapouts:\s+(\d+)', vm, re.M)
    assert idle and swap, 'unrecognized host diagnostics; refusing admission'
    return {
        'utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'load_average': list(os.getloadavg()),
        'cpu_idle_percent': float(idle[-1]),
        'swapout_pages_total': int(swap[1]),
        'pressure_level': int(command('/usr/sbin/sysctl', '-n', 'kern.memorystatus_vm_pressure_level')),
        'raw_top': top,
        'raw_vm_stat': vm,
    }


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--fixture-parent', type=Path, default=Path('/private/tmp'))
    p.add_argument('--samples', type=int, default=5)
    a = p.parse_args()
    assert not a.output.exists(), 'refusing report overwrite'
    assert 2 <= a.samples <= 10
    cores = int(command('/usr/sbin/sysctl', '-n', 'hw.logicalcpu'))
    policy = {'samples': a.samples, 'minimum_idle_percent': 70,
              'maximum_load1': cores, 'maximum_swapout_delta_pages': 0,
              'required_pressure_level': 1, 'minimum_fixture_free_bytes': 2 * 1024**3}
    report = {'policy': policy, 'logical_cpus': cores, 'samples': [],
              'scope': 'conservative predeclared collection admission; not proof of latency stability; A/A still required',
              'status': 'collecting'}
    a.output.parent.mkdir(parents=True, exist_ok=True)

    def save():
        temporary = a.output.with_suffix('.tmp')
        temporary.write_text(json.dumps(report, indent=2) + '\n')
        temporary.replace(a.output)

    save()
    try:
        for index in range(a.samples):
            row = sample()
            row['fixture_free_bytes'] = shutil.disk_usage(a.fixture_parent).free
            report['samples'].append(row)
            save()
            if index + 1 < a.samples:
                time.sleep(1)
        rows = report['samples']
        gates = {
            'cpu_idle': all(x['cpu_idle_percent'] >= policy['minimum_idle_percent'] for x in rows),
            'load': all(x['load_average'][0] <= cores for x in rows),
            'swapout': rows[-1]['swapout_pages_total'] == rows[0]['swapout_pages_total'],
            'pressure': all(x['pressure_level'] == 1 for x in rows),
            'disk': all(x['fixture_free_bytes'] >= policy['minimum_fixture_free_bytes'] for x in rows),
        }
        report.update(gates=gates, status='admitted_for_aa' if all(gates.values()) else 'not_admitted')
        report['top_processes'] = command('/bin/ps', '-axo', 'pid,%cpu,%mem,etime,comm', '-r').splitlines()[:16]
        save()
        print(json.dumps({'status': report['status'], 'gates': gates}))
        return 0 if all(gates.values()) else 2
    except Exception as e:
        report.update(status='diagnostic_failed', error=repr(e))
        save()
        raise


if __name__ == '__main__':
    raise SystemExit(main())
