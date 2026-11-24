#!/usr/bin/env python3
"""Bounded-memory metadata audit; never constructs the full SNS node tree."""
import argparse,base64,collections,hashlib,json,os,struct,time
from pathlib import Path

p=argparse.ArgumentParser();p.add_argument('input',type=Path);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
start=time.monotonic();identity=a.input.stat();input_size=identity.st_size;digest=hashlib.sha256();offset=0;stack=[];roots=[];kinds=collections.Counter();versions=collections.Counter();path_hist=collections.Counter();name_hist=collections.Counter();child_hist=collections.Counter()
totals=collections.Counter();maximum_path=0;maximum_depth=0;maximum_children=0;nodes=0
def read(f,n):
 global offset
 value=f.read(n)
 if len(value)!=n:raise ValueError(('truncated',offset,n,len(value)))
 offset+=n;digest.update(value);return value
def bucket(n):return 0 if n==0 else 1<<(n.bit_length()-1)
with a.input.open('rb',buffering=1024*1024) as f:
 while offset<input_size:
  version,kind=read(f,2)
  if version not in [1,3,4]:raise ValueError(('audit does not guess v2 ACP',version,offset))
  versions[version]+=1
  if kind==0:
   if not stack:raise ValueError(('unbalanced end',offset))
   parent=stack.pop();children=parent['children'];maximum_children=max(maximum_children,children);child_hist[bucket(children)]+=1
   continue
  if kind not in range(1,7):raise ValueError(('type',kind,offset))
  length=struct.unpack('<I',read(f,4))[0]
  if not 0<length<=8192:raise ValueError(('name length',length,offset))
  raw=read(f,length);name=raw.decode('utf-8') if version==1 else base64.b64decode(raw,validate=True).decode('utf-16le')
  if not name or '\0' in name:raise ValueError(('name',offset))
  utf8=len(name.encode('utf-8'));utf16=len(name.encode('utf-16le'))
  payload=read(f,46 if version==4 else 42);logical=struct.unpack_from('<q',payload)[0];allocated=struct.unpack_from('<q' if version==4 else '<i',payload,8)[0]
  if version<4:allocated+=logical
  if logical<0 or allocated<0:raise ValueError(('negative',offset))
  if stack:
   parent=stack[-1]
   if parent['kind'] not in [1,3]:raise ValueError(('non-directory parent',offset))
   parent['children']+=1;path_bytes=parent['path_bytes']+(0 if parent['ends_separator'] else 1)+utf8
   # Child segments cannot end with a path separator in the scanner fixture.
   windows=parent['windows'];ends=name.endswith('\\' if windows else '/')
  else:
   if not(name.startswith('/') or name.startswith('\\\\') or len(name)>1 and name[1]==':'):raise ValueError(('relative root',offset))
   windows=name.startswith('\\\\') or len(name)>1 and name[1]==':';ends=name.endswith('\\' if windows else '/')
   path_bytes=utf8;roots.append({'path':name,'logical_bytes':logical,'allocated_bytes':allocated})
  # Store only depth-local lengths, kind and child count, not all paths/names.
  stack.append({'path_bytes':path_bytes,'ends_separator':ends,'windows':windows,'kind':kind,'children':0})
  nodes+=1;kinds[kind]+=1;maximum_depth=max(maximum_depth,len(stack));maximum_path=max(maximum_path,path_bytes)
  path_hist[bucket(path_bytes)]+=1;name_hist[bucket(utf8)]+=1
  totals['encoded_name_bytes']+=length;totals['decoded_name_utf8_bytes']+=utf8;totals['decoded_name_utf16_bytes']+=utf16;totals['reconstructed_full_path_utf8_bytes']+=path_bytes
  # Swift small String representation threshold is a model, not malloc/RSS accounting.
  totals['names_over_15_utf8_bytes']+=utf8>15;totals['paths_over_15_utf8_bytes']+=path_bytes>15
  if len(stack)>1:totals['nonroot_name_utf8_bytes']+=utf8
  if kind==2:totals['file_logical_sum']+=logical;totals['file_allocated_sum']+=allocated
if stack:raise ValueError(('unterminated',len(stack)))
after=a.input.stat()
if after.st_size!=input_size or after.st_mtime_ns!=identity.st_mtime_ns:raise ValueError('input changed during audit')
report={'scope':'one-pass SNS record audit, O(depth) stack; raw UTF8 payload and structural counts are not measured Swift heap/RSS. Full paths are counted by byte length, never all retained. No target execution, tree model, filesystem scan, source modification or claim of compressed-path speed.',
 'input':str(a.input),'input_bytes':offset,'input_sha256':digest.hexdigest(),'seconds':time.monotonic()-start,'nodes':nodes,'roots':roots,'types':dict(kinds),'versions_including_end_records':dict(versions),'totals':dict(totals),
 'maximum_depth':maximum_depth,'maximum_path_utf8_bytes':maximum_path,'maximum_children':maximum_children,'path_length_floor_power2_histogram':dict(sorted(path_hist.items())),'name_length_floor_power2_histogram':dict(sorted(name_hist.items())),'children_floor_power2_histogram':dict(sorted(child_hist.items())),
 'structural_model':{'int_id_parent_bytes_at_8_each':nodes*16,'child_edges_at_8_bytes':max(0,nodes-len(roots))*8,'note':'Numeric payload estimate only; excludes DiskNode inline layout, COW page arrays, String heap headers/capacity/sharing, dictionary/allocator/ARC overhead, UI/readers and transient decoder bridges. Segment storage would still need parent traversal/path materialization.'}}
a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print(json.dumps({'nodes':nodes,'sha256':report['input_sha256'],'path_utf8_bytes':totals['reconstructed_full_path_utf8_bytes'],'name_utf8_bytes':totals['decoded_name_utf8_bytes'],'seconds':report['seconds']}))
