#!/usr/bin/env python3
"""Package the frozen 2026-11-24 release; never compile or install the candidate."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import zipfile


def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def run(argv, **kwargs):
    return subprocess.run([str(x) for x in argv], check=True, **kwargs)


def verify(root, files):
    actual = {p.relative_to(root).as_posix(): sha(p)
              for p in root.rglob('*') if p.is_file()}
    assert actual == files, f'Payload does not exactly match frozen manifest: {root}'


def nsis_quote(value):
    return str(value).replace('$', '$$').replace('"', '$\\"')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-delivery', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    src, out = args.source_delivery.resolve(), args.output.resolve()
    assert not out.exists(), 'Use a new output directory; never overwrite release evidence'
    repo = Path(__file__).resolve().parents[2]
    mac = json.loads((src/'mac.manifest.json').read_text(encoding='utf-8-sig'))
    win = json.loads((src/'windows.manifest.json').read_text(encoding='utf-8-sig'))
    wf = {f['path'].replace('\\', '/'): f['sha256'] for f in win['files']}
    assert mac['files']['Contents/MacOS/MacSpaceSniffer'] == '71b58ddcacc0404b79d9c7c98ed0993ef7a99782ddd8d81410e5136a1b569137'
    assert mac['files']['Contents/MacOS/MacScanBridge'] == 'a8ab73ee1e9f307669bdd4138015a64e31cba2c0d9feb2720f235f014cb97df5'
    assert wf['MacSpaceSniffer.exe'] == '77280faa7f57cf40f385925d7b828d621c90becc11cd80ce30061a70f229a2d2'
    assert wf['ExplorerBackend.exe'] == '1bf91efa01a4ecadeb96141dd1d5ca00099a7bf5d49e8e235cf3becc813e57d3'
    out.mkdir(parents=True)
    evidence = out/'Evidence'
    evidence.mkdir()
    with tempfile.TemporaryDirectory(prefix='sniffer-installers-') as temporary:
        work = Path(temporary)
        dmg_root = work/'dmg'
        dmg_root.mkdir()
        run(['ditto', '-x', '-k', src/'Mac-Space-Sniffer-0.3.0-arm64-os-input.zip', dmg_root])
        shutil.rmtree(dmg_root/'__MACOSX', ignore_errors=True)
        app = dmg_root/'Mac Space Sniffer.app'
        verify(app, mac['files'])
        run(['codesign', '--verify', '--deep', '--strict', app])
        assert subprocess.run([str(app/'Contents/MacOS/MacSpaceSniffer'), '--qa-output', 'unused'],
                              capture_output=True).returncode == 64
        (dmg_root/'Applications').symlink_to('/Applications', target_is_directory=True)
        (dmg_root/'설치 안내.txt').write_text(
            'Mac Space Sniffer 0.3.0 (Apple Silicon, macOS 14 이상)\n\n'
            '앱을 Applications로 드래그한 뒤 그곳에서 실행하세요.\n'
            '기존 버전을 교체할 때는 먼저 앱을 정상 종료하세요.\n'
            '현재 패키지는 ad-hoc 서명이며 Apple 공증을 받지 않았습니다.\n'
            '조직 내 검수용 패키지입니다. 보안 정책에 의해 실행이 제한될 수 있습니다.\n')
        dmg = out/'SpaceSniffer-0.3.0-20261124.1-macos-arm64.dmg'
        run(['hdiutil', 'create', '-volname', 'Space Sniffer 0.3.0', '-srcfolder', dmg_root,
             '-format', 'UDZO', dmg])
        run(['hdiutil', 'verify', dmg])
        # Mount independently and verify the actual distribution payload, not staging only.
        mounted = run(['hdiutil', 'attach', '-readonly', '-nobrowse', '-plist', dmg], capture_output=True)
        import plistlib
        entities = plistlib.loads(mounted.stdout)['system-entities']
        mount = next(Path(e['mount-point']) for e in entities if 'mount-point' in e)
        try:
            verify(mount/'Mac Space Sniffer.app', mac['files'])
            run(['codesign', '--verify', '--deep', '--strict', mount/'Mac Space Sniffer.app'])
            assert (mount/'Applications').is_symlink()
        finally:
            run(['hdiutil', 'detach', mount])

        payload = work/'windows'
        payload.mkdir()
        with zipfile.ZipFile(src/'SpaceSniffer-0.3.0-windows-x64-os-input.zip') as archive:
            assert archive.testzip() is None
            for info in archive.infolist():
                parts = info.filename.replace('\\', '/').split('/')
                assert parts[0] == 'ui-fix-package' and '..' not in parts
                relative = Path(*parts[1:])
                if info.is_dir() or not str(relative) or str(relative) == '.': continue
                dest = payload/relative
                dest.parent.mkdir(parents=True, exist_ok=True)
                dest.write_bytes(archive.read(info))
        verify(payload, wf)
        install_lines, delete_lines = [], []
        for name in sorted(wf):
            parent = str(Path(name).parent).replace('/', '\\')
            install_lines.append('SetOutPath "$INSTDIR' + (('\\'+parent) if parent != '.' else '') + '"')
            install_lines.append('File "' + nsis_quote(payload/name) + '"')
            delete_lines.append('Delete "$INSTDIR\\' + nsis_quote(name.replace('/', '\\')) + '"')
        parents = {str(Path(n).parent).replace('/', '\\') for n in wf if str(Path(n).parent) != '.'}
        for parent in sorted(parents, key=len, reverse=True):
            delete_lines.append('RMDir "$INSTDIR\\' + nsis_quote(parent) + '"')
        ins, dele = work/'install.nsh', work/'delete.nsh'
        ins.write_text('\n'.join(install_lines)+'\n')
        dele.write_text('\n'.join(delete_lines)+'\n')
        exe = out/'SpaceSniffer-0.3.0-20261124.1-windows-x64-setup.exe'
        with (evidence/'makensis.log').open('w') as log:
            run(['makensis', f'-DPAYLOAD={payload}', f'-DOUTPUT={exe}',
                 f'-DAPPICON={repo}/gpui-app/native/windows-app/AppIcon.ico',
                 f'-DINSTALL_INCLUDE={ins}', f'-DDELETE_INCLUDE={dele}',
                 repo/'scripts/gpui-app/installer-windows.nsi'], stdout=log)
        extracted = work/'extracted'
        with (evidence/'installer-extract.log').open('w') as log:
            run(['7z', 'x', exe, f'-o{extracted}', '-y'], stdout=log)
        for name, expected in wf.items():
            assert sha(extracted/name) == expected, f'Installer extraction mismatch: {name}'
        shutil.copy2(ins, evidence/'install.nsh')
        shutil.copy2(dele, evidence/'delete.nsh')
    for name in ['mac.manifest.json', 'windows.manifest.json']:
        shutil.copy2(src/name, evidence/name)
    report = {'version':'0.3.0', 'packageRevision':'20261124.1', 'engineNodeBytes':184,
              'candidate168Included':False, 'rebuiltApplication':False,
              'mac': {'signature':'ad-hoc', 'notarized':False, 'mountedPayloadHashesVerified':True},
              'windows': {'authenticode':'NotSigned', 'extractedPayloadHashesVerified':True,
                          'installerRuntimeValidated':False},
              'installedApplicationsReplaced':False, 'published':False,
              'sourceDelivery':str(src)}
    (evidence/'verification.json').write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
