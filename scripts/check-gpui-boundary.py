#!/usr/bin/env python3
"""Keep the GPUI presentation common and OS choices in one composition boundary."""
from pathlib import Path
import re
root=Path(__file__).resolve().parents[1]
violations=[]
for path in (root/'gpui-app/src').rglob('*.rs'):
    if path.name != 'frame.rs' and re.search(r'\bwindow\s*\.\s*draw\s*\(',path.read_text()):
        violations.append(f'{path.relative_to(root)}: manual draw must use ui/frame.rs to clear its arena')
    if 'platform' in path.parts or path.name=='main.rs':continue
    text=path.read_text()
    for forbidden in ['target_os','target_family','WinForms','System.Windows.Forms','use windows::','use objc','use AppKit']:
        if forbidden in text:violations.append(f'{path.relative_to(root)}: {forbidden}')
assert not violations,'\n'.join(violations)
print('PASS: shared GPUI UI/model/projection/layout/motion; OS choices confined to platform adapters')
