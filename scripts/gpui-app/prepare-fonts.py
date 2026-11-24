#!/usr/bin/env python3
"""Regenerate static UI faces from the retained OFL variable source (fonttools 4.68.0)."""
import hashlib
import json
import pathlib
from fontTools import version
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

root = pathlib.Path(__file__).resolve().parents[2] / 'gpui-app/assets/fonts'
source = root / 'NotoSansKR.ttf'
records = []
for style, weight in [('Regular', 400), ('Medium', 500), ('SemiBold', 600), ('Bold', 700)]:
    font = TTFont(source, recalcTimestamp=False)
    font = instantiateVariableFont(font, {'wght': weight}, inplace=True, updateFontNames=True)
    # A single explicit family lets both CoreText and DirectWrite match by weight.
    for record in font['name'].names:
        if record.nameID in (1, 16):
            record.string = 'Noto Sans KR'.encode(record.getEncoding())
        elif record.nameID in (2, 17):
            record.string = style.encode(record.getEncoding())
    font.recalcTimestamp = False
    target = root / f'NotoSansKR-{style}.ttf'
    font.save(target)
    records.append({'path': target.name, 'weight': weight, 'sha256': hashlib.sha256(target.read_bytes()).hexdigest()})
manifest = {'tool': 'fonttools ' + version, 'source': source.name, 'sourceSha256': hashlib.sha256(source.read_bytes()).hexdigest(), 'license': 'OFL.txt', 'family': 'Noto Sans KR', 'faces': records}
(root / 'static-faces.json').write_text(json.dumps(manifest, indent=2) + '\n')
print(json.dumps(manifest))
