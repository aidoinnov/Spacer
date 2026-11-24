#!/usr/bin/env python3
"""Owned physical fixtures, independent POSIX oracle, alternating release pairs.

Engine callback timings are explicitly separate from future GUI gates. No sudo,
cache purge, user file deletion, or Spotlight reindexing. JSON contains all runs.
"""
import argparse
import hashlib
import errno
import json
import math
import os
import platform
import random
import resource
import shutil
import stat
import statistics
import subprocess
import sys
import tempfile
import time
from pathlib import Path

sys.dont_write_bytecode = True
from catalog import CatalogFailure, scan as catalog_scan

REPO = Path(__file__).resolve().parents[3]
SCENARIOS = ['S01', 'S02', 'S03-4095', 'S03-4096', 'S03-4097', 'S03-4100', 'S03-100000', 'S04', 'S05', 'S06', 'S07']


def percentile(values, q):
    return sorted(values)[max(0, math.ceil(q * len(values))-1)] if values else None


def ci(values):
    if not values:
        return None
    rng = random.Random(20261116)
    medians = [statistics.median(rng.choices(values, k=len(values))) for _ in range(2000)]
    return [percentile(medians, .025), percentile(medians, .975)]


def oracle(root):
    """Independent os.scandir/lstat oracle; same regular/link accounting contract."""
    digest = hashlib.sha256()
    rows, groups = [], {}
    files = folders = allocated = logical = 0
    def walk(path):
        nonlocal files, folders, allocated, logical
        info = path.lstat()
        if stat.S_ISLNK(info.st_mode):
            return
        directory, regular = stat.S_ISDIR(info.st_mode), stat.S_ISREG(info.st_mode)
        relative = '.' if path == root else path.relative_to(root).as_posix()
        size = info.st_size if regular else 0
        blocks = info.st_blocks * 512 if regular else 0
        flags = 0x10 if directory else 0
        if info.st_mode & 0o222 == 0: flags |= 1
        if path.name.startswith('.') or info.st_flags & 0x8000: flags |= 2
        if info.st_flags & 0x20: flags |= 0x800
        if regular and size > blocks: flags |= 0x200
        line = f'{relative}\t{int(directory)}\t{info.st_dev}:{info.st_ino}\t{size}\t{blocks}\t{flags}\t{int(info.st_mtime)}\n'
        rows.append((str(path), line))
        if directory:
            folders += 1
            if path.parent == root: groups[path.name] = 0
            for child in sorted(path.iterdir()): walk(child)
        else:
            files += 1; allocated += blocks; logical += size
            parts = path.relative_to(root).parts
            if len(parts) > 1: groups[parts[0]] = groups.get(parts[0], 0) + blocks
    walk(root)
    for _, line in sorted(rows): digest.update(line.encode())
    return dict(files=files, folders=folders, allocated_bytes=allocated,
                logical_bytes=logical, digest=digest.hexdigest(), groups=groups)


def make_fixture(root, scenario, backing_parent=None):
    root.mkdir()
    created = 0
    def file(path, size=1):
        nonlocal created
        if created % 256 == 0:
            if shutil.disk_usage(root).free < 64*1024**2:
                raise OSError(errno.ENOSPC, 'fixture volume reserve reached')
            if backing_parent and shutil.disk_usage(backing_parent).free < 1024**3:
                raise OSError(errno.ENOSPC, 'backing filesystem 1 GiB reserve reached')
        created += 1
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open('wb') as f:
            # Real blocks, never ftruncate a supposedly large physical file.
            block = b'x' * min(size, 1024*1024)
            remaining = size
            while remaining:
                if size >= 1024*1024 and backing_parent and shutil.disk_usage(backing_parent).free < 1024**3:
                    raise OSError(errno.ENOSPC, 'backing filesystem reserve reached while writing large file')
                written = min(len(block), remaining)
                f.write(block[:written]); remaining -= written
    if scenario == 'S01':
        for i in range(1000): file(root/f'b{i%50:03}'/f'f{i:06}')
    elif scenario == 'S02':
        for i in range(100000): file(root/f'b{i%5000:04}'/f'f{i:06}')
    elif scenario.startswith('S03-'):
        for i in range(int(scenario.split('-')[1])): file(root/f'f{i:06}')
    elif scenario == 'S04':
        current = root
        for depth in range(64):
            current /= f'd{depth:02}'
            for i in range(16): file(current/f'f{i:02}')
        file(current/'large', 32*1024*1024)
    elif scenario in ('S05','S06'):
        # Big branch lexicographically first/last distinguishes DFS order bias.
        large_name = 'aaa-large' if scenario == 'S05' else 'zzz-large'
        for i in range(99990): file(root/f'mid-{i%20:02}'/f'f{i:06}', 4096)
        for i in range(10): file(root/large_name/f'big{i:02}', 32*1024*1024)
    elif scenario == 'S07':
        for i in range(90000): file(root/'a-heavy'/f'f{i:06}')
        for i in range(10000): file(root/f'light-{i%20:02}'/f'f{i:06}')
    else:
        raise ValueError(scenario)


