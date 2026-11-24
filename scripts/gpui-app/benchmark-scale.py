#!/usr/bin/env python3
"""Paired actual-GPUI SNS import/filter/resize measurements; use a QA build."""
import argparse
import hashlib
import datetime
import json
import pathlib
import statistics
import subprocess

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('gpui', type=pathlib.Path)
p.add_argument('--sns', type=pathlib.Path, required=True)
p.add_argument('--pairs', type=int, default=5)
p.add_argument('--output', type=pathlib.Path, required=True)
a = p.parse_args()
assert 1 <= a.pairs <= 20
assert a.gpui.is_file() and a.sns.is_file()
a.output.parent.mkdir(parents=True, exist_ok=True)
samples = []
for index in range(a.pairs):
    for mode in (['binary', 'json'] if index % 2 else ['json', 'binary']):
        output = a.output.with_name(f'{a.output.stem}-{mode}-{index}.json')
        assert not output.exists(), 'Use a fresh output path to preserve prior results'
        command = [str(a.gpui.resolve()), '--scan', str(a.sns.resolve()), '--qa-scale-only', str(output.resolve()), '--qa-visible']
        if mode == 'json':
            command.append('--qa-wire-json')
        with output.with_suffix('.log').open('w') as log:
            subprocess.run(command, check=True, timeout=150, stdout=log, stderr=subprocess.STDOUT)
        report = json.loads(output.read_text())
        assert report['passed'], report
        report.update(mode=mode, pair=index)
        samples.append(report)
        print(mode, index, report['firstReadyMs'], flush=True)
report = {'passed': True, 'samples': samples, 'createdUTC': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'executableSha256': hashlib.file_digest(a.gpui.open('rb'), 'sha256').hexdigest(), 'inputSha256': hashlib.file_digest(a.sns.open('rb'), 'sha256').hexdigest(),
          'firstReadyMs': {mode: statistics.median(v['firstReadyMs'] for v in samples if v['mode'] == mode) for mode in ['json', 'binary']},
          'notes': ['Same current QA binary; alternating order; visible windows required for opacity/animation readiness',
                    'Readiness timer starts after GPUI/font initialization; SNS import and first visible map, not full startup or filesystem traversal throughput',
                    'Resize includes a fixed 60ms settle; process RSS excludes the native backend',
                    'Run with other benchmarks/builds stopped for controlled comparisons; no p95 claim from five pairs']}
a.output.write_text(json.dumps(report, indent=2) + '\n')
