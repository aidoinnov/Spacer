#!/usr/bin/env python3
"""Run metadata-only optimization probes sequentially; does not launch or scan the app."""
import argparse,hashlib,json,pathlib,re,statistics,subprocess
p=argparse.ArgumentParser();p.add_argument('--core-probe',required=True);p.add_argument('--mcp-probe',required=True);p.add_argument('--output',required=True);args=p.parse_args()
rows=[]
scenarios=[('navigation',[args.core_probe,'navigation','250000']),('export',[args.core_probe,'export','250000'])]
scenarios += [(f'queue-{n}',[args.core_probe,'queue',str(n)]) for n in (1000,2000,4000)]
scenarios += [(f'mcp-scope-{n}',[args.mcp_probe,str(n)]) for n in (0,100000,250000)]
for name,cmd in scenarios:
    samples=[]
    for run in range(3):
        r=subprocess.run(['/usr/bin/time','-l',*cmd],capture_output=True,text=True,check=True,timeout=55)
        value=json.loads(r.stdout)
        value['max_rss_bytes']=int(re.search(r'(\d+)\s+maximum resident set size',r.stderr).group(1));samples.append(value)
    summary={}
    for key,value in samples[0].items():
        if key.endswith('seconds'): summary[key]=statistics.median(s[key] for s in samples)
    if 'times' in samples[0]:summary['times']={k:statistics.median(s['times'][k] for s in samples) for k in samples[0]['times']}
    row={'name':name,'samples':samples,'median':summary,'max_rss_bytes':max(s['max_rss_bytes'] for s in samples)};rows.append(row)
    print(json.dumps({'name':name,'median':summary,'max_rss_mib':row['max_rss_bytes']/1048576}),flush=True)
files=[*pathlib.Path('Sources/SpaceSnifferCore').glob('*.swift'),*pathlib.Path('Sources/SpaceSnifferAutomation').glob('*.swift'),pathlib.Path('scripts/bench/optimization-audit.swift'),pathlib.Path('scripts/bench/mcp-query-audit.swift')]
result={'date':'2026-11-08','kind':'audit_only_no_shipped_changes','repeats':3,'timing':'monotonic wall time; metadata only; max RSS includes fixture construction and common cached inputs','compiler':subprocess.run(['swiftc','--version'],capture_output=True,text=True,check=True).stdout.strip(),'source_sha256':{str(f):hashlib.sha256(f.read_bytes()).hexdigest() for f in files},'rows':rows}
pathlib.Path(args.output).write_text(json.dumps(result,indent=2)+'\n')
