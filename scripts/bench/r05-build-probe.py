#!/usr/bin/env python3
"""Build an isolated, source-frozen prototype. No production files are edited."""
import argparse,hashlib,json,os,shutil,subprocess
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--output',required=True);a=p.parse_args()
out=Path(a.output);out.mkdir(parents=True,exist_ok=False)
sources=sorted(Path('Sources/SpaceSnifferCore').glob('*.swift'))
scripts=[Path('scripts/bench/r05-focus-extension.swift'),Path('scripts/bench/r05-focus-probe.swift'),Path(__file__).resolve().relative_to(Path.cwd())]
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
archive=out/'source-archive';manifest={}
for f in sources+scripts+[Path('Package.swift')]:
 target=archive/f;target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(f,target);manifest[str(f)]=sha(f)
core=archive/'Sources/SpaceSnifferCore';filter_path=out/'generated/Filter.swift';filter_path.parent.mkdir()
filter_path.write_text((core/'Filter.swift').read_text()+'\n'+(archive/scripts[0]).read_text())
probe=out/'r05-probe'
command=['swiftc','-swift-version','6','-O','-g','-whole-module-optimization']+[str(filter_path if p.name=='Filter.swift' else p) for p in sorted(core.glob('*.swift'))]+[str(archive/scripts[1]),'-o',str(probe)]
result=subprocess.run(command,capture_output=True,text=True)
(out/'build.stdout').write_text(result.stdout);(out/'build.stderr').write_text(result.stderr)
assert result.returncode==0,result.stderr
version=subprocess.check_output(['swiftc','--version'],text=True)
record={'scope':'all frozen Core source, with test-only extension appended to Filter.swift for private-field access; no production linkage','source_sha256':manifest,'generated_filter':str(filter_path),'generated_filter_sha256':sha(filter_path),'probe_sha256':sha(probe),'command':command,'swift_version':version}
(out/'build-manifest.json').write_text(json.dumps(record,indent=2)+'\n')
print(json.dumps({'probe':str(probe),'source_files':len(sources),'sha256':sha(probe)}))
