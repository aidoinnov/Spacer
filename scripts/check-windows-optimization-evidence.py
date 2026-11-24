#!/usr/bin/env python3
"""Check portable Windows optimization claims against retained shipped-artifact evidence."""
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parent.parent
manifest = json.loads((root / 'docs/windows-optimization-findings.json').read_text())
digest = lambda data: hashlib.sha256(data).hexdigest()
assert digest((root / manifest['target_path']).read_bytes()) == manifest['target_sha256'], 'EXE changed'
bundle_path = root / manifest['evidence_bundle']
assert digest(bundle_path.read_bytes()) == manifest['evidence_bundle_sha256'], 'Evidence bundle changed'
bundle = json.loads(bundle_path.read_text())
records = {r['evidence_id']: r for r in bundle['records']}
assert len(records) == manifest['bundle_records']
assert len(manifest['findings']) == 20
assert len({f['id'] for f in manifest['findings']}) == 20
checked = set()
for finding in manifest['findings']:
    assert finding['evidence_type'] == 'static_decompilation'
    assert finding['observed'] and finding['optimization_effect_inference'] and finding['limitations']
    for reference in finding['references']:
        r = records[reference['evidence_id']]
        assert r['authority'] == 'shipped-artifact' and r['confidence'] == 'observed'
        assert r['subject']['digest']['sha256'] == manifest['target_sha256']
        assert r['operation'] == reference['operation'] == 'procedure_pseudo_code'
        assert r['parameters']['procedure'] == reference['address']
        payload = r['normalized_result']
        assert isinstance(payload, str) and payload
        assert digest(payload.encode()) == reference['payload_sha256']
        extracted = (root / reference['pseudocode_path']).read_text()
        assert 'Evidence: ' + r['evidence_id'] in extracted
        assert 'SHA-256: ' + manifest['target_sha256'] in extracted
        assert extracted.split('\n\n', 1)[1] == payload
        checked.add(reference['address'])
for reference in manifest['corroborating_evidence']:
    r = records[reference['evidence_id']]
    assert r['subject']['digest']['sha256'] == manifest['target_sha256']
    assert r['operation'] == reference['operation'] and r['parameters'] == reference['parameters']
print(f"PASS: 20 findings, {len(checked)} function extracts, {len(records)} retained records, EXE and payload hashes match")
print('Checks traceability, not runtime performance or behavioral equivalence.')
