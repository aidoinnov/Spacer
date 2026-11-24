#!/usr/bin/env python3
import argparse,json,math,statistics
from pathlib import Path
from compare import ci,percentile

def score(raw):
 report=dict(pairs=raw['pairs'],binaries=raw['binaries'],scope=raw['scope'],cells={},passed=False)
 complete=raw.get('status')=='measured' and raw.get('control_removed') is True and raw['pairs']>=20
 for scenario in ['mounted','control10000']:
  cells={}
  for variant in ['before_all','after_all','after_selected']:
   rows=[r for r in raw['rows'] if r['scenario']==scenario and r['variant']==variant]
   expected=(100,5,300) if scenario=='mounted' and variant=='after_selected' else (6100,37,30300) if scenario=='mounted' else (10000,101,505000)
   def valid_row(row):
    if row.get('status')!='ok' or row.get('same_scope_equal') is not True:return False
    if tuple(row.get(k) for k in ['files','folders','logical_bytes'])!=expected or row.get('issue_count')!=0 or row.get('cancelled') is not False:return False
    if not all(isinstance(row.get(k),(int,float)) and math.isfinite(row[k]) and row[k]>0 for k in ['scan_complete_ms','cpu_seconds','peak_rss_mib']):return False
    if variant.startswith('after'):
     coverage=row.get('volume_coverage',{})
     if coverage.get('traversal')!=('allVolumes' if variant=='after_all' else 'selectedVolume'):return False
     if coverage.get('excludedCount')!=(1 if scenario=='mounted' and variant=='after_selected' else 0):return False
    return True
   valid=[r for r in rows if valid_row(r)]
   good=len(rows)==len(valid)==raw['pairs'] and {r['pair'] for r in valid}==set(range(raw['pairs']))
   complete &= good
   cells[variant]=dict(attempted=len(rows),valid=len(valid),complete=good,metrics={},rows=valid)
   if valid:
    for metric in ['scan_complete_ms','cpu_seconds','peak_rss_mib']:
     values=[r[metric] for r in valid];cells[variant]['metrics'][metric]=dict(p50=statistics.median(values),p95=percentile(values,.95))
  checks={}
  for variant in ['after_all']+(['after_selected'] if scenario=='control10000' else []):
   baseline=cells['before_all'];candidate=cells[variant];gates=dict(complete=baseline['complete'] and candidate['complete'])
   if gates['complete']:
    before={r['pair']:r for r in baseline['rows']};after={r['pair']:r for r in candidate['rows']}
    gates['digest']=all(before[i]['digest']==after[i]['digest'] for i in before)
    changes=[100*(r['scan_complete_ms']-after[i]['scan_complete_ms'])/r['scan_complete_ms'] for i,r in before.items()]
    interval=ci(changes);b=baseline['metrics'];a=candidate['metrics']
    gates.update(latency=all(a['scan_complete_ms'][q]<=b['scan_complete_ms'][q]*1.1 for q in ['p50','p95']),paired_ci=interval[0]>=-10,cpu=a['cpu_seconds']['p95']<=b['cpu_seconds']['p95']*1.2,rss=a['peak_rss_mib']['p95']<=max(b['peak_rss_mib']['p95']*1.1,b['peak_rss_mib']['p95']+32))
    checks[variant]=dict(gates=gates,paired_improvement_pct=statistics.median(changes),ci95=interval,passed=all(gates.values()))
   else:checks[variant]=dict(gates=gates,passed=False)
  for cell in cells.values():del cell['rows']
  report['cells'][scenario]=dict(variants=cells,checks=checks)
 report['passed']=complete and all(c['passed'] for s in report['cells'].values() for c in s['checks'].values())
 return report

