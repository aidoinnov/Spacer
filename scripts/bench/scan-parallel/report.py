#!/usr/bin/env python3
"""Recompute adoption gates from every raw attempt, never cached summaries."""
import argparse
import json
import math
import statistics
from pathlib import Path
from compare import ci, percentile

VARIANTS = ('before', 'serial', 'parallel2', 'parallel4')
SCENARIOS = {'small1000': (1000, 51), 'normal10000': (10000, 101),
             'wide4100': (4100, 1), 'wide100000': (100000, 1),
             'overbudget131073': (131073, 1), 'tinyfolders1000': (1000, 1001),
             'deep200': (200, 201)}
METRICS = ('scan_complete_ms', 'cpu_seconds', 'peak_rss_mib')



def valid_warmups(raw):
    count = raw.get('warmup_pairs', 0)
    rows = raw.get('warmup_rows', [])
    if not isinstance(count, int) or count < 0: return False
    variants = tuple(raw.get('variants') or VARIANTS)
    expected = {(s, v, p) for s in raw['planned_scenarios'] for v in variants for p in range(-count, 0)}
    cells = {(r.get('scenario'), r.get('variant'), r.get('pair')) for r in rows}
    if len(rows) != len(expected) or cells != expected: return False
    digests = {}
    for row in rows:
        scenario = row['scenario']
        if scenario not in SCENARIOS: return False
        files, folders = SCENARIOS[scenario]
        logical = (files // 100) * 5050 + sum(range(1, files % 100 + 1))
        allocated = raw.get('summary', {}).get(scenario, {}).get('expected', {}).get('allocated_bytes')
        if not (row.get('status') == 'ok' and row.get('exit_status') == 0 and row.get('pair_equal') is True
                and row.get('phase') == 'warmup' and row.get('files') == files and row.get('folders') == folders
                and row.get('logical_bytes') == logical and row.get('allocated_bytes') == allocated
                and row.get('issue_count') == 0 and row.get('cancelled') is False and row.get('digest')): return False
        digests.setdefault((scenario, row['pair']), set()).add(row['digest'])
    return all(len(values) == 1 for values in digests.values())


def score(raw):
    pairs = raw['pairs']
    planned = raw['planned_scenarios']
    variants = tuple(raw.get('variants') or VARIANTS)
    complete = (raw.get('status') == 'measured' and raw.get('cleanup', {}).get('removed') is True
                and pairs >= 20 and len(planned) == len(set(planned))
                and set(planned) == set(SCENARIOS)
                and {'before', 'serial'} <= set(variants) <= set(VARIANTS)
                and bool(set(variants) & {'parallel2', 'parallel4'})
                and len(raw['rows']) == pairs * len(planned) * len(variants) and valid_warmups(raw))
    result = dict(pairs=pairs, warmup_pairs=raw.get('warmup_pairs',0), scope=raw['scope'], variants=raw['variants'], scenarios={}, adopted=[])
    for scenario in planned:
        files, folders = SCENARIOS[scenario]
        logical = (files // 100) * 5050 + sum(range(1, files % 100 + 1))
        allocated = raw.get('summary', {}).get(scenario, {}).get('expected', {}).get('allocated_bytes')
        groups, cells = {}, {}
        for variant in variants:
            rows = [r for r in raw['rows'] if r.get('scenario') == scenario and r.get('variant') == variant]
            def valid(r):
                return (r.get('status') == 'ok' and r.get('exit_status') == 0
                        and r.get('pair_equal') is True and r.get('files') == files
                        and r.get('folders') == folders and r.get('issue_count') == 0
                        and r.get('cancelled') is False and isinstance(r.get('digest'), str)
                        and len(r['digest']) == 64
                        and all(isinstance(r.get(k), (int, float)) and not isinstance(r[k], bool)
                                and math.isfinite(r[k]) and r[k] > 0 for k in METRICS)
                        and r.get('logical_bytes') == logical
                        and isinstance(allocated, int) and allocated >= 0
                        and r.get('allocated_bytes') == allocated)
            good = [r for r in rows if valid(r)]
            ok = len(rows) == len(good) == pairs and {r['pair'] for r in good} == set(range(pairs))
            groups[variant] = {r['pair']: r for r in good} if ok else {}
            metrics = {k: dict(p50=statistics.median([r[k] for r in good]),
                               p95=percentile([r[k] for r in good], .95)) for k in METRICS} if good else {}
            used = [r.get('enumeration_io', {}).get('prefetchUsed', 0) for r in good]
            peaks = [r['peak_directory_sections'] for r in good if 'peak_directory_sections' in r]
            cells[variant] = dict(attempted=len(rows), valid=len(good), complete=ok, metrics=metrics,
                                  prefetch_used_range=[min(used), max(used)] if used else [],
                                  peak_directory_sections=max(peaks) if peaks else None)
        checks = {}
        for variant in [v for v in variants if v != 'before']:
            for baseline in ('before',) + (('serial',) if variant != 'serial' else ()):
                b, a = groups[baseline], groups[variant]
                gates = dict(complete=bool(b and a))
                detail = {}
                if gates['complete']:
                    gates['exact'] = all(b[i]['digest'] == a[i]['digest'] and
                                         b[i]['allocated_bytes'] == a[i]['allocated_bytes'] for i in b)
                    changes = [100 * (b[i]['scan_complete_ms'] - a[i]['scan_complete_ms']) /
                               b[i]['scan_complete_ms'] for i in b]
                    interval = ci(changes)
                    bm, am = cells[baseline]['metrics'], cells[variant]['metrics']
                    gates.update(latency=all(am['scan_complete_ms'][q] <= bm['scan_complete_ms'][q]*1.1
                                             for q in ('p50', 'p95')),
                                 paired_ci=interval[0] >= -10,
                                 cpu=am['cpu_seconds']['p95'] <= bm['cpu_seconds']['p95']*1.2,
                                 rss=am['peak_rss_mib']['p95'] <= max(bm['peak_rss_mib']['p95']*1.1,
                                                                                bm['peak_rss_mib']['p95']+32))
                    detail = dict(paired_improvement_pct=statistics.median(changes), ci95=interval)
                checks[variant+'_vs_'+baseline] = dict(gates=gates, passed=all(gates.values()), **detail)
        result['scenarios'][scenario] = dict(variants=cells, comparisons=checks)
    result['complete'] = complete
    for variant in ('parallel2', 'parallel4'):
        if variant not in variants: continue
        if complete and all(cell['comparisons'][variant+'_vs_'+base]['passed']
                            for cell in result['scenarios'].values() for base in ('before', 'serial')):
            result['adopted'].append(variant)
    return result


def markdown(r):
    lines = ['# V03 디렉터리 병렬 읽기 측정', '',
             '판정: **'+(', '.join(r['adopted'])+' 채택 가능' if r['adopted'] else '기본 적용 보류')+'**.', '',
             '수집·정리·최소 표본 조건: '+('충족' if r['complete'] else '미충족')+'.', '',
             f"입력별 {r['pairs']}쌍. 같은 범위·같은 파일, 릴리스 엔진, 공유 호스트, warm/unknown cache. GUI 완료 시간이나 실제 전체 볼륨 속도를 의미하지 않는다.", '',
             f"변형별 사전 워밍업 {r.get('warmup_pairs',0)}회/입력. 워밍업도 별도로 보존·정확성 검증하며 아래 통계에는 포함하지 않는다.", '',
             '| 입력 | 변형 | 유효 / 시도 | p50 / p95 ms | CPU p95 ms | RSS p95 MiB |',
             '|---|---|---:|---:|---:|---:|']
    for scenario, cell in r['scenarios'].items():
        for variant, value in cell['variants'].items():
            m = value['metrics']
            if m:
                lines.append(f"| {scenario} | {variant} | {value['valid']} / {value['attempted']} | {m['scan_complete_ms']['p50']:.2f} / {m['scan_complete_ms']['p95']:.2f} | {m['cpu_seconds']['p95']*1000:.2f} | {m['peak_rss_mib']['p95']:.2f} |")
    lines += ['', '| 입력·비교 | paired 감소율 [95% CI] | 판정 |', '|---|---:|---|']
    for scenario, cell in r['scenarios'].items():
        for name, c in cell['comparisons'].items():
            delta = f"{c['paired_improvement_pct']:.2f}% [{c['ci95'][0]:.2f}, {c['ci95'][1]:.2f}]" if 'ci95' in c else '누락'
            failed = ', '.join(k for k, v in c['gates'].items() if not v)
            lines.append(f"| {scenario} · {name} | {delta} | {'통과' if c['passed'] else '보류: '+failed} |")
    lines += ['', '모든 시도를 포함해 원시 결과에서 재계산한다. 7개 입력 전체와 최소20쌍, 결과 digest·파일/폴더/크기 일치, p50/p95 회귀≤10%, paired bootstrap CI 하한≥−10%, CPU p95 회귀≤20%, RSS p95≤max(기준×1.10, 기준+32MiB)를 요구한다.', '']
    selected = 'parallel4' if 'parallel4' in next(iter(r['scenarios'].values()))['variants'] else 'parallel2'
    lines += ['## 실제 read-ahead 활성화', '',
              '병렬도 설정은 동시 directory sections의 상한이다. 각 입력의 실제 활성화 통계와 함께 해석한다.', '',
              f'| 입력 | {selected} prefetch 수락 최소~최대 | 최대 동시 directory sections |', '|---|---:|---:|']
    for scenario, cell in r['scenarios'].items():
        value = cell['variants'][selected]
        lines.append(f"| {scenario} | {value['prefetch_used_range']} | {value['peak_directory_sections']} |")
    lines += ['', '이 성과표는 엔진 비교다. GUI/watch·패키징·실행본 교체는 별도 검증하며, 공유 호스트의 warm/unknown cache 결과를 전체 실제 볼륨 성능으로 확대 해석하지 않는다.', '',
              '[설계·소유권](SCAN_PARALLEL_DESIGN.md) · [원시 결과·테스트·정리 기록](validation/scan-parallel-2026-11-19/README.md) · [재현 명령](../scripts/bench/scan-parallel/README.md)', '']
    return '\n'.join(lines)


if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('--raw', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    args = p.parse_args()
    result = score(json.loads(args.raw.read_text()))
    args.output.write_text(markdown(result))
    args.output.with_suffix('.json').write_text(json.dumps(result, indent=2)+'\n')
    print(result['adopted'] or 'HOLD')
