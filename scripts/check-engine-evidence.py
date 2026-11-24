#!/usr/bin/env python3
"""Check the explicit original/platform/UI boundaries and retained original evidence links."""
import json
from pathlib import Path

root = Path(__file__).resolve().parent.parent
manifest = json.loads((root / 'docs/engine-contracts.json').read_text())
bundle = json.loads((root / manifest['evidence_bundle']).read_text())
records = {r['evidence_id']: r for r in bundle['records']}
covered = set()
for rule in manifest['rules']:
    file = root / rule['file']
    assert file.is_file(), f'Missing implementation: {file}'
    assert rule['anchor'] in file.read_text(), f'Missing implementation anchor: {rule["id"]}'
    assert rule['classification'] in {'original', 'platform', 'ui'}, f'Unclassified policy: {rule["id"]}'
    if rule['classification'] == 'original':
        assert rule['evidence'], f'Original behavior without evidence: {rule["id"]}'
    for source in rule['evidence']:
        evidence = records[source['evidence_id']]
        assert evidence['subject']['digest']['sha256'] == manifest['artifact_sha256'], f'Wrong target: {rule["id"]}'
        assert evidence['normalized_result'] is not None, f'No result: {rule["id"]}'
    covered.add(rule['file'])
engine_files = {str(p.relative_to(root)) for directory in [root / 'Sources/SpaceSnifferCore', root / 'Packages/SpaceSnifferScanEngine/Sources'] for p in directory.rglob('*.swift')}
assert engine_files <= covered, f'Engine files without a contract: {engine_files - covered}'
print(f'PASS: {len(engine_files)} engine files, {len(manifest["rules"])} contracts, {len(records)} retained evidence records')
print('This checks traceability; it does not prove Windows runtime equivalence.')