def evaluate(row, expected):
    checks = {key: row.get(key) == expected[key] for key in ('files','folders','allocated_bytes','logical_bytes','digest')}
    row['oracle_checks'] = checks
    row['accurate'] = all(checks.values()) and row.get('issue_count') == 0 and not row.get('cancelled')
    group_truth = expected['groups']
    top = sorted(group_truth, key=lambda name: (-group_truth[name], name))[:10]
    denominator = sum(group_truth[n] for n in top)
    samples = []
    for sample in row.get('publications', []):
        groups = sample['groups']
        ranked = sorted(groups, key=lambda name: (-groups[name], name))[:len(top)]
        recall = len(set(top) & set(ranked))/len(top) if top else None
        error = sum(abs(groups.get(n,0)-group_truth[n]) for n in top)/denominator if denominator else None
        coverage = sample['observed_bytes']/expected['allocated_bytes'] if expected['allocated_bytes'] else None
        samples.append(dict(elapsed_ms=sample['elapsed_ms'], recall=recall, byte_error=error, coverage=coverage))
    row['quality_samples'] = samples
    useful = [s['elapsed_ms'] for i,s in enumerate(samples)
              if top and all(x['recall'] >= .9 and x['byte_error'] <= .2 and x['coverage'] >= .7
                             for x in samples[i:])]
    # Publications can stop before the final one-second hold elapses. Final
    # correct data is stable on these static fixtures; runner does not invent a
    # GUI draw/hold observation. Name the engine proxy explicitly.
    row['useful_callback_proxy_ms'] = min(useful) if useful else None
    row['quality_at'] = {}
    for seconds in (2,5,10):
        eligible = [s for s in samples if s['elapsed_ms'] <= seconds*1000]
        if eligible: row['quality_at'][str(seconds)] = eligible[-1]
        else: row['quality_at'][str(seconds)] = dict(recall=0 if top else None,byte_error=1 if denominator else None,coverage=0)


def summarize(rows):
    output = {}
    for scenario in sorted({r['scenario'] for r in rows}):
        output[scenario] = {}
        base = {r['pair']: r for r in rows if r['scenario']==scenario and r['mode']=='posix' and r['status']=='ok'}
        for mode in ('posix','bulk','stream'):
            selected = [r for r in rows if r['scenario']==scenario and r['mode']==mode]
            valid = [r for r in selected if r['status']=='ok' and r['accurate']]
            summary = dict(attempts=len(selected), valid=len(valid), failures=len(selected)-len(valid), metrics={})
            for metric in ('scan_complete_ms','useful_callback_proxy_ms','peak_rss_mib','cpu_seconds'):
                values = [r[metric] for r in valid if r.get(metric) is not None]
                changes = [(base[r['pair']][metric]-r[metric])/base[r['pair']][metric]*100
                           for r in valid if r['pair'] in base and base[r['pair']].get('accurate')
                           and r.get(metric) is not None and base[r['pair']].get(metric)]
                summary['metrics'][metric] = dict(n=len(values),p50=statistics.median(values) if values else None,
                    p95=percentile(values,.95),paired_improvement_pct=statistics.median(changes) if changes else None,
                    paired_improvement_ci95=ci(changes))
            summary['gate'] = 'pending_GUI_and_full_matrix'
            output[scenario][mode] = summary
    return output


