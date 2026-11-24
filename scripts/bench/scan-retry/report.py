#!/usr/bin/env python3
"""Combine the predeclared V2 sample expansion; never drop failed/slow runs."""
import argparse,hashlib,json,math,random,statistics
from pathlib import Path


def percentile(xs,q):return sorted(xs)[max(0,math.ceil(len(xs)*q)-1)]

def interval(xs):
    rng=random.Random(20261119)
    samples=[statistics.median(rng.choices(xs,k=len(xs))) for _ in range(2000)]
    return [percentile(samples,.025),percentile(samples,.975)]


def combine(paths):
    rows=[];binaries=None
    for series,path in enumerate(paths):
        report=json.loads(path.read_text())
        if report.get('status')!='measured':raise ValueError(f'incomplete report: {path}')
        hashes={name:item['sha256'] for name,item in report['binaries'].items()}
        if binaries is not None and hashes!=binaries:raise ValueError('cannot pool different binary revisions')
        binaries=hashes
        for row in report['rows']:rows.append(dict(row,series=series))
    output=dict(scope='V01 V2 combined fixed initial20 + predeclared supplement80; all attempted rows retained',binaries=binaries,sources=[str(p) for p in paths],summary={})
    all_valid=True
    for scenario in ['denied20','normal-10000']:
        selected=[r for r in rows if r['scenario']==scenario]
        by_variant={name:{(r['series'],r['pair']):r for r in selected if r['variant']==name and r['status']=='ok' and r.get('pair_equal')} for name in ['before','after']}
        keys=by_variant['before'].keys() & by_variant['after'].keys()
        cell=dict(attempted_runs=len(selected),valid_pairs=len(keys),failed_runs=sum(r['status']!='ok' or not r.get('pair_equal') for r in selected))
        for name in ['before','after']:
            cell[name]={}
            for metric in ['scan_complete_ms','cpu_seconds','peak_rss_mib']:
                values=[by_variant[name][k][metric] for k in keys]
                if not values:raise ValueError('no valid values')
                cell[name][metric]=dict(p50=statistics.median(values),p95=percentile(values,.95))
        changes=[(by_variant['before'][k]['scan_complete_ms']-by_variant['after'][k]['scan_complete_ms'])/by_variant['before'][k]['scan_complete_ms']*100 for k in sorted(keys)]
        cell['paired_improvement_pct']=statistics.median(changes)
        cell['paired_ci95']=interval(changes)
        cell['counts']={name:{field:sorted({r['enumeration_io'][field] for r in by_variant[name].values() if field in r['enumeration_io']}) for field in ['openDirectoryCalls','openRetryDecisions','requestedRetryDelaySeconds']} for name in ['before','after']}
        valid=len(keys)>=20 and not cell['failed_runs']
        rss=cell['after']['peak_rss_mib']['p95']<=max(cell['before']['peak_rss_mib']['p95']*1.1,cell['before']['peak_rss_mib']['p95']+32)
        if scenario=='denied20':
            latency=cell['after']['scan_complete_ms']['p95']<=200
            behavior=cell['counts']['after']['openDirectoryCalls']==[21] and cell['counts']['after']['openRetryDecisions']==[0] and cell['counts']['after']['requestedRetryDelaySeconds']==[0]
            cell['gates']=dict(valid=valid,denied_p95_le_200ms=latency,one_open_per_denied_no_wait=behavior,rss=rss)
        else:
            latency=all(cell['after']['scan_complete_ms'][q]<=cell['before']['scan_complete_ms'][q]*1.1 for q in ['p50','p95'])
            cell['gates']=dict(valid=valid,normal_p50_p95_regression_le_10pct=latency,paired_median_ci_not_crossing_minus10=cell['paired_ci95'][0]>=-10,rss=rss)
        cell['gates']['cpu_p95_regression_le_20pct']=cell['after']['cpu_seconds']['p95']<=cell['before']['cpu_seconds']['p95']*1.2
        cell['point_gate_pass']=all(cell['gates'].values())
        all_valid=all_valid and cell['point_gate_pass']
        output['summary'][scenario]=cell
    output['gate_pass']=all_valid
    return output


