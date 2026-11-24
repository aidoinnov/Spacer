#!/usr/bin/env python3
"""Validate the documentation plan; does not run or certify optimizations."""
import hashlib
import argparse
import json
import re
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', default='docs/validation/optimization-plan-documentation-check.json',
                    help='Report destination; choose a new path to preserve historical validation.')
args = parser.parse_args()

def require(condition, message):
    if not condition:
        raise SystemExit('FAIL: ' + message)

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

todo = (ROOT / 'TODO.md').read_text()
history = ROOT / 'TODO_HISTORY_2026-11-08.md'
require(digest(history) == 'ffe5f5cf86157ff1bd4dbccbc3abff376099a9e728a915c72a87374b67972350', 'historical TODO changed')
expected_counts = {'G00': 12, 'A00': 10, 'E01': 10, 'E02': 10, 'B01': 9, 'B02': 8, 'B03': 8, 'B04': 7, 'B05': 8, 'B06': 6, 'B07': 9, 'B08': 8, 'G90': 6, 'G99': 5}
steps = re.findall(r'^- \[([ x])\] ((?:G|A|E|B)\d{2})\.(\d{2}) ', todo, re.M)
require(len(steps) == sum(expected_counts.values()), 'step count mismatch')
progress = json.loads((ROOT / 'docs/optimization-execution-progress.json').read_text())
checked = {group + '.' + step for status, group, step in steps if status == 'x'}
require(checked == set(progress['completed_steps']), 'checked steps differ from evidence progress')
for key, record in progress['completed_steps'].items():
    require(record['evidence'] and record['note'], key + ' has no completion record')
    for evidence in record['evidence']:
        require((ROOT / evidence).is_file(), key + ' missing proof file')
require(len({(group, step) for _, group, step in steps}) == len(steps), 'duplicate step ID')
for group, count in expected_counts.items():
    require({int(step) for _, key, step in steps if key == group} == set(range(1, count + 1)), group + ' missing steps')
require(set(re.findall(r'^\| (R\d{2}) \|', todo, re.M)) == {f'R{i:02}' for i in range(1, 16)}, 'backlog R01–R15 missing')

selection = json.loads((ROOT / 'docs/beneficial-optimizations.json').read_text())
require(digest(ROOT / selection['source_checklist']) == selection['source_checklist_sha256'], 'selection source hash stale')
require({x['id'] for x in selection['work_packages']} == {f'B{i:02}' for i in range(1, 9)}, 'B packages incomplete')
for package in selection['work_packages']:
    if package['implemented']:
        require(package['implementation_status'] == 'implemented_with_recorded_limits', 'missing implementation scope')
        require((ROOT / package['implementation_report']).is_file(), 'missing implementation report')
        require(all(f"{package['id']}.{n:02}" in checked for n in range(1, expected_counts[package['id']] + 1)), 'implementation checklist incomplete')
rows = selection['all_30_dispositions']
require(len(rows) == 30 and {r['id'] for r in rows} == {f'W{i:02}' for i in range(1,31)}, 'W coverage incomplete')
require(dict(Counter(r['disposition'] for r in rows)) == selection['summary'], 'selection counts mismatch')
require({r['id'] for r in rows if r['disposition'] == 'evaluate_first'} == {'W15','W16'}, 'pool priorities inconsistent')
require({r['id'] for r in selection['pool_evaluations']} == {'E01','E02'}, 'pool evaluation missing')
for evaluation in selection['pool_evaluations']:
    require(evaluation['status'] in {'not_started','partial','evaluated_with_recorded_limits'}, 'unknown pool evaluation status')
    if evaluation['status'] == 'evaluated_with_recorded_limits':
        require((ROOT / evaluation['implementation_report']).is_file(), 'pool evaluation report missing')
        require(all(f"{evaluation['id']}.{n:02}" in checked for n in range(1, expected_counts[evaluation['id']] + 1)), 'pool evaluation acceptance steps incomplete')

architecture = (ROOT / 'docs/OPTIMIZATION_MODULE_DESIGN.md').read_text()
modules = re.findall(r'^\| (M\d{2}) [A-Za-z]+ \|', architecture, re.M)
require(len(modules) == 16 and set(modules) == {f'M{i:02}' for i in range(1,17)}, 'module responsibilities M01–M16 missing or duplicated')
require('## A00 ' in todo and 'docs/OPTIMIZATION_MODULE_DESIGN.md' in todo, 'SRP gate disconnected')

link_count = 0
for relative in ['TODO.md', 'TODO_HISTORY_2026-11-08.md', 'docs/BENEFICIAL_OPTIMIZATIONS.md', 'docs/OPTIMIZATION_MODULE_DESIGN.md', 'docs/PROJECTION_SESSION_VALIDATION.md', 'docs/SCAN_RESOURCE_VALIDATION.md', 'docs/ARTIFACT_STREAMING_VALIDATION.md', 'docs/REFRESH_QUEUE_VALIDATION.md', 'docs/REFRESH_LIFECYCLE_VALIDATION.md', 'docs/ACCESSIBILITY_CACHE_VALIDATION.md', 'docs/TOOLTIP_REGISTRY_VALIDATION.md', 'README.md']:
    file = ROOT / relative
    for target in re.findall(r'\]\(([^)]+)\)', file.read_text()):
        if target.startswith(('https://', 'http://', '#', 'mailto:')):
            continue
        target = target.split('#')[0].strip('<>')
        require((file.parent / target).exists(), f'broken link {relative}: {target}')
        link_count += 1
report = {
    'scope': 'documentation consistency only; no implementation or runtime/performance validation',
    'history_sha256': digest(history),
    'task_groups': expected_counts,
    'total_steps': len(steps),
    'checked_steps': len(checked),
    'unchecked_steps': len(steps) - len(checked),
    'backlog_items': 15,
    'module_responsibilities': 16,
    'source_dispositions': selection['summary'],
    'local_links': link_count,
    'checked_document_hashes': {p: digest(ROOT / p) for p in ['TODO.md','docs/BENEFICIAL_OPTIMIZATIONS.md','docs/beneficial-optimizations.json','docs/OPTIMIZATION_MODULE_DESIGN.md','docs/SCAN_RESOURCE_VALIDATION.md','docs/ARTIFACT_STREAMING_VALIDATION.md','docs/optimization-execution-progress.json']},
    'result': 'PASS'
}
destination = Path(args.output)
if not destination.is_absolute():
    destination = ROOT / destination
destination.parent.mkdir(parents=True, exist_ok=True)
destination.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
print(f'PASS: {len(steps)} steps ({len(checked)} checked, {len(steps)-len(checked)} pending) / {len(expected_counts)} task groups / 15 backlog items / 30 source dispositions / {link_count} local links / historical TODO hash')