def catalog_probe(volume, root, expected):
    start_usage = resource.getrusage(resource.RUSAGE_SELF)
    try:
        result = catalog_scan(str(volume), timeout=30)
        # Resolve the selected folder using IDs, with no per-file path syscall.
        root_id = root.stat().st_ino
        directories = {r['inode']:r for r in result['records'] if r['kind']==2}
        def below(parent):
            visited=set()
            while parent != root_id:
                if parent in visited or parent not in directories: return False
                visited.add(parent); parent=directories[parent]['parent']
            return True
        chosen = [r for r in result['records'] if r['name'] not in ('.','..') and below(r['parent'])]
        regular = [r for r in chosen if r['kind']==1]
        actual = dict(files=sum(r['kind']!=2 and r['kind']!=5 for r in chosen),
                      folders=1+sum(r['kind']==2 for r in chosen),
                      logical_bytes=sum(r['logical'] for r in regular),
                      allocated_bytes=sum(r['allocated'] for r in regular))
        checks = {key:actual[key]==expected[key] for key in actual}
        return dict(status='ok',scan_complete_ms=result['scan_complete_ms'],calls=result['calls'],
                    volume_records=len(result['records']),selected=actual,oracle_checks=checks,
                    accurate=all(checks.values()),scope='full volume catalog + final totals; no GUI or early quality claim')
    except (CatalogFailure, OSError, ValueError, UnicodeError) as exc:
        return dict(status='failed',error=str(exc))


