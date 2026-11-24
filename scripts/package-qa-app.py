#!/usr/bin/env python3
"""Package an already-built executable under a separate QA identity."""
import argparse, plistlib, shutil, subprocess
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument('--binary', required=True)
p.add_argument('--output', required=True)
p.add_argument('--bundle-id', required=True)
p.add_argument('--version')
p.add_argument('--build-number')
a = p.parse_args()
app = Path(a.output).resolve()
assert not app.exists(), 'QA output must be new; running apps are never overwritten'
assert a.bundle_id.startswith('local.macspacesniffer.qa.'), 'Use a separate QA bundle identity'
(app/'Contents/MacOS').mkdir(parents=True)
(app/'Contents/Resources/MCP').mkdir(parents=True)
shutil.copy2(a.binary, app/'Contents/MacOS/MacSpaceSniffer')
shutil.copy2('scripts/mcp/space_sniffer_mcp.py', app/'Contents/Resources/MCP/space_sniffer_mcp.py')
shutil.copy2('scripts/mcp/control_transport.py', app/'Contents/Resources/MCP/control_transport.py')
shutil.copy2('dist/Mac Space Sniffer.app/Contents/Resources/AppIcon.icns', app/'Contents/Resources/AppIcon.icns')
info = plistlib.loads(Path('dist/Mac Space Sniffer.app/Contents/Info.plist').read_bytes())
info.update(CFBundleIdentifier=a.bundle_id, CFBundleName='Mac Space Sniffer QA', CFBundleDisplayName='Mac Space Sniffer QA')
if a.version: info['CFBundleShortVersionString'] = a.version
if a.build_number: info['CFBundleVersion'] = a.build_number
(app/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
subprocess.run(['codesign','--force','--deep','--sign','-',str(app)], check=True)
subprocess.run(['codesign','--verify','--deep','--strict',str(app)], check=True)
print(app)
