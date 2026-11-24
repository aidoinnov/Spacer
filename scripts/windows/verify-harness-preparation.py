#!/usr/bin/env python3
"""Read-only artifact/source checks. NOT a PowerShell parser/runtime test."""
import hashlib,json,re
from pathlib import Path
root=Path(__file__).resolve().parents[2]
exe=root/'References/Windows/2.2.0.27/SpaceSniffer.exe'
out=root/'docs/validation/r-backlog-2026-11-09/windows-harness'
expected='192176a0ff46d84d27885e9d38e60157bc692eaf5d1e5b75ca56b3beaa0de7a6'
assert hashlib.sha256(exe.read_bytes()).hexdigest()==expected
origin=json.loads((out/'embedded-cli-help-origin.json').read_text())
raw=(out/'embedded-cli-help.bin').read_bytes()
assert exe.read_bytes()[origin['file_offset_start']:origin['file_offset_end_exclusive']]==raw
assert hashlib.sha256(raw).hexdigest()==origin['raw_sha256']
for token in ['help','scan "<path>"','load "<file>"','save "<path>"','export "<name>" "<path>"','autoclose','@parser=OS','@delim=X']:
 assert token.encode('ascii') in raw,token
script=(root/'scripts/windows/Invoke-SpaceSnifferRuntimeQA.ps1').read_text()
assert expected in script and "return '\"' + $Value + '\"'" in script
assert 'Invoke-Expression' not in script and 'Start-Process' not in script
# Basic delimiter sanity, explicitly weaker than Windows PowerShell AST parse.
for path in sorted((root/'scripts/windows').glob('*.ps1')):
 source=path.read_text();stack=[];i=0;quote=None;block=False
 while i<len(source):
  c=source[i]
  if block:
   if source[i:i+2]=='#>':block=False;i+=2
   else:i+=1
   continue
  if quote:
   if quote=='"' and c=='`':i+=2;continue
   if c==quote:
    if i+1<len(source) and source[i+1]==quote:i+=2;continue
    quote=None
   i+=1;continue
  if source[i:i+2]=='<#':block=True;i+=2;continue
  if c=='#':
   j=source.find('\n',i);i=len(source) if j<0 else j+1;continue
  if c in "'\"":quote=c
  elif c in '([{':stack.append(c)
  elif c in ')]}':assert stack and stack.pop()=={')':'(',']':'[','}':'{'}[c],(path,i)
  i+=1
 assert not stack and quote is None and not block,path
# Literal quote behavior model mirrors internal-parser contract, not PS execution.
def literal(value):
 if any(c in value for c in ['"','\r','\n']):raise ValueError()
 return '"'+value+'"'
assert literal('C:\\with space\\')=='"C:\\with space\\"'
assert literal('')=='""'
result={'status':'PREPARATION_CHECKS_PASS','frozen_exe_sha256':expected,'embedded_help_bytes_match':True,'powershell_ast_parse':'NOT_RUN_NO_POWERSHELL_HOST','windows_target_execution':'NOT_RUN_NO_WINDOWS_RUNTIME','scope':'literal artifact hashes/tokens + source delimiter sanity + quote model only; not script execution or runtime equivalence'}
(out/'preparation-check.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))