def markdown(report):
    lines=['# Progressive scan engine measurements','',
           'Engine callback measurements only. GUI, cache, live convergence gates remain pending.', '',
           '| Scenario | Mode | n / failures | scan p50 / p95 ms | paired improvement % | RSS p50 MiB | oracle |',
           '|---|---|---:|---:|---:|---:|---|']
    def number(x): return 'N/A' if x is None else f'{x:.2f}'
    for scenario,modes in report['summary'].items():
        for mode,s in modes.items():
            m=s['metrics']['scan_complete_ms']; rss=s['metrics']['peak_rss_mib']
            lines.append(f"| {scenario} | {mode} | {s['valid']} / {s['failures']} | {number(m['p50'])} / {number(m['p95'])} | {number(m['paired_improvement_pct'])} | {number(rss['p50'])} | {'pass' if s['valid'] and not s['failures'] else 'failed/pending'} |")
    lines += ['', 'Detailed paired confidence intervals and callback quality samples: `report.json`.', '',
              'Catalog probes (separate experiment; not a fair language-to-language speed comparison):','']
    for fixture in report['fixtures']:
        if 'catalog' in fixture: lines.append(f"- {fixture['scenario']}: `{json.dumps(fixture['catalog'],ensure_ascii=False)}`")
    return '\n'.join(lines)+'\n'


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--fixture-parent',type=Path,default=Path('/private/tmp'))
    parser.add_argument('--catalog-volume',type=Path)
    parser.add_argument('--backing-parent',type=Path,default=Path('/private/tmp'),help='physical backing filesystem reserve check (important for sparse images)')
    parser.add_argument('--pairs',type=int,default=5)
    parser.add_argument('--scenarios',nargs='+',choices=SCENARIOS,default=SCENARIOS)
    args=parser.parse_args()
    if args.pairs<1: parser.error('pairs must be positive')
    args.output.mkdir(parents=True,exist_ok=True)
    target=args.output/'report.json'
    if target.exists(): parser.error('refusing to overwrite an existing run')
    args.fixture_parent.mkdir(parents=True,exist_ok=True)
    required=1024**3 if any(s in args.scenarios for s in ('S05','S06')) else 700*1024**2
    free=shutil.disk_usage(args.fixture_parent).free
    backing_free=shutil.disk_usage(args.backing_parent).free
    if free<required or backing_free<required+1024**3:
        target.write_text(json.dumps(dict(status='skipped',reason='insufficient fixture/backing space including 1 GiB reserve',free=free,backing_free=backing_free,required=required),indent=2))
        return 2
    root=Path(tempfile.mkdtemp(prefix='sniffer-progressive-',dir=args.fixture_parent))
    report=dict(schema_version=1,scope='engine only, warm/unknown OS cache; no app cache; alternating fresh processes',
                status='running',pairs=args.pairs,os=platform.platform(),machine=platform.machine(),
                binary_sha256=hashlib.sha256(args.binary.read_bytes()).hexdigest(),
                source_hashes={str(p.relative_to(REPO)):hashlib.sha256(p.read_bytes()).hexdigest()
                               for p in sorted((REPO/'Sources/SpaceSnifferCore').glob('*.swift'))},
                fixture_free_bytes_at_start=free,backing_free_bytes_at_start=backing_free,planned_scenarios=args.scenarios,skipped_scenarios=[],fixtures=[],rows=[])
    def save():
        report['summary']=summarize(report['rows'])
        temporary=target.with_suffix('.json.tmp')
        temporary.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
        temporary.replace(target)
        (args.output/'summary.md').write_text(markdown(report))
    try:
        for scenario in args.scenarios:
            required=1024**3 if scenario in ('S05','S06') else 700*1024**2 if scenario in ('S02','S03-100000','S07') else 128*1024**2
            free=shutil.disk_usage(args.fixture_parent).free
            backing_free=shutil.disk_usage(args.backing_parent).free
            if free<required or backing_free<required+1024**3:
                report['skipped_scenarios'].append(dict(scenario=scenario,reason='insufficient fixture/backing space including reserve',free=free,backing_free=backing_free,required=required))
                save(); continue
            path=root/scenario
            print(f'creating {scenario}',flush=True)
            make_fixture(path,scenario,args.backing_parent)
            print(f'oracle before {scenario}',flush=True)
            expected=oracle(path)
            fixture=dict(scenario=scenario,root=str(path),oracle=expected)
            report['fixtures'].append(fixture)
            if args.catalog_volume:
                fixture['catalog']=catalog_probe(args.catalog_volume,path,expected)
                print(f"catalog {scenario}: {fixture['catalog']}",flush=True)
            for pair in range(args.pairs):
                modes=('posix','bulk','stream') if pair%2==0 else ('stream','bulk','posix')
                for mode in modes:
                    row=dict(scenario=scenario,pair=pair,mode=mode,status='failed')
                    try:
                        proc=subprocess.run([str(args.binary.resolve()),mode,str(path)],capture_output=True,text=True,timeout=120)
                        row['exit_status']=proc.returncode
                        if proc.returncode:
                            row['error']=proc.stderr[-4000:]
                        else:
                            row.update(json.loads(proc.stdout)); row['status']='ok'; evaluate(row,expected)
                    except (subprocess.TimeoutExpired,json.JSONDecodeError) as exc:
                        row['error']=str(exc)
                    report['rows'].append(row)
                print(f'{scenario}: pair {pair+1}/{args.pairs}',flush=True)
                save()
            # Verify fixture did not change during the entire paired experiment.
            print(f'oracle after {scenario}',flush=True)
            fixture['oracle_after']=oracle(path)
            fixture['stable']=fixture['oracle_after']==expected
            if not fixture['stable']:
                for row in report['rows']:
                    if row['scenario']==scenario: row['status']='invalid_fixture_changed'
            print(f'cleanup {scenario}',flush=True)
            shutil.rmtree(path)
            save()
        report['status']='measured_engine_only' if not report['skipped_scenarios'] else 'partial_space_skips'
    except KeyboardInterrupt:
        report['status']='interrupted'
        report['stop_reason']='KeyboardInterrupt; completed raw pairs preserved'
        return 130
    except OSError as exc:
        report['status']='harness_error'
        report['error']=str(exc)
        return 2
    finally:
        shutil.rmtree(root)
        report['cleanup']=dict(owned_fixture=str(root),exists_after=root.exists())
        save()
    return 0 if not report['skipped_scenarios'] and all(r.get('accurate') and r['status']=='ok' for r in report['rows']) else 1


if __name__=='__main__':
    raise SystemExit(main())
