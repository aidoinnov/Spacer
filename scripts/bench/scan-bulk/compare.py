#!/usr/bin/env python3
"""Alternating ordered/POSIX release scans. Own fixtures; no cold-cache claim."""
import argparse, hashlib, json, math, os, platform, random, shutil, statistics, subprocess, tempfile, time
from pathlib import Path

def percentile(values, q):
    return sorted(values)[max(0, math.ceil(len(values)*q)-1)]

def ci(values):
    rng = random.Random(20261119)
    samples = [statistics.median(rng.choices(values, k=len(values))) for _ in range(2000)]
    return [percentile(samples, .025), percentile(samples, .975)]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary', type=Path, required=True)
    parser.add_argument('--baseline', type=Path, help='optional frozen historical POSIX binary')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--pairs', type=int, default=20)
    parser.add_argument('--mode', choices=['ordered','automatic'], default='ordered')
    parser.add_argument('--scenarios', nargs='+', choices=['small1000','normal10000','wide4100','wide100000','overbudget131073','denied20','deep200','tinyfolders1000'],
                        default=['small1000','normal10000','wide4100','wide100000','overbudget131073','denied20'])
    args = parser.parse_args()
    if args.pairs < 1 or os.getuid() == 0: parser.error('positive pairs and non-root required')
    if args.output.exists(): parser.error('refusing overwrite')
    if shutil.disk_usage('/private/tmp').free < 2*1024**3: parser.error('2 GiB reserve required')
    args.output.parent.mkdir(parents=True, exist_ok=True)
    report = dict(started_at=time.time(), os=platform.platform(), uid=os.getuid(), pairs=args.pairs, planned_scenarios=args.scenarios,
                  scope='fresh process; shared host; warm/unknown OS metadata cache; engine completion, not GUI',
                  variants={}, rows=[], summary={})
    variants = [('posix', args.binary.resolve(), 'posix'), ('ordered', args.binary.resolve(), args.mode)]
    if args.baseline: variants.append(('original', args.baseline.resolve(), 'posix'))
    for name, binary, mode in variants:
        report['variants'][name] = dict(path=str(binary), mode=mode, sha256=hashlib.sha256(binary.read_bytes()).hexdigest())
    def save():
        tmp=args.output.with_suffix('.tmp'); tmp.write_text(json.dumps(report, indent=2)+'\n'); tmp.replace(args.output)
    root=Path(tempfile.mkdtemp(prefix='sniffer-bulk-')); denied=[]
    save() # fixed plan, variants and sample count recorded before the first scan
    try:
        for scenario in args.scenarios:
            path=root/scenario; path.mkdir()
            count={'small1000':1000,'normal10000':10000,'wide4100':4100,'wide100000':100000,'overbudget131073':131073,'denied20':1,'deep200':200,'tinyfolders1000':1000}[scenario]
            folders={'small1000':50,'normal10000':100,'deep200':200,'tinyfolders1000':1000}.get(scenario,0)
            branches=[]
            for i in range(folders):
                folder=(branches[-1]/'d' if branches else path/'d') if scenario=='deep200' else path/f'b{i:03}'
                folder.mkdir();branches.append(folder)
            if scenario=='denied20':
                for i in range(20):
                    folder=path/f'denied{i:02}';folder.mkdir();folder.chmod(0);denied.append(folder)
            allocated=logical=0
            for i in range(count):
                file=(branches[i%folders] if folders else path)/f'f{i:06}'
                file.write_bytes(b'x'*(1+i%100)); value=file.stat()
                allocated+=value.st_blocks*512;logical+=value.st_size
            expected=dict(files=count,folders=folders+1+(20 if scenario=='denied20' else 0),issue_count=20 if scenario=='denied20' else 0,
                          allocated_bytes=allocated,logical_bytes=logical,cancelled=False)
            for pair in range(args.pairs):
                order=variants[pair%len(variants):]+variants[:pair%len(variants)]
                paired=[]
                for name,binary,mode in order:
                    row=dict(scenario=scenario,pair=pair,variant=name)
                    try:
                        proc=subprocess.run([str(binary),mode,str(path)],capture_output=True,text=True,timeout=60)
                        row['exit_status']=proc.returncode
                        if proc.returncode:row.update(status='failed',error=proc.stderr[-2000:])
                        else:
                            row.update(json.loads(proc.stdout))
                            row['status']='ok' if all(row[k]==v for k,v in expected.items()) else 'oracle_mismatch'
                    except (subprocess.TimeoutExpired,json.JSONDecodeError) as exc:row.update(status='failed',error=str(exc))
                    paired.append(row);report['rows'].append(row)
                same=all(r['status']=='ok' for r in paired) and len({r['digest'] for r in paired})==1
                for row in paired:row['pair_equal']=same
                save(); print(scenario,pair+1,flush=True)
            cell=dict(expected=expected,variants={},comparisons={})
            for name,_,_ in variants:
                rows=[r for r in report['rows'] if r['scenario']==scenario and r['variant']==name and r['status']=='ok' and r['pair_equal']]
                cell['variants'][name]=dict(valid=len(rows),metrics={})
                for metric in ['scan_complete_ms','cpu_seconds','peak_rss_mib','metadata_requests_per_entry']:
                    values=[r[metric] for r in rows]
                    cell['variants'][name]['metrics'][metric]=dict(p50=statistics.median(values),p95=percentile(values,.95)) if values else None
            for baseline in ['posix']+(['original'] if args.baseline else []):
                before={r['pair']:r for r in report['rows'] if r['scenario']==scenario and r['variant']==baseline and r['status']=='ok' and r['pair_equal']}
                after={r['pair']:r for r in report['rows'] if r['scenario']==scenario and r['variant']=='ordered' and r['status']=='ok' and r['pair_equal']}
                changes=[100*(r['scan_complete_ms']-after[p]['scan_complete_ms'])/r['scan_complete_ms'] for p,r in before.items() if p in after]
                if not changes:continue
                b=cell['variants'][baseline]['metrics'];a=cell['variants']['ordered']['metrics']
                gates=dict(valid=len(changes)==args.pairs,
                    latency=all(a['scan_complete_ms'][q]<=b['scan_complete_ms'][q]*1.1 for q in ['p50','p95']),
                    paired_ci_margin=ci(changes)[0]>=-10,
                    cpu=a['cpu_seconds']['p95']<=b['cpu_seconds']['p95']*1.2,
                    rss=a['peak_rss_mib']['p95']<=max(b['peak_rss_mib']['p95']*1.1,b['peak_rss_mib']['p95']+32))
                if scenario=='denied20':gates['denied_p95']=a['scan_complete_ms']['p95']<=200
                cell['comparisons'][baseline]=dict(paired_improvement_pct=statistics.median(changes),ci95=ci(changes),gates=gates,passed=all(gates.values()))
            report['summary'][scenario]=cell;save()
            # Release only our scenario tree; restore denied permissions before removal.
            for directory in denied:
                if directory.exists():directory.chmod(0o700)
            shutil.rmtree(path)
        report['status']='measured'
    finally:
        for directory in denied:
            if directory.exists():directory.chmod(0o700)
        shutil.rmtree(root);report['cleanup']=dict(path=str(root),exists_after=root.exists());save()
    return 0 if all(r['status']=='ok' and r['pair_equal'] for r in report['rows']) else 1

if __name__=='__main__':raise SystemExit(main())
