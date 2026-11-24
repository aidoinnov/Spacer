#!/usr/bin/env python3
"""Publish a numeric scorecard without turning engine-only data into GUI claims."""
import argparse
import json
import math
import random
import statistics
from pathlib import Path


def percentile(xs, q):
    return sorted(xs)[max(0, math.ceil(len(xs)*q)-1)]


def paired_quantile_ci(pairs, q):
    if not pairs: return None
    rng=random.Random(20261116)
    values=[]
    def quantile(xs): return statistics.median(xs) if q==.5 else percentile(xs,q)
    for _ in range(2000):
        chosen=rng.choices(pairs,k=len(pairs))
        a,b=quantile([p[0] for p in chosen]),quantile([p[1] for p in chosen])
        if a: values.append((a-b)/a*100)
    return [percentile(values,.025),percentile(values,.975)] if values else None


def analyze(paths):
    cells={}
    for path in paths:
        report=json.loads(path.read_text())
        for scenario,modes in report.get('summary',{}).items():
            if scenario not in cells or modes['stream']['valid']>cells[scenario]['summary']['stream']['valid']:
                cells[scenario]=dict(source=str(path),series=path.parent.name,source_status=report.get('status'),binary_sha256=report.get('binary_sha256'),summary=modes,rows=[r for r in report['rows'] if r['scenario']==scenario])
    for scenario,cell in cells.items():
        rows=cell['rows']; by_mode={mode:{r['pair']:r for r in rows if r['mode']==mode and r['status']=='ok' and r.get('accurate')} for mode in ('posix','stream')}
        cell['engine_gate']={}
        for metric in ('scan_complete_ms','useful_callback_proxy_ms','peak_rss_mib','cpu_seconds'):
            pairs=[(a[metric],by_mode['stream'][key][metric]) for key,a in by_mode['posix'].items()
                   if key in by_mode['stream'] and a.get(metric) is not None and by_mode['stream'][key].get(metric) is not None]
            if not pairs:
                cell['engine_gate'][metric]=dict(status='not_applicable_or_missing'); continue
            p50ci=paired_quantile_ci(pairs,.5); p95ci=paired_quantile_ci(pairs,.95)
            cell['engine_gate'][metric]=dict(n=len(pairs),p50_improvement_ci95=p50ci,p95_improvement_ci95=p95ci,
                                            status='engine_proxy_only' if metric=='useful_callback_proxy_ms' else 'measured')
        summary=cell['summary']
        a,b=summary['posix']['metrics']['scan_complete_ms'],summary['stream']['metrics']['scan_complete_ms']
        if summary['stream']['valid']<20:
            cell['engine_total_time_point_gate']='insufficient_pairs'
        elif not a['p50'] or not a['p95']:
            cell['engine_total_time_point_gate']='missing_data'
        else:
            p50_extra=b['p50']-a['p50'];p95_extra=b['p95']-a['p95']
            p50_allowance=max(a['p50']*.1,50) if scenario=='S01' else a['p50']*.1
            p95_allowance=max(a['p95']*.1,50) if scenario=='S01' else a['p95']*.1
            cell['engine_total_time_point_gate']='failed' if p50_extra>p50_allowance or p95_extra>p95_allowance else 'within_point_thresholds'
        cell['adoption']='pending_GUI_cache_lifecycle_and_full_gate_matrix'
    return cells


