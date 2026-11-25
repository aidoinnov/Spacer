#!/usr/bin/env python3
"""Compose a release bundle from already-built binaries; never replaces a running app."""
import argparse, hashlib, json, pathlib, plistlib, shutil, subprocess

p = argparse.ArgumentParser()
p.add_argument('--rust-binary', type=pathlib.Path, required=True)
p.add_argument('--cli-binary', type=pathlib.Path, help='Console companion (defaults to SpacerCLI beside the GUI binary)')
p.add_argument('--native-directory', type=pathlib.Path, required=True)
p.add_argument('--output', type=pathlib.Path, required=True)
a = p.parse_args()
repo = pathlib.Path(__file__).resolve().parents[2]
product = json.loads((repo/'gpui-app/product.json').read_text())
version = product['version']
executable = product['executable']
assert subprocess.check_output([str(a.rust_binary),'--version'],text=True).strip() == f'Spacer {version}', 'GUI version mismatch'
cli = a.cli_binary or a.rust_binary.with_name('SpacerCLI')
assert subprocess.check_output([str(cli),'--version'],text=True).strip() == f'Spacer CLI {version}', 'CLI version mismatch'
assert not a.output.exists(), 'Output must be new; preserve the previous bundle for rollback'
inputs = {executable: a.rust_binary, 'MacScanBridge': a.native_directory / 'MacScanBridge',
          'libMacPreviewSupport.dylib': a.native_directory / 'libMacPreviewSupport.dylib',
          'SpacerCLI': a.cli_binary or a.rust_binary.with_name('SpacerCLI')}
for value in inputs.values():
    assert value.is_file(), value
contents = a.output / 'Contents'
(contents / 'MacOS').mkdir(parents=True)
resources = contents / 'Resources'
(resources / 'MCP').mkdir(parents=True)
for name, source in inputs.items():
    shutil.copy2(source, contents / 'MacOS' / name)
for name in ['space_sniffer_mcp.py', 'control_transport.py']:
    shutil.copy2(repo / 'scripts/mcp' / name, resources / 'MCP' / name)
(resources / 'MCP').chmod(0o555)
shutil.copy2(repo / 'gpui-app/native/macos-app/AppIcon.icns', resources / 'AppIcon.icns')
shutil.copy2(repo / 'gpui-app/assets/fonts/OFL.txt', resources / 'NotoSansKR-OFL.txt')
info = {'CFBundleExecutable': executable, 'CFBundleIdentifier': product['bundle_id'],
        'CFBundleName': product['name'], 'CFBundleDisplayName': product['name'],
        'CFBundlePackageType': 'APPL', 'CFBundleShortVersionString': version, 'CFBundleVersion': str(sum(int(v)*m for v,m in zip(version.split('.'),[10000,100,1]))),
        'CFBundleIconFile': 'AppIcon', 'LSMinimumSystemVersion': '14.0', 'NSHighResolutionCapable': True,
        'NSPrincipalClass': 'NSApplication',
        'NSHumanReadableCopyright': 'Spacer contributors'}
(contents / 'Info.plist').write_bytes(plistlib.dumps(info))
for name in ['MacScanBridge', 'libMacPreviewSupport.dylib', 'SpacerCLI', executable]:
    subprocess.run(['codesign', '--force', '--sign', '-', str(contents / 'MacOS' / name)], check=True)
subprocess.run(['codesign', '--force', '--sign', '-', str(a.output)], check=True)
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(a.output)], check=True)
result = subprocess.run([str(contents / 'MacOS' / executable), '--qa-output', 'unused'], capture_output=True)
assert result.returncode == 64, 'Release must reject acceptance commands before opening a window'
manifest = {'version': version, 'bundleId': info['CFBundleIdentifier'], 'signature': 'ad-hoc',
            'qaCommandsRejected': True, 'mcpResourceDirectoryMode': '0555', 'files': {str(v.relative_to(a.output)): hashlib.sha256(v.read_bytes()).hexdigest()
                                               for v in a.output.rglob('*') if v.is_file()}}
a.output.with_suffix('.manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
print(json.dumps({'bundle': str(a.output), 'passed': True, 'signature': 'ad-hoc'}))