def markdown(r):
 lines=['# V00 볼륨 범위 검증 성과','',f"2026-11-19. 후보V3, 입력별{r['pairs']} pairs ×3변형. 동일 범위 회귀 gate: **{'통과' if r['passed'] else '미달/보류'}**.",'',
 '같은 파일을 더 빨리 읽는 엔진 성과와, 선택 범위 밖의 볼륨을 읽지 않아 줄어든 작업량을 구분한다. 공유 호스트·warm/unknown cache·릴리스 엔진 완료 시간이다. GUI draw 시간이나 전체 실제 볼륨 속도를 의미하지 않는다.','',
 '| 입력·변형 | 파일 / 폴더 | p50 / p95 ms | CPU p95 ms | RSS p95 MiB |','|---|---:|---:|---:|---:|']
 for scenario,cell in r['cells'].items():
  for variant,value in cell['variants'].items():
   m=value['metrics'];counts='100 / 5' if scenario=='mounted' and variant=='after_selected' else '6100 / 37' if scenario=='mounted' else '10000 / 101'
   if m:lines.append(f"| {scenario} · {variant} | {counts} | {m['scan_complete_ms']['p50']:.2f} / {m['scan_complete_ms']['p95']:.2f} | {m['cpu_seconds']['p95']*1000:.2f} | {m['peak_rss_mib']['p95']:.2f} |")
 lines+=['','## 동일 범위 판정','','| 입력·후보 | paired 감소율 [95% CI] | 판정·미달 항목 |','|---|---|---|']
 for scenario,cell in r['cells'].items():
  for variant,c in cell['checks'].items():
   change=f"{c['paired_improvement_pct']:.2f}% [{c['ci95'][0]:.2f}, {c['ci95'][1]:.2f}]" if 'ci95' in c else '누락/실패'
   failed=', '.join(k for k,v in c['gates'].items() if not v)
   lines.append(f"| {scenario} · {variant} | {change} | {'통과' if c['passed'] else '보류: '+failed} |")
 lines+=['','기준: 동일 scope 파일·필드 digest 정확성, p50/p95 회귀≤10%, paired CI하한≥−10%, CPU p95회귀≤20%, RSS p95≤max(이전×1.10, 이전+32MiB). 모든 시도와 pair를 분모에 포함한다.','',
 '## 범위·정확성','',
 '- 기본은 선택 볼륨만. `--include-mounted-volumes` 또는 GUI의 다른 볼륨 포함 옵션으로 범위를 확장한다. 옵션 변경 시 새 검사로 시작하며 mode별 root cache는 분리하고 전역 scan admission은 공유한다.',
 '- 실제 중첩 HFS+ 이미지 두 개에서 기본100개/300 logical bytes/5폴더, 포함6100개/30300 bytes/37폴더를 확인했다. 기본은 경계1곳을 기록하고 외부 트리의 폴더를 열지 않는다. 이는 범위 축소 효과다.',
 '- 이미 아는 mount는 target lstat 이전에 제외한다. getfsstat MNT_NOWAIT와 초기4096개 미만의 mount count 및16개 여유 슬롯을 사용하며 실패/초과는 검사 오류로 표시한다. mount 이름 정규화로 remote 파일시스템을 조회하지 않는다.',
 '- `/`에서는 APFS System/Data 연결의 Users/private를 유지하고 `/System/Volumes/Data` 직접 별칭은 두 모드 모두 제외한다. 임의의 symlink/hardlink를 물리 공간으로 deduplicate한다는 뜻은 아니다.',
 '- 부분 재검사는 원래 root를 anchor로 사용한다. 제외 경계의 일반 watch 이벤트와 focus 요청을 차단하며, mount/loss 이벤트는 기존 full-refresh 복구 규칙을 따른다. 다른 볼륨의 free/total을 root의 용량으로 덮어쓰지 않는다.',
 '- 제외 정보는 오류와 별도이며 최대500개 경로와 전체 count를 보유한다. truncated provenance는 다음 작업에서 root refresh로 승격한다. snapshot merge는 scope 안의 제외 정보만 교체하고 mode 혼합을 거부한다.',
 '- 기존 SNS 형식에는 이 Mac-only provenance를 추가하지 않았다. 오래된 JSON/SNS를 읽을 때 scope는 unknown이며 현재 volume 정책을 소급해 붙이지 않는다.',
 '- mount inventory와 파일 트리는 atomic snapshot이 아니다. 실행 중 새 mount/동일 device alias 변경은 관측 및 다음 watcher refresh로 수렴한다. 동적 remount 전체 조합의 원자적 보장을 주장하지 않는다.','',
 '## 근거','',
 '- [원시100-pair 측정](validation/scan-scope-2026-11-19/comparison-v3-100.json), [사전 계획·소스 hash](validation/scan-scope-2026-11-19/v3-plan.json)',
 '- [테스트·패키지·cleanup 기록](validation/scan-scope-2026-11-19/README.md), [실행 방법](../scripts/bench/scan-scope/README.md)',
 '- V2의 추가 scope 검사 비용과 미달 gate는 comparison20.json으로 보존했다. V3은 scalar DeviceRule과 boundary 없는 폴더 fast path로 수정했다. 표본 수100은 수집 전에 고정했고 같은 후보를 통과할 때까지 반복하지 않는다.','']
 return '\n'.join(lines)

def main():
 p=argparse.ArgumentParser();p.add_argument('--raw',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args();r=score(json.loads(a.raw.read_text()));a.output.write_text(markdown(r));a.output.with_suffix('.json').write_text(json.dumps(r,indent=2)+'\n');print('PASS' if r['passed'] else 'HOLD')
if __name__=='__main__':main()