def markdown(cells, base):
    def n(value): return 'N/A' if value is None else f'{value:.2f}'
    def link(path):
        import os
        return os.path.relpath(path,base)
    lines=['# 빠른 개요 + 상세 스캔 성과표','',
           '2026-11-16. **엔진 후보 구현·실측 완료 범위만 보고한다. 앱 기본 backend는 POSIX이며 GUI·캐시·증분 통합은 미완료다.**', '',
           '[실행 TODO](PROGRESSIVE_SCAN_TODO.md) · [테스트 계획](PROGRESSIVE_SCAN_TEST_PLAN.md) · [재현 명령](../scripts/bench/progressive-scan/README.md)', '',
           '## 실제 release 엔진 전후 성과','',
           'S01=1천 파일/50폴더, S02=10만 파일/5천 폴더, S03-숫자=한 폴더의 해당 파일 수, S04=64단계 깊이, S05/S06=작은 파일 99,990개+32MiB 파일 10개의 큰 분기 방문 순서 역전, S07=한 분기에 9만 파일이 몰린 입력이다.','',
           '동일 물리 fixture를 순서를 바꿔 fresh process로 반복했다. 각 셀은 독립 POSIX oracle의 경로·종류·identity·크기·일부 속성 checksum과 합계를 확인한다. OS metadata cache는 oracle에 의해 warm/unknown 상태다. 공유 호스트 부하가 있어 paired CI와 원시 결과를 함께 본다.', '',
           '| 시나리오 | 유효 pairs | 기존 p50 / p95 ms | streaming p50 / p95 ms | p50 감소율 | paired 감소율 [95% CI] | RSS 기존 → 후보 MiB |',
           '|---|---:|---:|---:|---:|---|---:|']
    for scenario,cell in sorted(cells.items()):
        a,b=cell['summary']['posix'],cell['summary']['stream']
        ma,mb=a['metrics']['scan_complete_ms'],b['metrics']['scan_complete_ms']
        change=(ma['p50']-mb['p50'])/ma['p50']*100 if ma['p50'] else None
        ci=mb['paired_improvement_ci95']
        lines.append(f"| {scenario} ({cell['series']}) | {b['valid']} | {n(ma['p50'])} / {n(ma['p95'])} | {n(mb['p50'])} / {n(mb['p95'])} | {n(change)}% | {n(mb['paired_improvement_pct'])}% [{', '.join(n(x) for x in ci) if ci else 'N/A'}] | {n(a['metrics']['peak_rss_mib']['p50'])} → {n(b['metrics']['peak_rss_mib']['p50'])} |")
    lines += ['', '각 행의 기존/후보는 같은 볼륨·binary 조건에서 비교했다. exploratory/paired-20은 APFS image, guarded-20은 시스템 임시 폴더이므로 서로 다른 행의 절대 시간을 직접 비교하지 않는다. p50 감소율은 두 중앙값의 비율이고 paired 감소율은 각 pair 감소율의 중앙값이므로 서로 다를 수 있다. 5-pair 셀은 탐색 결과이며 채택 표본 기준 20 pairs에 미달한다.', '',
              '## 첫 유용한 결과: 엔진 proxy와 화면 측정 구분','',
              '| 시나리오 | callback proxy p50 기존 → 후보 ms | 실제 화면 useful overview |',
              '|---|---:|---|']
    for scenario,cell in sorted(cells.items()):
        a,b=cell['summary']['posix']['metrics']['useful_callback_proxy_ms'],cell['summary']['stream']['metrics']['useful_callback_proxy_ms']
        lines.append(f"| {scenario} | {n(a['p50'])} → {n(b['p50'])} | 미측정 |")
    lines += ['', 'proxy는 top-k recall≥90%, byte error≤20%, 현재 관측 coverage≥70%를 이후 callback에서도 유지하는 최초 엔진 publication이다. 실제 draw와 1초 visible hold는 측정하지 않았다. direct-child 폴더가 없는 wide 입력은 N/A이며 0ms가 아니다.', '',
              '## 정확성·채택 판단','',
              '| 항목 | 상태 |', '|---|---|']
    attempted=sum(len(c['rows']) for c in cells.values())
    inaccurate=sum(not (r.get('accurate') and r['status']=='ok') for c in cells.values() for r in c['rows'])
    lines += [f'| 선택된 엔진 비교 실행 | {attempted}회, 실패·oracle 불일치 {inaccurate}회 |',
              '| searchfs 상세 backend | 채택 보류: 실제 APFS 필드 oracle에서 symlink/FIFO 종류가 일반 파일로 반환되고 link 논리 크기가 기존 규칙과 다름 |',
              '| 실제 develop catalog 조회 | 동일 inode·동일 alias record 반복을 감지하여 명시적으로 실패 처리 |',
              '| GUI p50 ≥50%·p95 ≥30% 단축 | 미측정: 엔진 개선율을 GUI 성과로 대체하지 않음 |',
              '| 캐시·FSEvents·동시 창·입력 지연·장시간 수명 | 미실행 |',
              '| 최종 채택 | 전체 gate 미완료, POSIX 기본값 유지 |','',
              '## 원시 근거','']
    for source in sorted({c['source'] for c in cells.values()}):
        cell=next(c for c in cells.values() if c['source']==source)
        lines.append(f"- [{cell['series']} 반복 실측 JSON]({link(source)}): {cell['source_status']}, binary `{cell['binary_sha256'][:16]}`")
    lines += ['- [전체 검증·I/O 호출 성과·중단/정리 기록](validation/progressive-scan-2026-11-16/README.md)',
              '- [catalog 필드 실패 근거](validation/progressive-scan-2026-11-16/catalog-fields.json)',
              '- [실제 볼륨 catalog 결과](validation/progressive-scan-2026-11-16/catalog-live.json)',
              '- [호스트 동시 부하](validation/progressive-scan-2026-11-16/host-context.json)',
              '- [측정 당시 소스 manifest](validation/progressive-scan-2026-11-16/source-manifest.json)',
              '', '다음 단계는 개요용 상태·공정한 순회·상세 보정과 실제 화면 계측이다. 여기의 엔진 결과만으로 전체 계획 완료 또는 앱 가속 적용을 선언하지 않는다.']
    return '\n'.join(lines)+'\n'


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--reports',nargs='+',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    cells=analyze(args.reports)
    args.output.write_text(markdown(cells,args.output.parent))
    args.output.with_suffix('.json').write_text(json.dumps({name:{key:value for key,value in cell.items() if key!='rows'} for name,cell in cells.items()},ensure_ascii=False,indent=2)+'\n')


if __name__=='__main__': main()
