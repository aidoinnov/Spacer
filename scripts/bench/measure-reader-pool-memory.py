#!/usr/bin/env python3
"""Fresh-process decoder comparison; preserve pre-change reader and source archive."""
import argparse, hashlib, json, statistics, subprocess
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument('--input', required=True)
p.add_argument('--output', required=True)
p.add_argument('--probe', required=True)
a = p.parse_args()
out = Path(a.output)
assert out.exists() and not (out/'report.json').exists()
rows = []
for pair in range(5):
    for mode in (['legacy', 'current'] if pair % 2 == 0 else ['current', 'legacy']):
        run = subprocess.run(['/usr/bin/time', '-lp', a.probe, mode, a.input], capture_output=True, text=True)
        (out/f'{pair}-{mode}.stderr').write_text(run.stderr)
        assert run.returncode == 0, run.stderr
        row = json.loads(run.stdout); row['pair'] = pair; rows.append(row)
    assert rows[-1]['canonical_checksums'] == rows[-2]['canonical_checksums']
    assert rows[-1]['nodes'] == rows[-2]['nodes']
summary = {mode: {key: statistics.median(row[key] for row in rows if row['mode'] == mode)
    for key in ['seconds', 'decoder_max_rss_bytes', 'decoder_physical_footprint_bytes']} for mode in ['legacy', 'current']}
hash_file = lambda path: hashlib.file_digest(path.open('rb'), 'sha256').hexdigest()
report = {'scope': 'five alternating fresh processes on same mapped SNS; timer and RSS high-water sampled before canonical export; footprint is instantaneous after decode, not lifetime peak; all fields emitted by canonical SNS compared via FNV1a; not a Windows runtime oracle or full scan benchmark',
    'rows': rows, 'summary': summary, 'input': a.input, 'input_sha256': hash_file(Path(a.input)),
    'probe_sha256': hash_file(Path(a.probe)), 'source_sha256': {str(path.relative_to(out)): hash_file(path)
    for path in sorted(out.rglob('*.swift'))}}
(out/'report.json').write_text(json.dumps(report, indent=2)+'\n')
print(json.dumps(summary))
