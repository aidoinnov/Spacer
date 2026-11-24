#!/usr/bin/env python3
"""Recompute release gates from every raw row; never trust cached summaries."""
import argparse, copy, json, math, statistics
from pathlib import Path
from compare import ci, percentile

REQUIRED = ['small1000','normal10000','wide4100','wide100000','overbudget131073','denied20','tinyfolders1000','deep200']

def merge(raw, supplement):
    assert raw['variants']==supplement['variants'], 'binary/mode identity changed'
    assert supplement['planned_scenarios']==['small1000'], 'only predeclared small-input expansion allowed'
    assert all(r['scenario']=='small1000' for r in supplement['rows'])
    result=copy.deepcopy(raw)
    result['pairs_by_scenario']={s:raw['pairs'] for s in REQUIRED}
    result['pairs_by_scenario']['small1000']+=supplement['pairs']
    for row in supplement['rows']:
        entry=copy.deepcopy(row);entry['pair']+=raw['pairs'];result['rows'].append(entry)
    result['status']='measured' if raw.get('status')==supplement.get('status')=='measured' else 'incomplete'
    result['cleanup']['exists_after']=raw.get('cleanup',{}).get('exists_after',True) or supplement.get('cleanup',{}).get('exists_after',True)
    return result

def score(raw):
    report = dict(scope=raw['scope'], pairs=raw['pairs'], pairs_by_scenario=raw.get('pairs_by_scenario',{}), variants=raw['variants'], scenarios={}, passed=False)
    for scenario in REQUIRED:
        count=raw.get('pairs_by_scenario',{}).get(scenario,raw['pairs'])
        rows = [r for r in raw['rows'] if r['scenario']==scenario]
        metrics = {}; complete = count>=20
        for variant in raw['variants']:
            cells = [r for r in rows if r['variant']==variant]
            valid = [r for r in cells if r.get('status')=='ok' and r.get('pair_equal') is True and
                     all(isinstance(r.get(k),(float,int)) and math.isfinite(r[k]) and r[k]>=0 for k in ['scan_complete_ms','cpu_seconds','peak_rss_mib'])]
            complete &= len(valid)==len(cells)==count and {r['pair'] for r in valid}==set(range(count))
            metrics[variant] = dict(attempted=len(cells),valid=len(valid),metrics={})
            for key in ['scan_complete_ms','cpu_seconds','peak_rss_mib','metadata_requests_per_entry']:
                values=[r[key] for r in valid]
                if values:metrics[variant]['metrics'][key] = dict(p50=statistics.median(values),p95=percentile(values,.95))
        comparisons={}
        for baseline in [v for v in raw['variants'] if v!='ordered']:
            before={r['pair']:r for r in rows if r['variant']==baseline}
            after={r['pair']:r for r in rows if r['variant']=='ordered'}
            consistent=complete and all(before[p]['digest']==after[p]['digest'] for p in before)
            gates=dict(complete_and_equal=bool(consistent))
            if consistent:
                changes=[100*(before[p]['scan_complete_ms']-after[p]['scan_complete_ms'])/before[p]['scan_complete_ms'] for p in before]
                interval=ci(changes)
                b=metrics[baseline]['metrics'];a=metrics['ordered']['metrics']
                gates.update(latency=all(a['scan_complete_ms'][q]<=1.1*b['scan_complete_ms'][q] for q in ['p50','p95']),
                             paired_ci_margin=interval[0]>=-10,
                             cpu=a['cpu_seconds']['p95']<=1.2*b['cpu_seconds']['p95'],
                             rss=a['peak_rss_mib']['p95']<=max(1.1*b['peak_rss_mib']['p95'],b['peak_rss_mib']['p95']+32))
                if scenario=='denied20':gates['denied_p95']=a['scan_complete_ms']['p95']<=200
                comparisons[baseline]=dict(improvement_pct=statistics.median(changes),ci95=interval,gates=gates,passed=all(gates.values()))
            else:comparisons[baseline]=dict(gates=gates,passed=False)
        report['scenarios'][scenario]=dict(variants=metrics,comparisons=comparisons)
    report['passed']={'posix','ordered'}<=set(raw['variants']) and raw.get('status')=='measured' and not raw.get('cleanup',{}).get('exists_after',True) and all(
        c['passed'] for s in report['scenarios'].values() for c in s['comparisons'].values())
    return report

