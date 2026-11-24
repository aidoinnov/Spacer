#!/usr/bin/env python3
"""Delivery scorecard: existing unchanged gates, plus separate GUI evidence."""
import argparse, json
from pathlib import Path
from report import score

p = argparse.ArgumentParser()
p.add_argument('--raw', type=Path, required=True)
p.add_argument('--proof', type=Path, required=True)
p.add_argument('--output', type=Path, required=True)
a = p.parse_args()
raw = json.loads(a.raw.read_text()); result = score(raw)
chosen = 'parallel2'
passed = chosen in result['adopted']
lines = ['# 분석 속도·빠른 개요 검증', '',
         '**엔진 판정: '+('기준 통과 · 기본 병렬도2' if passed else '기준 미달 · 기본 배포 보류')+'**', '',
         f"입력별 {raw['pairs']}쌍, 총 {len(raw['rows'])}회. {raw.get('fixture_storage','기록 없음')}. 공유 호스트·warm/unknown cache이며, 파일 내용은 읽지 않는 메타데이터 검사다. 이전 dense-file 실험과 합산하지 않는다.", '',
         '| 입력 | 기준 p50 / p95 ms | 후보2 p50 / p95 ms | 후보 CPU p95 ms | RSS p95 MiB | paired 감소율 [95% CI] | 판정 |',
         '|---|---:|---:|---:|---:|---:|---|']
for name, cell in result['scenarios'].items():
    b = cell['variants']['before']['metrics']; c = cell['variants'][chosen]['metrics']
    checks = [cell['comparisons'][chosen+'_vs_'+base] for base in ['before','serial']]
    comparison = checks[0]
    failure = '; '.join(base+':'+','.join(k for k,v in check['gates'].items() if not v)
                        for base,check in zip(['before','serial'], checks) if not check['passed'])
    if b and c and 'ci95' in comparison:
        lines.append(f"| {name} | {b['scan_complete_ms']['p50']:.2f} / {b['scan_complete_ms']['p95']:.2f} | {c['scan_complete_ms']['p50']:.2f} / {c['scan_complete_ms']['p95']:.2f} | {c['cpu_seconds']['p95']*1000:.2f} | {c['peak_rss_mib']['p95']:.2f} | {comparison['paired_improvement_pct']:.2f}% [{comparison['ci95'][0]:.2f}, {comparison['ci95'][1]:.2f}] | {'통과' if all(x['passed'] for x in checks) else failure} |")
lines += ['', '지연 p50/p95 회귀≤10%, paired CI 하한≥−10%, CPU p95 회귀≤20%, RSS p95≤max(기준×1.10, 기준+32MiB). 기준선과 현재 직렬 경로 양쪽에 적용한다. 누락·중복·비유한 수치·oracle 불일치가 있으면 채택하지 않는다.', '',
          '`overbudget131073`는 상한131072의 경계 입력이며 POSIX fallback을 측정한다. inline metadata는131072개·추정32MiB, 사적 read-ahead는2048개·이름128KiB·metadata512KiB 상한을 유지한다.', '',
          '## 구현과 책임', '',
          '- 한 builder가 node·ID·합계를 소유한다. 다음 폴더의 inline I/O와 미래 sibling 조회를 겹치며, 필요할 때만 최대3개 공유 reader를 시작한다. 기본 병렬도2는 builder+reader1개이며64개 이상 대기 sibling에서만 count probe와 병렬화를 검토한다.',
          '- 이름 정렬·raw UTF-8 namespace 대조·fallback은 OrderedDirectoryReader 한 곳이다. 큰 배치는 첫 정렬 결과를 선형 index로 재사용한다.',
          '- 개요는50ms 이상 걸리는 검사에서만 활성화한다. 이미 수락한 상세 tree를 기하급수 간격으로 소비하며 파일별 hot path에 개요 처리를 넣지 않는다. 큰 폴더16개·파일16개와 cursor만 보유하고 추가 파일시스템 순회가 없다.',
          '- 개요의 observed_nodes는 해당 집계의 출처 범위다. 최근 관측값이며 미확인 영역의 추정 총량이나 삭제 시 회수량을 뜻하지 않는다.', '',
          '## 실제 앱', '']
gui_path = a.proof/'gui-delivery.json'
if gui_path.exists():
    gui = json.loads(gui_path.read_text())
    lines.append(f"GUI 상태: {gui.get('status','진행 중')}; 임시 fixture 정리: {gui.get('removed',False)}.")
    if 'draw_latency_ms' in gui:
        d = gui['draw_latency_ms']
        lines.append(f"실제 native draw 확인 {d['runs']}회: p50 {d['p50']:.2f}ms / p95 {d['p95']:.2f}ms. MCP 전송·polling 시간을 포함한 상한이며 동일 실행 앱의 warm fixture 결과다.")
    lines += ['', *['- '+name+': '+str(value) for name,value in gui.get('checks',{}).items()]]
else: lines.append('GUI 검증 대기. 엔진 callback 시점을 실제 draw 시간으로 간주하지 않는다.')
deployment = a.proof/'deployment.json'
if deployment.exists():
    d = json.loads(deployment.read_text()); lines += ['', '배포 상태: '+d.get('status','기록 없음')+'.', '기본 앱: '+d.get('app','')]
else: lines += ['', '배포 기록 없음.']
lines += ['', '## 근거와 한계', '',
          '- [원시 결과·실행 기록](validation/scan-delivery-2026-11-20/README.md)',
          '- 기존 V1~V6 실패·공간 부족 중단·fixture reset 기록은 보존한다. 동일 후보를 통과할 때까지 반복하거나 실패 시도를 제거하지 않는다.',
          '- 전체 실제1TB 볼륨, 모든 장치·캐시 상태·동적 mount 조합의 보장은 아니다. OS 호출이 멈추면 해당 호출이 돌아온 뒤 취소할 수 있다.', '']
a.output.write_text('\n'.join(lines))
a.output.with_suffix('.json').write_text(json.dumps(result,indent=2)+'\n')
print('PASS' if passed else 'HOLD')
