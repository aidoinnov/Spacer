# 분석 속도·빠른 개요 검증

**엔진 판정: 기준 통과 · 기본 병렬도2**

입력별 51쌍, 총 1071회. APFS clone files; reported per-path allocated bytes retained. 공유 호스트·warm/unknown cache이며, 파일 내용은 읽지 않는 메타데이터 검사다. 이전 dense-file 실험과 합산하지 않는다.

| 입력 | 기준 p50 / p95 ms | 후보2 p50 / p95 ms | 후보 CPU p95 ms | RSS p95 MiB | paired 감소율 [95% CI] | 판정 |
|---|---:|---:|---:|---:|---:|---|
| small1000 | 4.00 / 4.27 | 3.97 / 4.37 | 3.95 | 5.34 | 1.92% [0.92, 2.76] | 통과 |
| normal10000 | 21.31 / 24.01 | 14.07 / 16.39 | 25.66 | 10.09 | 33.48% [32.68, 34.12] | 통과 |
| wide4100 | 8.80 / 11.04 | 8.47 / 9.08 | 8.78 | 8.17 | 3.44% [2.15, 4.78] | 통과 |
| wide100000 | 213.65 / 222.94 | 219.25 / 244.67 | 242.35 | 86.14 | -2.27% [-3.54, -1.73] | 통과 |
| overbudget131073 | 276.66 / 304.87 | 284.46 / 313.54 | 303.91 | 63.88 | -2.91% [-3.69, -1.98] | 통과 |
| tinyfolders1000 | 13.64 / 14.93 | 13.71 / 14.76 | 14.24 | 6.27 | -0.49% [-2.32, 0.49] | 통과 |
| deep200 | 5.77 / 9.74 | 5.60 / 7.55 | 6.67 | 5.45 | 2.76% [1.02, 5.60] | 통과 |

지연 p50/p95 회귀≤10%, paired CI 하한≥−10%, CPU p95 회귀≤20%, RSS p95≤max(기준×1.10, 기준+32MiB). 기준선과 현재 직렬 경로 양쪽에 적용한다. 누락·중복·비유한 수치·oracle 불일치가 있으면 채택하지 않는다.

`overbudget131073`는 상한131072의 경계 입력이며 POSIX fallback을 측정한다. inline metadata는131072개·추정32MiB, 사적 read-ahead는2048개·이름128KiB·metadata512KiB 상한을 유지한다.

## 구현과 책임

- 한 builder가 node·ID·합계를 소유한다. 다음 폴더의 inline I/O와 미래 sibling 조회를 겹치며, 필요할 때만 최대3개 공유 reader를 시작한다. 기본 병렬도2는 builder+reader1개이며64개 이상 대기 sibling에서만 count probe와 병렬화를 검토한다.
- 이름 정렬·raw UTF-8 namespace 대조·fallback은 OrderedDirectoryReader 한 곳이다. 큰 배치는 첫 정렬 결과를 선형 index로 재사용한다.
- 개요는50ms 이상 걸리는 검사에서만 활성화한다. 이미 수락한 상세 tree를 기하급수 간격으로 소비하며 파일별 hot path에 개요 처리를 넣지 않는다. 큰 폴더16개·파일16개와 cursor만 보유하고 추가 파일시스템 순회가 없다.
- 개요의 observed_nodes는 해당 집계의 출처 범위다. 최근 관측값이며 미확인 영역의 추정 총량이나 삭제 시 회수량을 뜻하지 않는다.

## 실제 앱

GUI 상태: passed; 임시 fixture 정리: True.
실제 native draw 확인 20회: p50 257.47ms / p95 299.07ms. MCP 전송·polling 시간을 포함한 상한이며 동일 실행 앱의 warm fixture 결과다.

- overview_before_completion_and_cancel: True
- exact_detail_and_replacement_generation: True
- create_rename_watch_converged: True
- empty_root_replacement: True

배포 상태: verified_running.
기본 앱: /Volumes/develop/Code/Products/mac-space-sniffer/dist/Mac Space Sniffer.app

## 근거와 한계

- [원시 결과·실행 기록](validation/scan-delivery-2026-11-20/README.md)
- 기존 V1~V6 실패·공간 부족 중단·fixture reset 기록은 보존한다. 동일 후보를 통과할 때까지 반복하거나 실패 시도를 제거하지 않는다.
- 전체 실제1TB 볼륨, 모든 장치·캐시 상태·동적 mount 조합의 보장은 아니다. OS 호출이 멈추면 해당 호출이 돌아온 뒤 취소할 수 있다.
