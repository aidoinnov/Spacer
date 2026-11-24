#!/usr/bin/env python3
"""Guard source dependencies; native Windows execution remains a separate check."""
from pathlib import Path
import re
root=Path(__file__).resolve().parent.parent
common=root/'Packages/SpaceSnifferScanEngine'
files=list((common/'Sources').rglob('*.swift'))
assert files
for file in files:
 text=file.read_text()
 imports=set(re.findall(r'^import\s+(\w+)',text,re.M))
 assert imports <= {'Foundation'},(file,imports)
 assert '/private/tmp' not in text,file
 assert not re.search(r'\b(import\s+(Darwin|WinSDK|AppKit|SwiftUI)|qualityOfService|/private/tmp)\b',text),file
assert 'platforms:' not in (common/'Package.swift').read_text(),'shared package constrained to one OS'
assert 'NSCondition(' not in (root/'Sources/SpaceSnifferCore/DirectoryReadAhead.swift').read_text(),'duplicate queue implementation'
assert 'DirectoryWorkerPool' in (root/'Sources/SpaceSnifferCore/DirectoryReadAhead.swift').read_text()
assert 'DirectoryBatchReader' in (root/'Sources/SpaceSnifferCore/MacDirectoryBatchReader.swift').read_text()
print(f'PASS: {len(files)} portable production files; macOS batch adapter uses shared worker implementation')
print('Source boundary check only; Windows SDK build and native I/O are not validated by this check.')
