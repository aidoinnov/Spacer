#!/usr/bin/env python3
"""Independent SNS record fixture bytes for native adapter QA, not Windows capture."""
import argparse, base64, json, struct
from pathlib import Path

p = argparse.ArgumentParser(); p.add_argument('--output', required=True); a = p.parse_args()
out = Path(a.output); out.mkdir(parents=True, exist_ok=False)
def node(name, kind, logical, allocated, children=(), version=4):
    raw = base64.b64encode(name.encode('cp1252' if version == 2 else 'utf-16le'))
    size = struct.pack('<qi', logical, allocated-logical) if version == 2 else struct.pack('<qq', logical, allocated)
    return struct.pack('<BBI',version,kind,len(raw))+raw+size+struct.pack('<IQQQBB',16 if kind == 3 else 0,0,0,0,0,0)+b''.join(children)+b'\1\0'
children = [node('entry-%02d.bin'%i,2,i+1,4096) for i in range(24)]
root = node('/qa/first',3,300,24*4096,children)
second = node('/qa/second',3,7,4096,[node('second.txt',2,7,4096)])
(out/'single.sns').write_bytes(root)
(out/'multiple.sns').write_bytes(root+second)
(out/'legacy.sns').write_bytes(node('C:\\café',3,7,4096,[node('café.txt',2,7,4096,version=2)],version=2))
(out/'malformed.sns').write_bytes((root+second)[:-3])
(out/'single.DU').write_bytes(b'10 C:\\parent\r\n4 C:\\parent\\a\r\n6 C:\\parent\\b\r\n')
(out/'multiple.DU').write_bytes(b'1 C:\\first\r\n2 D:\\second\r\n')
(out/'legacy.DU').write_bytes(b'1 C:\\caf\xe9\r\n')
# Native v3 standalone XML with encoded UTF16LE template.
detail=base64.b64encode('<%pathfile%>{&br}'.encode('utf-16le')).decode()
(out/'export.xml').write_text('<exportConfig version="3"><description>QA paths</description><detailFormat>'+detail+'</detailFormat><blockSorting>files</blockSorting><fineSorting>name</fineSorting><fineSortingDirection>asc</fineSortingDirection></exportConfig>')
(out/'manifest.json').write_text(json.dumps({'scope':'independent synthetic record fixtures; not captured from Windows runtime','files':24,'roots':['/qa/first','/qa/second']},indent=2)+'\n')
print(out)
