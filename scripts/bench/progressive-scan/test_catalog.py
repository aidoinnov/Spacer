#!/usr/bin/env python3
"""Real APFS catalog field oracle on an explicit disposable fixture volume."""
import argparse
import ctypes as C
import json
import os
import shutil
import stat
import tempfile
from pathlib import Path
from catalog import scan


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('volume',type=Path)
    args=parser.parse_args()
    root=Path(tempfile.mkdtemp(prefix='catalog-field-oracle-',dir=args.volume))
    try:
        (root/'branch'/'deep').mkdir(parents=True)
        for name,body in [('zero',b''),('one',b'1'),('.hidden',b'2'),('한글-😀-cafe\u0301',b'3')]:
            (root/'branch'/name).write_bytes(body)
        os.link(root/'branch'/'one',root/'alias')
        (root/'broken').symlink_to('missing')
        (root/'cycle').symlink_to('.')
        (root/'fifo').parent.mkdir(exist_ok=True)
        os.mkfifo(root/'fifo')
        with (root/'sparse').open('wb') as f: f.truncate(8*1024*1024)
        (root/'fork').write_bytes(b'data')
        lib=C.CDLL('/usr/lib/libSystem.B.dylib',use_errno=True)
        lib.setxattr.argtypes=[C.c_char_p,C.c_char_p,C.c_void_p,C.c_size_t,C.c_uint32,C.c_int]
        fork=C.create_string_buffer(b'r'*8192)
        assert lib.setxattr(os.fsencode(root/'fork'),b'com.apple.ResourceFork',fork,8192,0,0)==0, C.get_errno()
        os.chmod(root/'branch'/'.hidden',0o444)
        before={}
        def walk(path):
            info=path.lstat(); before[str(path)]=info
            if stat.S_ISDIR(info.st_mode):
                for child in path.iterdir(): walk(child)
        walk(root)
        result=scan(str(args.volume),timeout=15)
        directories={record['inode']:record for record in result['records'] if record['kind']==2}
        root_id=root.stat().st_ino
        def relative(record):
            parts=[record['name']]; parent=record['parent']; visited=set()
            while parent!=root_id:
                if parent in visited or parent not in directories: return None
                visited.add(parent); directory=directories[parent]
                parts.append(directory['name']); parent=directory['parent']
            return root.joinpath(*reversed(parts))
        actual={}
        for record in result['records']:
            path=relative(record)
            if path is None: continue
            key=str(path)
            assert key not in actual, f'duplicate path {key}'
            actual[key]=record
        expected=set(before)-{str(root)}
        assert set(actual)==expected, dict(missing=list(expected-set(actual)),extra=list(set(actual)-expected))
        mismatches=[]
        for key,r in actual.items():
            info=before[key]
            kind=2 if stat.S_ISDIR(info.st_mode) else 1 if stat.S_ISREG(info.st_mode) else 5 if stat.S_ISLNK(info.st_mode) else 7
            regular=stat.S_ISREG(info.st_mode)
            truth=dict(device=info.st_dev,inode=info.st_ino,parent=Path(key).parent.stat().st_ino,
                       kind=kind,flags=info.st_flags,logical=info.st_size if regular else 0,
                       allocated=info.st_blocks*512 if regular else 0)
            for field,value in truth.items():
                if r[field]!=value: mismatches.append(dict(path=str(Path(key).relative_to(root)),field=field,expected=value,actual=r[field]))
        output=dict(status='pass' if not mismatches else 'failed',entries=len(actual),mismatches=mismatches,
                    scope='isolated fixture field oracle, aliases/symlinks/FIFO/Unicode/sparse/resource fork; not full app or volume benchmark')
        print(json.dumps(output,ensure_ascii=False))
        return 0 if not mismatches else 1
    finally:
        shutil.rmtree(root)


if __name__=='__main__': raise SystemExit(main())
