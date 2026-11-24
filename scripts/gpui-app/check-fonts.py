#!/usr/bin/env python3
"""Independent stdlib OpenType metadata check for the shipped static faces."""
import hashlib
import json
import pathlib
import struct

root = pathlib.Path(__file__).resolve().parents[2] / 'gpui-app/assets/fonts'
manifest = json.loads((root / 'static-faces.json').read_text())
assert hashlib.sha256((root / manifest['source']).read_bytes()).hexdigest() == manifest['sourceSha256']
checks = []
for face in manifest['faces']:
    data = (root / face['path']).read_bytes()
    assert hashlib.sha256(data).hexdigest() == face['sha256']
    count = struct.unpack_from('>H', data, 4)[0]
    tables = {}
    for index in range(count):
        tag, _, offset, length = struct.unpack_from('>4sIII', data, 12 + 16 * index)
        assert offset + length <= len(data)
        tables[tag] = offset
    assert b'fvar' not in tables, 'A variable default must not masquerade as a static face'
    weight = struct.unpack_from('>H', data, tables[b'OS/2'] + 4)[0]
    assert weight == face['weight']
    offset = tables[b'name']
    _, count, strings = struct.unpack_from('>HHH', data, offset)
    family = None
    for index in range(count):
        platform, encoding, language, name, length, start = struct.unpack_from('>HHHHHH', data, offset + 6 + 12 * index)
        if platform == 3 and language == 1033 and name == 1:
            family = data[offset + strings + start:offset + strings + start + length].decode('utf-16-be')
    assert family == manifest['family']
    checks.append({'face': face['path'], 'weight': weight, 'family': family, 'static': True})
assert sorted(v['weight'] for v in checks) == [400, 500, 600, 700]
print(json.dumps({'passed': True, 'checks': checks}))
