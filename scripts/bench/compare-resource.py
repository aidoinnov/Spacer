#!/usr/bin/env python3
"""Run before/after release probes sequentially, alternating each pair."""
import argparse
import json
from pathlib import Path
import re
import statistics
import subprocess

parser = argparse.ArgumentParser()
for name in ('before-filter', 'after-filter', 'before-tree', 'after-tree'):
    parser.add_argument('--' + name, required=True)
args = parser.parse_args()
out = Path(__file__).resolve().parents[2] / 'docs/validation'

def compare(group, scenarios, binaries, argument):
    rows = []
    for scenario in scenarios:
        samples = {'before': [], 'after': []}
        for index in range(3):
            for version in ('before', 'after'):
                result = subprocess.run(['/usr/bin/time', '-l', binaries[version], *argument(scenario)], capture_output=True, text=True, check=True)
                (out / f'resource-{group}-{scenario}-{version}-{index}.txt').write_text(result.stdout + result.stderr)
                value = json.loads(result.stdout)
                value['maxRSSBytes'] = int(re.search(r'(\d+)\s+maximum resident set size', result.stderr).group(1))
                samples[version].append(value)
        row = {'scenario': scenario, 'files': 250000}
        for version, values in samples.items():
            row[version] = {'medianSeconds': statistics.median(v['seconds'] for v in values),
                            'maxRSSMiB': max(v['maxRSSBytes'] for v in values) / 1048576,
                            'checksum': values[0]['checksum'], 'runs': values}
        assert row['before']['checksum'] == row['after']['checksum']
        row['speedup'] = row['before']['medianSeconds'] / row['after']['medianSeconds']
        rows.append(row)
    (out / f'resource-{group}-comparison.json').write_text(json.dumps(rows, indent=2) + '\n')
    for row in rows:
        print(row['scenario'], round(row['before']['medianSeconds']*1000, 3), '->', round(row['after']['medianSeconds']*1000, 3), 'ms;', round(row['speedup'], 2), 'x')

compare('filter', ['name', 'folder', 'tagsHidden'], {'before': args.before_filter, 'after': args.after_filter}, lambda name: [name])
compare('tree', ['projection', 'merge'], {'before': args.before_tree, 'after': args.after_tree}, lambda name: ['250000', name])
