#!/usr/bin/env python3
"""Package only the portable engine and its tests; never credentials or Mac UI."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import zipfile

root = Path(__file__).resolve().parents[2]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--output', type=Path, required=True)
a = p.parse_args()
a.output.mkdir(parents=True, exist_ok=False)
package = root / 'Packages/SpaceSnifferScanEngine'
files = [package / 'Package.swift', *sorted((package / 'Sources').rglob('*.swift')),
         *sorted((package / 'Tests').rglob('*.swift'))]
manifest = {}
with zipfile.ZipFile(a.output / 'engine.zip', 'w', zipfile.ZIP_DEFLATED) as archive:
    for file in files:
        relative = str(file.relative_to(package))
        archive.write(file, 'engine/' + relative)
        manifest[relative] = hashlib.sha256(file.read_bytes()).hexdigest()
report = {'package': 'SpaceSnifferScanEngine', 'sources': manifest,
          'zip_sha256': hashlib.sha256((a.output / 'engine.zip').read_bytes()).hexdigest(),
          'scope': 'portable production and Windows-only filesystem test adapter; not a Windows GUI or Win32 production reader'}
(a.output / 'source-manifest.json').write_text(json.dumps(report, indent=2) + '\n')
for name in ['run-tests.cmd', 'run-tests.ps1']:
    shutil.copy2(root / 'scripts/windows-validation' / name, a.output / name)
print('Packaged portable engine; Windows runner verifies ZIP and every source hash before building.')
