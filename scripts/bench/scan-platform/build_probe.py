#!/usr/bin/env python3
"""Build a frozen same-module Core probe with the independent shared dependency."""
import argparse,hashlib,json,shutil,subprocess,tempfile
from pathlib import Path

def main():
 root=Path(__file__).resolve().parents[3]
 p=argparse.ArgumentParser();p.add_argument('--core',type=Path,default=root/'Sources/SpaceSnifferCore');p.add_argument('--shared',type=Path,default=root/'Packages/SpaceSnifferScanEngine');p.add_argument('--profile',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
 assert not a.output.exists(),'refusing binary overwrite'
 assert not a.output.with_suffix('.sources.json').exists(),'refusing manifest overwrite'
 with tempfile.TemporaryDirectory(prefix='sniffer-platform-probe-',dir='/private/tmp') as work:
  work=Path(work);sources=work/'Sources';sources.mkdir()
  for file in a.core.rglob('*.swift'):
   dest=sources/file.relative_to(a.core);dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(file,dest)
  shutil.copy2(a.profile,sources/'profile.swift')
  shutil.copytree(a.shared,work/'Engine',ignore=shutil.ignore_patterns('.build','.swiftpm'))
  (work/'Package.swift').write_text('''// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "SnifferScanProbe", platforms: [.macOS(.v14)], dependencies: [.package(path: "Engine")], targets: [
    .executableTarget(name: "ScanProbe", dependencies: [.product(name: "SpaceSnifferScanEngine", package: "engine")], path: "Sources")
])
''')
  manifest={str(f.relative_to(work)):hashlib.sha256(f.read_bytes()).hexdigest() for f in work.rglob('*.swift')}
  subprocess.run(['swift','build','--package-path',str(work),'--scratch-path',str(work/'Build'),'-c','release','--product','ScanProbe'],check=True)
  binpath=subprocess.check_output(['swift','build','--package-path',str(work),'--scratch-path',str(work/'Build'),'-c','release','--show-bin-path'],text=True).strip()
  a.output.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(Path(binpath)/'ScanProbe',a.output)
  a.output.with_suffix('.sources.json').write_text(json.dumps({'sources':manifest,'binary_sha256':hashlib.sha256(a.output.read_bytes()).hexdigest(),'scope':'SPM release same-module Core/profile plus separately compiled static shared package; not directly pooled with old swiftc experiments'},indent=2)+'\n')
if __name__=='__main__':main()
