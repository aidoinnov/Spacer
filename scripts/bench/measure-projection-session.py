#!/usr/bin/env python3
"""Five alternating release comparisons; metadata only, no UI/disk scan claim."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import statistics
import subprocess

p = argparse.ArgumentParser()
p.add_argument('--probe', required=True)
p.add_argument('--output', required=True)
a = p.parse_args()
rows = []
for pair in range(5):
    for mode in (['full', 'session'] if pair % 2 == 0 else ['session', 'full']):
        r = subprocess.run(['/usr/bin/time', '-l', a.probe, mode, '250000'], capture_output=True, text=True, check=True, timeout=55)
        row = json.loads(r.stdout)
        row['pair'] = pair
        row['max_rss_bytes'] = int(re.search(r'(\d+)\s+maximum resident set size', r.stderr).group(1))
        rows.append(row)
summaries = {}
for mode in ['full', 'session']:
    samples = [r for r in rows if r['mode'] == mode]
    summaries[mode] = {k: {'median': statistics.median(r[k] for r in samples), 'min': min(r[k] for r in samples), 'max': max(r[k] for r in samples)} for k in ['initial_seconds', 'navigation_seconds', 'max_rss_bytes']}
assert len({r['checksum'] for r in rows}) == 1
sources = sorted(Path('Sources').rglob('*.swift')) + [Path('Package.swift'), Path('scripts/bench/projection-session.swift'), Path(__file__)]
report = {'date': '2026-11-09', 'scope': '250k metadata fixture; 10 navigations after initial evaluation; both paths LatestWorker/MainActor; excludes UI, geometry and disk I/O; process peak RSS includes fixture construction', 'pairs': 5, 'compiler': subprocess.check_output(['swiftc', '--version'], text=True).strip(), 'platform': subprocess.check_output(['sw_vers'], text=True).strip(), 'source_sha256': {str(f): hashlib.sha256(f.read_bytes()).hexdigest() for f in sources}, 'probe_sha256': hashlib.sha256(Path(a.probe).read_bytes()).hexdigest(), 'rows': rows, 'summary': summaries}
Path(a.output).write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(summaries, indent=2))
