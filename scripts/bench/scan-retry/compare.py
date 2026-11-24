#!/usr/bin/env python3
"""V01 only: alternating immutable before/after release binaries, own fixtures."""
import argparse, hashlib, json, math, os, platform, random, shutil, statistics, subprocess, tempfile, time
from pathlib import Path


def percentile(xs, q): return sorted(xs)[max(0, math.ceil(len(xs)*q)-1)] if xs else None

def interval(values):
    if not values: return None
    rng=random.Random(20261119)
    samples=[statistics.median(rng.choices(values,k=len(values))) for _ in range(2000)]
    return [percentile(samples,.025),percentile(samples,.975)]


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--before',type=Path,required=True)
    parser.add_argument('--after',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--pairs',type=int,default=20)
    parser.add_argument('--scenarios',nargs='+',choices=['denied20','normal-10000'],default=['denied20','normal-10000'])
    args=parser.parse_args()
    if args.pairs<1: parser.error('pairs must be positive')
    if os.getuid()==0: parser.error('permission fixture must not run as root')
    if args.output.exists(): parser.error('refusing overwrite')
    if shutil.disk_usage('/private/tmp').free < 1024**3: parser.error('1 GiB free reserve required')
    args.output.parent.mkdir(parents=True,exist_ok=True)
    root=Path(tempfile.mkdtemp(prefix='sniffer-v01-'))
    denied=[]
    report=dict(scope='V01 POSIX backend only; fresh processes/warm OS metadata; same source except retry extraction and cancellation wait; shared host; scan-only timer, RSS sampled before checksum',
                os=platform.platform(),uid=os.getuid(),started_at=time.time(),pairs=args.pairs,
                binaries={name:dict(path=str(p),sha256=hashlib.sha256(p.read_bytes()).hexdigest()) for name,p in [('before',args.before),('after',args.after)]},rows=[],summary={})
    def save():
        tmp=args.output.with_suffix('.json.tmp');tmp.write_text(json.dumps(report,indent=2)+'\n');tmp.replace(args.output)
    try:
        for scenario in args.scenarios:
            path=root/scenario;path.mkdir()
            if scenario=='denied20':
                for i in range(20):
                    directory=path/f'denied{i:02}';directory.mkdir();directory.chmod(0);denied.append(directory)
                (path/'readable.bin').write_bytes(b'abc')
            else:
                for i in range(10000):
                    folder=path/f'b{i%100:03}';folder.mkdir(exist_ok=True)
                    (folder/f'f{i:05}').write_bytes(b'x'*(1+i%100))
            readable_files=[path/'readable.bin'] if scenario=='denied20' else [p for folder in path.iterdir() for p in folder.iterdir()]
            expected_bytes=sum(p.stat().st_blocks*512 for p in readable_files)
            expected_logical=sum(p.stat().st_size for p in readable_files)
            expected_files=1 if scenario=='denied20' else 10000
            expected_folders=21 if scenario=='denied20' else 101
            expected_issues=20 if scenario=='denied20' else 0
            for pair in range(args.pairs):
                paired=[]
                for name in (['before','after'] if pair%2==0 else ['after','before']):
                    row=dict(scenario=scenario,pair=pair,variant=name)
                    try:
                        proc=subprocess.run([str(getattr(args,name).resolve()),'posix',str(path)],capture_output=True,text=True,timeout=20)
                        row['exit_status']=proc.returncode
                        if proc.returncode:row.update(status='failed',error=proc.stderr[-2000:])
                        else:
                            data=json.loads(proc.stdout);row.update(data)
                            row['status']='ok' if data['files']==expected_files and data['folders']==expected_folders and data['issue_count']==expected_issues and data['allocated_bytes']==expected_bytes and data['logical_bytes']==expected_logical and not data['cancelled'] else 'oracle_mismatch'
                    except (subprocess.TimeoutExpired,json.JSONDecodeError) as exc:row.update(status='failed',error=str(exc))
                    report['rows'].append(row);paired.append(row)
                if all(r['status']=='ok' for r in paired):
                    same=all(paired[0][key]==paired[1][key] for key in ['digest','files','folders','allocated_bytes','logical_bytes','issue_count','cancelled'])
                    for row in paired:row['pair_equal']=same
                else:
                    for row in paired:row['pair_equal']=False
                save()
                print(scenario,pair+1,flush=True)
            cell={}
            for name in ['before','after']:
                rows=[r for r in report['rows'] if r['scenario']==scenario and r['variant']==name and r['status']=='ok' and r['pair_equal']]
                cell[name]={'valid':len(rows),'metrics':{}}
                for metric in ['scan_complete_ms','peak_rss_mib','cpu_seconds']:
                    values=[r[metric] for r in rows]
                    cell[name]['metrics'][metric]=dict(p50=statistics.median(values) if values else None,p95=percentile(values,.95))
            by_variant={v:{r['pair']:r for r in report['rows'] if r['scenario']==scenario and r['variant']==v and r['status']=='ok' and r['pair_equal']} for v in ['before','after']}
            changes=[(r['scan_complete_ms']-by_variant['after'][pair]['scan_complete_ms'])/r['scan_complete_ms']*100 for pair,r in by_variant['before'].items() if pair in by_variant['after']]
            cell['paired_improvement_pct']=statistics.median(changes) if changes else None
            cell['paired_ci95']=interval(changes)
            cell['expected']=dict(files=expected_files,folders=expected_folders,issues=expected_issues,allocated_bytes=expected_bytes,logical_bytes=expected_logical)
            cell['retry_after']=[{key:r['enumeration_io'].get(key) for key in ['openDirectoryCalls','openRetryDecisions','requestedRetryDelaySeconds']} for r in by_variant['after'].values()]
            report['summary'][scenario]=cell;save()
        report['status']='measured'
    finally:
        for p in denied:
            if p.exists():p.chmod(0o700)
        shutil.rmtree(root)
        report['cleanup']=dict(owned_fixture=str(root),exists_after=root.exists());save()
    print(json.dumps(report['summary'],indent=2))
    return 0 if all(r['status']=='ok' and r['pair_equal'] for r in report['rows']) else 1


if __name__=='__main__':raise SystemExit(main())