def markdown(report, raw_path):
    lines=['# V02 메타데이터 배치 조회 성과','',
           '2026-11-19. V01 재시도 개선을 포함한 자동 선택 후보. 같은 V4 binary의 POSIX와 비교해 V02를 분리하고, 이전 앱의 고정 binary와도 비교했다.', '',
           f"정량 gate: **{'통과' if report['passed'] else '미달/보류'}**. 기본 {report['pairs']} pairs/입력, small1000은 {report['pairs_by_scenario'].get('small1000',report['pairs'])} pairs. 세 변형 실행 순서 교대. 공유 호스트·warm/unknown OS cache·릴리스 엔진 완료 시간이며 GUI/전체 볼륨 성과가 아니다.", '',
           '| 입력 | V01 POSIX p50 / p95 ms | 자동 배치 p50 / p95 ms | paired 감소율 [95% CI] | RSS p95 이전 → 배치 MiB | 판정 |',
           '|---|---:|---:|---|---:|---|']
    for name,cell in report['scenarios'].items():
        b=cell['variants']['posix']['metrics'];a=cell['variants']['ordered']['metrics'];c=cell['comparisons']['posix']
        if not b or not a:lines.append(f'| {name} | 부족 | 부족 | 판정 불가 | — | 보류 |');continue
        change=f"{c['improvement_pct']:.2f}% [{c['ci95'][0]:.2f}, {c['ci95'][1]:.2f}]" if 'ci95' in c else '실패/누락 있음'
        lines.append(f"| {name} | {b['scan_complete_ms']['p50']:.2f} / {b['scan_complete_ms']['p95']:.2f} | {a['scan_complete_ms']['p50']:.2f} / {a['scan_complete_ms']['p95']:.2f} | {change} | {b['peak_rss_mib']['p95']:.2f} → {a['peak_rss_mib']['p95']:.2f} | {'통과' if c['passed'] else '보류'} |")
    lines+=['', '기준: 완료 p50/p95 회귀 ≤10%, paired median 95% CI 하한 ≥−10%, CPU p95 회귀 ≤20%, RSS p95 ≤max(POSIX×1.10, POSIX+32MiB), denied20 p95 ≤200ms. 모든 시도·pair가 정확성 검증을 통과해야 한다.', '',
            '## 이전 앱과 비교','', '| 입력 | 기존 p50 → 후보 p50 ms | paired 감소율 [95% CI] | 판정 |','|---|---:|---|---|']
    for name,cell in report['scenarios'].items():
        if 'original' not in cell['comparisons']:continue
        c=cell['comparisons']['original'];b=cell['variants']['original']['metrics'];a=cell['variants']['ordered']['metrics']
        if 'ci95' in c:lines.append(f"| {name} | {b['scan_complete_ms']['p50']:.2f} → {a['scan_complete_ms']['p50']:.2f} | {c['improvement_pct']:.2f}% [{c['ci95'][0]:.2f}, {c['ci95'][1]:.2f}] | {'통과' if c['passed'] else '보류'} |")
    isolated=all(s['comparisons'].get('posix',{}).get('passed',False) for s in report['scenarios'].values())
    lines+=['', f"V02 단독 비교: {'8개 입력 통과' if isolated else '미달/보류'}. 전체 채택은 이전 앱 비교도 모두 통과해야 한다. 남은 미달 항목:", '']
    for name,cell in report['scenarios'].items():
        for baseline,c in cell['comparisons'].items():
            if not c['passed']:
                failed=', '.join(k for k,v in c['gates'].items() if not v)
                lines.append(f'- {name} / {baseline}: {failed}.')
    if report.get('pairs_by_scenario'):
        lines+=['', 'small1000은 최초20+사전 고정80 pairs를 모두 합쳤다. 원시 보강 측정은 [comparison-v4-small80.json](validation/scan-bulk-2026-11-19/comparison-v4-small80.json), 계획은 [v4-small-supplement-plan.json](validation/scan-bulk-2026-11-19/v4-small-supplement-plan.json)이다. 기존 S01 제품 계획은 50ms 절대 예산을 허용하지만, 이번 수집 전에 고정한 더 엄격한 10% 기준을 사후에 완화해 채택하지 않았다.']
    lines+=['', '개별 V01의 과거 CI 보류 판정은 유지한다. 이번 판정은 변경된 V01+V02 후보에 한정한다. 실패·느린 표본을 제외하거나 이전 시리즈를 임의로 합치지 않았다.', '',
            '## 구현·정확성·한계','',
            '- POSIX 이름 열거/정렬을 먼저 수행하고, 16~131,072개 및 추정 32MiB 예산 안에서만 native metadata를 수집한다. 너무 작거나 큰 폴더는 prefix 조회 없이 POSIX를 사용한다.',
            '- 두 목록의 raw UTF-8 이름이 일치할 때만 metadata를 원래 순서로 사용한다. 실패·불일치는 첫 이름 목록을 재사용해 lstat하며 두 번째 readdir를 피한다.',
            '- `ScanMetadataPolicy`가 실행 내 device별 local APFS 여부를 판정한다. 중첩 mount는 별도로 판정하고 미지원·remote·판정 실패는 POSIX다. 범위 축소로 얻은 속도 차이는 없다.',
            '- parser와 예산은 `NativeDirectoryMetadata`, FD/errno/retry는 `POSIXDirectoryReader`와 `ScanRetryPolicy`, tree/합계는 기존 단일 scanner worker가 소유한다. model 필드·정렬·export 형식은 추가하지 않았다.',
            '- 예산은 추정치이며 hard RSS 제한이 아니다. 10만 파일 셀의 실제 RSS를 위에 보고했다. 두 번의 디렉터리 열거는 atomic snapshot이 아니며 rename 경합 시 오류/부분 결과를 보존하고 다음 스캔의 수렴을 검사했다.',
            '- V2 탐색에서 tinyfolders/deep가 회귀해 V3에서 16개 미만을 건너뛰었다. V3의 wide RSS gate 미달로 V4에서 정확한 count로 배열을 예약하고 검증한 이름 목록을 먼저 해제했다. 각 후보의 실패 근거와 고정 20-pair 시리즈를 보존했다.',
            '- 이전 streaming/adaptive backend는 benchmark·회귀 비교에 사용 중이므로 보존한다. obsolete retry/sleep/강제 unwrap 제거는 V01에서 완료했다.', '',
            f'원시 측정: [{raw_path.name}](validation/scan-bulk-2026-11-19/{raw_path.name}). 소스·테스트·TSAN·패키징 근거: [검증 기록](validation/scan-bulk-2026-11-19/README.md). 재현: [실행 방법](../scripts/bench/scan-bulk/README.md).', '']
    return '\n'.join(lines)

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--raw',type=Path,required=True);parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--supplement',type=Path)
    args=parser.parse_args();raw=json.loads(args.raw.read_text())
    if args.supplement:raw=merge(raw,json.loads(args.supplement.read_text()))
    result=score(raw)
    result['raw_reports']=[str(args.raw)]+([str(args.supplement)] if args.supplement else [])
    args.output.write_text(markdown(result,args.raw));args.output.with_suffix('.json').write_text(json.dumps(result,indent=2)+'\n')
    print('PASS' if result['passed'] else 'HOLD')

if __name__=='__main__':main()
