#!/usr/bin/env python3
"""Owned sparse HFS+ images mounted under a private fixture; no user mounts changed."""
import argparse,json,plistlib,shutil,subprocess,tempfile
from pathlib import Path

def cleanup(manifest):
    r=json.loads(manifest.read_text())
    for mount in reversed(r['mounts']):
        # Device numbers can be reused. Resolve the owned image, never blindly
        # detach a stale /dev/disk identifier from a previous partial cleanup.
        info=plistlib.loads(subprocess.check_output(['hdiutil','info','-plist']))
        def normalized(path):return path[8:] if path.startswith('/private/tmp/') else path
        matches=[image for image in info.get('images',[]) if normalized(image.get('image-path',''))==normalized(mount['image'])]
        if matches:
            devices=[entity['dev-entry'] for entity in matches[0].get('system-entities',[]) if 'dev-entry' in entity]
            if not devices:raise RuntimeError('owned image attached without a known device; keep fixture')
            device=mount.get('device') if mount.get('device') in devices else devices[0]
            proc=subprocess.run(['hdiutil','detach',device],capture_output=True,text=True)
            if proc.returncode:raise RuntimeError('detach failed; keep fixture intact: '+proc.stderr)
        mount['detached']=True
        manifest.write_text(json.dumps(r,indent=2)+'\n')
    root=Path(r['parent']);assert str(root).startswith('/private/tmp/sniffer-scope-native-')
    shutil.rmtree(root);r['removed']=not root.exists();manifest.write_text(json.dumps(r,indent=2)+'\n')

def main():
    parser=argparse.ArgumentParser();parser.add_argument('action',choices=['create','cleanup']);parser.add_argument('--manifest',type=Path,required=True)
    a=parser.parse_args()
    if a.action=='cleanup':cleanup(a.manifest);return
    assert not a.manifest.exists()
    assert shutil.disk_usage('/private/tmp').free>2*1024**3
    parent=Path(tempfile.mkdtemp(prefix='sniffer-scope-native-',dir='/private/tmp'));root=parent/'input';root.mkdir()
    r=dict(parent=str(parent),root=str(root),mounts=[],removed=False)
    def save():a.manifest.write_text(json.dumps(r,indent=2)+'\n')
    save()
    try:
        for i in range(4):(root/f'b{i}').mkdir()
        for i in range(100):(root/f'b{i%4}'/f'f{i:04}').write_bytes(b'abc')
        target=root/'foreign'
        for index in range(2):
            target.mkdir();image=parent/f'volume{index}.sparseimage'
            subprocess.run(['hdiutil','create','-size','64m','-fs','HFS+','-type','SPARSE','-volname',f'SnifferScope{index}',str(image)],check=True,capture_output=True)
            record=dict(path=str(target),device=None,image=str(image));r['mounts'].append(record);save()
            result=subprocess.run(['hdiutil','attach','-nobrowse','-mountpoint',str(target),'-plist',str(image)],check=True,capture_output=True)
            entities=plistlib.loads(result.stdout)['system-entities'];entry=next(e for e in entities if 'mount-point' in e)
            record['device']=entry['dev-entry'];save()
            branches=20 if index==0 else 10;count=5000 if index==0 else 1000
            for i in range(branches):(target/f'b{i}').mkdir()
            for i in range(count):(target/f'b{i%branches}'/f'f{i:05}').write_bytes(b'12345')
            target=target/'nested'
        r['expected']=dict(selected=dict(files=100,folders=5,logical=300,excluded=1),all=dict(files=6100,folders=37,logical=30300,excluded=0),foreign_selected=dict(files=5000,folders=21,logical=25000,excluded=1),nested_selected=dict(files=1000,folders=11,logical=5000,excluded=0));save();print(json.dumps(r,indent=2))
    except BaseException:
        cleanup(a.manifest);raise
if __name__=='__main__':main()
