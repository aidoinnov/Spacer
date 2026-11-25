#!/usr/bin/env python3
"""Compose named installers from verified current payloads, without rebuilding engines."""
import argparse,hashlib,json,os,shutil,subprocess,tempfile,zipfile
from pathlib import Path
from prepare_installers_support import sha,verify,nsis_quote

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--mac-bundle',type=Path,required=True)
p.add_argument('--windows-directory',type=Path,required=True)
p.add_argument('--output',type=Path,required=True)
a=p.parse_args();assert not a.output.exists();a.output.mkdir(parents=True)
repo=Path(__file__).resolve().parents[2];product=json.loads((repo/'gpui-app/product.json').read_text());version=product['version']
mac=json.loads(a.mac_bundle.with_suffix('.manifest.json').read_text());win=json.loads(Path(str(a.windows_directory)+'.manifest.json').read_text(encoding='utf-8-sig'))
wf={v['path'].replace('\\','/'):v['sha256'] for v in win['files']}
assert mac['version']==win['version']==version
verify(a.mac_bundle,mac['files']);verify(a.windows_directory,wf)
assert mac['files']['Contents/MacOS/MacScanBridge']=='a8ab73ee1e9f307669bdd4138015a64e31cba2c0d9feb2720f235f014cb97df5'
assert wf['ExplorerBackend.exe']=='1bf91efa01a4ecadeb96141dd1d5ca00099a7bf5d49e8e235cf3becc813e57d3'
def run(args,**kwargs):return subprocess.run([str(v) for v in args],check=True,**kwargs)
with tempfile.TemporaryDirectory(prefix='spacer-installer-') as directory:
 work=Path(directory);root=work/'dmg';root.mkdir();shutil.copytree(a.mac_bundle,root/'Spacer.app');(root/'Applications').symlink_to('/Applications')
 (root/'Read Me.txt').write_text(f'Spacer {version}\nApple Silicon, macOS 14+\nDrag Spacer.app into Applications.\nAd-hoc signed; not notarized.\n')
 dmg=a.output/f'Spacer-{version}-macos-arm64.dmg';run(['hdiutil','create','-volname',f'Spacer {version}','-srcfolder',root,'-format','UDZO',dmg],stdout=subprocess.DEVNULL)
 run(['ditto','-c','-k','--sequesterRsrc','--keepParent',a.mac_bundle,a.output/f'Spacer-{version}-macos-arm64.zip'])
 payload=a.windows_directory.resolve();ins=work/'install.nsh';delete=work/'delete.nsh';install_lines=[];delete_lines=[]
 for name in sorted(wf):
  parent=Path(name).parent.as_posix().replace('/','\\')
  install_lines+=['SetOutPath "$INSTDIR'+('\\'+parent if parent!='.' else '')+'"','File "'+nsis_quote(payload/name)+'"']
  delete_lines+=['Delete "$INSTDIR\\'+nsis_quote(name.replace('/','\\'))+'"']
 for parent in sorted({str(Path(n).parent).replace('/','\\') for n in wf if str(Path(n).parent)!='.'},key=len,reverse=True):delete_lines+=['RMDir "$INSTDIR\\'+nsis_quote(parent)+'"']
 ins.write_text('\n'.join(install_lines)+'\n');delete.write_text('\n'.join(delete_lines)+'\n')
 setup=a.output/f'Spacer-{version}-windows-x64-setup.exe'
 with (a.output/'installer-build.log').open('w') as log:run(['makensis',f'-DVERSION={version}',f'-DPAYLOAD={payload}',f'-DOUTPUT={setup.resolve()}',f'-DAPPICON={repo}/gpui-app/native/windows-app/AppIcon.ico',f'-DINSTALL_INCLUDE={ins}',f'-DDELETE_INCLUDE={delete}',repo/'scripts/gpui-app/installer-windows.nsi'],stdout=log)
 extracted=work/'extracted';run(['7z','x',setup,f'-o{extracted}','-y'],stdout=subprocess.DEVNULL)
 for name,digest in wf.items():assert sha(extracted/name)==digest,name
 shutil.copy2(ins,a.output/'install.nsh');shutil.copy2(delete,a.output/'delete.nsh')
 with zipfile.ZipFile(a.output/f'Spacer-{version}-windows-x64.zip','w',zipfile.ZIP_DEFLATED) as z:
  for name in sorted(wf):z.write(payload/name,'Spacer/'+name)
shutil.copy2(a.mac_bundle.with_suffix('.manifest.json'),a.output/'mac.manifest.json');shutil.copy2(Path(str(a.windows_directory)+'.manifest.json'),a.output/'windows.manifest.json')
(a.output/'packaging.json').write_text(json.dumps({'version':version,'name':product['name'],'engineNodeBytes':184,'candidate168Included':False,'windowsInstallerPayloadVerified':True,'files':{v.name:sha(v) for v in a.output.iterdir() if v.is_file()}},indent=2)+'\n')
print(a.output)