def markdown(report):
    lines=['# V01 스캔 재시도 개선 성과','',
           '2026-11-19. 권한 오류의 무조건 재시도 제거와 관련 레거시 정리 결과다. V00/V02~V08 전체 완료를 뜻하지 않는다.','',
           '## 최종 V2 전후 비교','',
           '최초 20 pairs의 경계 근처 p95와 넓은 신뢰구간 때문에, 변경 없는 같은 binary로 사전에 80 pairs 추가 수집을 정했다. 아래는 빠른 표본만 골라내지 않고 총 100 pairs를 합친 결과다. 각 pair는 순서를 교대했다. 공유 호스트·warm/unknown OS cache·release 엔진 시간이며 GUI 또는 전체 볼륨 성과가 아니다.','',
           '| 입력 | valid pairs / 실패 실행 | 이전 p50 / p95 ms | V2 p50 / p95 ms | paired 감소율 [95% CI] | RSS p95 이전 → V2 MiB |',
           '|---|---:|---:|---:|---|---:|']
    for name,cell in report['summary'].items():
        a,b=cell['before'],cell['after'];ci=cell['paired_ci95']
        lines.append(f"| {name} | {cell['valid_pairs']} / {cell['failed_runs']} | {a['scan_complete_ms']['p50']:.2f} / {a['scan_complete_ms']['p95']:.2f} | {b['scan_complete_ms']['p50']:.2f} / {b['scan_complete_ms']['p95']:.2f} | {cell['paired_improvement_pct']:.2f}% [{ci[0]:.2f}, {ci[1]:.2f}] | {a['peak_rss_mib']['p95']:.2f} → {b['peak_rss_mib']['p95']:.2f} |")
    lines+=['','## Gate 판정','','| 입력 | 기준 | 판정 |','|---|---|---|']
    for name,cell in report['summary'].items():
        for gate,passed in cell['gates'].items():lines.append(f"| {name} | {gate} | {'통과' if passed else '미달/보류'} |")
    lines+=['',f"V01 최종 정량 gate: **{'통과' if report['gate_pass'] else '미달/보류'}**. 이 판정만으로 실제 GUI·모든 볼륨·다른 최적화 gate를 통과했다고 보지 않는다.",'',
            '## 구현과 책임','','- `ScanRetryPolicy`: errno 결정표, 최대 3회 open·요청 대기 합계 20ms. EINTR 즉시, EAGAIN/EBUSY/ETIMEDOUT만 10ms, 나머지 즉시 오류.',
            '- `POSIXDirectoryReader`: cursor·errno 즉시 캡처·FD cleanup·이름 정렬. POSIX 기본 경로와 bulk fallback이 같은 구현을 사용한다.',
            '- `ScanControl`: 기존 hot cancellation 조회는 NSLock으로 보호하고 retry condition만 분리한다. cancel은 state lock을 해제한 뒤 condition을 깨워 역순 잠금을 피한다.',
            '- 기존 모든 오류 10회 재시도 루프, 고정 Thread.sleep, `lastError!`, scanner 내부 열거 중첩 함수 제거. 오류 문자열의 중복 계산도 제거했다.',
            '- node ID/정렬·집계·볼륨 범위·필터·SNS/TXT·public scanner API·POSIX 기본 backend는 유지한다. 비교/재현에 쓰이는 backend와 과거 archive는 보존한다.','',
            '## 정확성·회귀·실패 기록','','- before/after 파일·폴더·bytes·오류 수·정규화 필드 digest 일치. denied20은 읽기 가능한 sibling 1개/3 bytes, 오류 20개를 보존한다. 원자적 filesystem snapshot 동등성을 주장하지 않는다.',
            '- [V2 전체 Swift 검사](validation/scan-retry-2026-11-19/full-tests-v2.log): 260개, 명시적 release render probe 1개 skip, 실패 0.',
            '- [V2 TSAN 검사](validation/scan-retry-2026-11-19/tsan-v2-final.log): 20개 통과. 오류/취소/FD·1,000개 admission callbacks·stale scheduling 포함.',
            '- SwiftPM discovery helper는 macOS sanitizer 로딩 정책 때문에 검사 전에 실패했다. disposable ad-hoc xctest copy에서 동일 TSAN bundle을 실행했다. Xcode·system security는 변경하지 않았다. 초기 loader 실패와 XCTest support 경로 실패를 보존했다.',
            '- V1 TSAN의 첫 실행에서 기존 admission stress가 8초 제한을 넘겼다. 변경 없는 재검사와 V2 최종 검사에서는 통과했다. 실패 로그는 삭제하지 않았다.',
            '- 최초 baseline 빌드는 source 수정 중 컴파일해 invalid로 제외했다. 최종 baseline은 immutable before/core archive에서 다시 빌드했다.',
            '- [V1 20-pair 결과](validation/scan-retry-2026-11-19/comparison-20.json)는 latency gate 미달이었다. V2에서 hot lock 복원과 중복 오류 formatting 제거를 수행했다. 원인 전체를 NSCondition 하나로 단정하지 않는다.','',
            '## 재현·원시 근거','','- [실행 방법](../scripts/bench/scan-retry/README.md)',
            '- [최초 V2 20 pairs](validation/scan-retry-2026-11-19/comparison-v2-20.json)',
            '- [V2 보강 80 pairs](validation/scan-retry-2026-11-19/comparison-v2-supplement80.json)',
            '- [추가 표본 수집 계획](validation/scan-retry-2026-11-19/supplement-plan.json)',
            '- [baseline 빌드 manifest](validation/scan-retry-2026-11-19/comparison-build-manifest.json)',
            '- [V2 source/binary manifest](validation/scan-retry-2026-11-19/after-v2-manifest.json)',
            '- [근거 추적 검사](validation/scan-retry-2026-11-19/engine-evidence.log)',
            '- [실행 TODO](SCAN_SPEED_TODO.md)','',
            '패키징·실제 앱 검증 결과는 별도 packaging.json에서 기록한다. 현재 실행 중인 기존 앱과 새 디스크상의 binary 버전을 구분한다.']
    return '\n'.join(lines)+'\n'


def main():
    p=argparse.ArgumentParser();p.add_argument('--reports',nargs='+',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
    report=combine(a.reports);a.output.with_suffix('.json').write_text(json.dumps(report,indent=2)+'\n');a.output.write_text(markdown(report))
    print('gate_pass',report['gate_pass'])


if __name__=='__main__':main()
