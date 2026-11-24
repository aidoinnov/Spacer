#!/usr/bin/env python3
"""Bounded completeness and source/evidence traceability checks; no target execution."""
from collections import Counter
import hashlib
import json
from pathlib import Path
import re

root = Path(__file__).resolve().parent.parent
read = lambda p: json.loads((root / p).read_text())
digest = lambda data: hashlib.sha256(data).hexdigest()
m = read('docs/optimization-checklist.json')
assert digest((root / m['target_path']).read_bytes()) == m['target_sha256'], 'EXE changed'
assert digest((root / m['baseline_findings']).read_bytes()) == m['baseline_findings_sha256']
base = read(m['baseline_findings'])
records = {}
for b in m['evidence_bundles']:
    data = (root / b['path']).read_bytes()
    assert digest(data) == b['sha256'], b['path']
    bundle = json.loads(data)
    assert len(bundle['records']) == b['records']
    for r in bundle['records']:
        if r['evidence_id'] in records:
            assert records[r['evidence_id']] == r, 'Conflicting Evidence'
        records[r['evidence_id']] = r
assert len(records) == m['total_unique_evidence_records']
ids = [i['id'] for i in m['items']]
assert len(ids) == 30 and ids == [f'W{i:02}' for i in range(1, 31)], ids
assert ids[:20] == [i['id'] for i in base['findings']], 'Baseline IDs changed'
assert len([i for i in m['items'] if i['added_after_first_list']]) == 10
assert Counter(i['mac_status'] for i in m['items']) == m['summary']
for f, h in m['reviewed_source_sha256'].items():
    assert digest((root / f).read_bytes()) == h, f'Source changed; re-review checklist: {f}'
for item in m['items']:
    assert item['reviewed'] is True and item['runtime_equivalence_verified'] is False
    assert item['mac_status'] in m['status_definitions']
    assert item['original_observation'] and item['original_limitations'] and item['mac_assessment']
    assert item['remaining_checks'] and item['mac_sources'] and item['original_evidence']
    for reference in item['mac_sources'] + item['existing_test_sources']:
        assert reference['anchor'] in (root / reference['file']).read_text(), (item['id'], reference)
    for reference in item['original_evidence']:
        r = records[reference['evidence_id']]
        assert r['subject']['digest']['sha256'] == m['target_sha256']
        assert r['authority'] == 'shipped-artifact' and r['confidence'] == 'observed'
        assert r['operation'] == 'procedure_pseudo_code'
        assert r['parameters']['procedure'] == reference['address']
        payload = r['normalized_result']
        assert digest(payload.encode()) == reference['payload_sha256']
        text = (root / reference['pseudocode_path']).read_text()
        assert text.split('\n\n', 1)[1] == payload
        assert 'Evidence: ' + r['evidence_id'] in text
old = read(m['evidence_bundles'][0]['path'])
selected = {r['evidence_id'] for f in base['findings'] for r in f['references']}
unused = {r['evidence_id'] for r in old['records'] if r['operation'] == 'procedure_pseudo_code'} - selected
rows = m['baseline_unselected_pseudocode_audit']
assert len(rows) == 55 and len({r['evidence_id'] for r in rows}) == 55
assert {r['evidence_id'] for r in rows} == unused, 'Unselected pseudocode disposition omitted'
allowed = {'new_mechanism_source', 'mechanism_support', 'behavior_or_format', 'unresolved'}
for row in rows:
    assert row['classification'] in allowed and row['reason'] and row['review_depth']
    r = records[row['evidence_id']]
    assert row['address'] == r['parameters']['procedure']
    assert set(row['linked_items']) <= set(ids)
    text = (root / row['pseudocode_path']).read_text()
    assert text.split('\n\n', 1)[1] == r['normalized_result']
assert any(row['classification'] == 'unresolved' for row in rows)
assert m['coverage_boundary']['original_binary_exhaustive'] is False
assert len(m['open_questions']) == 5 and all(q['status'] != 'complete' for q in m['open_questions'])
doc = (root / 'docs/OPTIMIZATION_CHECKLIST.md').read_text()
table = doc.split('## 전체 목록', 1)[1].split('## 이번에 추가한', 1)[0]
assert re.findall(r'^\| \[[ x]\] \| (W\d+)', table, re.M) == ids
links = 0
for link in re.findall(r'\[[^\]]+\]\(([^)]+)\)', doc):
    if '://' in link or link.startswith('#'):
        continue
    assert (root / 'docs' / link.split('#')[0]).exists(), link
    links += 1
print(f'PASS: 30 items / 10 additions / 55 coverage dispositions / {len(records)} Evidence records / {links} local links')
print('Mac source statuses:', dict(Counter(i['mac_status'] for i in m['items'])))
print('Bounded review only; not proof of binary-wide completeness or runtime equivalence.')
