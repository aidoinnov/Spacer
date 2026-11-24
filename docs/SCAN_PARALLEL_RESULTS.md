# V03 디렉터리 병렬 읽기 측정

판정: **기본 적용 보류**.

수집·정리·최소 표본 조건: 충족.

입력별 100쌍. 같은 범위·같은 파일, 릴리스 엔진, 공유 호스트, warm/unknown cache. GUI 완료 시간이나 실제 전체 볼륨 속도를 의미하지 않는다.

| 입력 | 변형 | 유효 / 시도 | p50 / p95 ms | CPU p95 ms | RSS p95 MiB |
|---|---|---:|---:|---:|---:|
| small1000 | before | 100 / 100 | 10.37 / 30.23 | 10.89 | 7.06 |
| small1000 | serial | 100 / 100 | 10.80 / 34.81 | 10.91 | 7.11 |
| small1000 | parallel2 | 100 / 100 | 11.77 / 41.99 | 10.87 | 7.12 |
| small1000 | parallel4 | 100 / 100 | 11.84 / 29.85 | 11.63 | 7.12 |
| normal10000 | before | 100 / 100 | 48.65 / 92.23 | 49.13 | 10.52 |
| normal10000 | serial | 100 / 100 | 49.27 / 89.68 | 50.83 | 10.53 |
| normal10000 | parallel2 | 100 / 100 | 64.30 / 195.43 | 61.35 | 10.78 |
| normal10000 | parallel4 | 100 / 100 | 28.96 / 67.47 | 53.38 | 10.89 |
| wide4100 | before | 100 / 100 | 21.21 / 46.77 | 18.45 | 8.61 |
| wide4100 | serial | 100 / 100 | 21.58 / 53.30 | 18.81 | 8.58 |
| wide4100 | parallel2 | 100 / 100 | 23.37 / 53.24 | 19.09 | 8.62 |
| wide4100 | parallel4 | 100 / 100 | 21.03 / 48.61 | 18.48 | 8.61 |
| wide100000 | before | 100 / 100 | 493.82 / 1403.35 | 402.01 | 67.59 |
| wide100000 | serial | 100 / 100 | 478.70 / 1208.81 | 406.73 | 67.41 |
| wide100000 | parallel2 | 100 / 100 | 521.93 / 1286.77 | 406.94 | 67.83 |
| wide100000 | parallel4 | 100 / 100 | 549.26 / 1422.72 | 398.54 | 67.39 |
| overbudget131073 | before | 100 / 100 | 1071.26 / 3066.01 | 627.09 | 60.91 |
| overbudget131073 | serial | 100 / 100 | 1085.91 / 2841.77 | 642.24 | 60.78 |
| overbudget131073 | parallel2 | 100 / 100 | 1099.57 / 3361.71 | 637.68 | 61.05 |
| overbudget131073 | parallel4 | 100 / 100 | 965.63 / 3155.04 | 622.54 | 60.30 |
| tinyfolders1000 | before | 100 / 100 | 43.84 / 98.57 | 35.29 | 7.45 |
| tinyfolders1000 | serial | 100 / 100 | 45.67 / 81.55 | 36.06 | 7.48 |
| tinyfolders1000 | parallel2 | 100 / 100 | 42.45 / 75.89 | 35.39 | 7.45 |
| tinyfolders1000 | parallel4 | 100 / 100 | 45.63 / 98.82 | 35.31 | 7.47 |
| deep200 | before | 100 / 100 | 14.18 / 31.50 | 14.35 | 6.67 |
| deep200 | serial | 100 / 100 | 13.36 / 32.18 | 14.49 | 6.72 |
| deep200 | parallel2 | 100 / 100 | 14.45 / 29.37 | 14.44 | 6.75 |
| deep200 | parallel4 | 100 / 100 | 14.34 / 35.77 | 14.10 | 6.72 |

| 입력·비교 | paired 감소율 [95% CI] | 판정 |
|---|---:|---|
| small1000 · serial_vs_before | 1.68% [-10.01, 15.41] | 보류: latency, paired_ci |
| small1000 · parallel2_vs_before | -7.19% [-30.24, 5.27] | 보류: latency, paired_ci |
| small1000 · parallel2_vs_serial | -6.82% [-26.54, 5.71] | 보류: latency, paired_ci |
| small1000 · parallel4_vs_before | -15.37% [-29.63, -6.50] | 보류: latency, paired_ci |
| small1000 · parallel4_vs_serial | -8.96% [-22.81, 5.00] | 보류: paired_ci |
| normal10000 · serial_vs_before | -0.33% [-12.05, 10.17] | 보류: paired_ci |
| normal10000 · parallel2_vs_before | -38.45% [-56.37, -20.18] | 보류: latency, paired_ci, cpu |
| normal10000 · parallel2_vs_serial | -37.29% [-49.87, -27.03] | 보류: latency, paired_ci, cpu |
| normal10000 · parallel4_vs_before | 42.33% [32.79, 47.94] | 통과 |
| normal10000 · parallel4_vs_serial | 35.21% [30.29, 44.24] | 통과 |
| wide4100 · serial_vs_before | 1.97% [-6.98, 10.80] | 보류: latency |
| wide4100 · parallel2_vs_before | -7.72% [-20.66, 2.98] | 보류: latency, paired_ci |
| wide4100 · parallel2_vs_serial | -1.23% [-15.81, 9.46] | 보류: paired_ci |
| wide4100 · parallel4_vs_before | 2.39% [-23.62, 10.12] | 보류: paired_ci |
| wide4100 · parallel4_vs_serial | -0.03% [-10.43, 12.45] | 보류: paired_ci |
| wide100000 · serial_vs_before | 5.03% [-4.46, 9.88] | 통과 |
| wide100000 · parallel2_vs_before | 3.58% [-2.48, 10.13] | 통과 |
| wide100000 · parallel2_vs_serial | -4.92% [-10.70, 2.55] | 보류: paired_ci |
| wide100000 · parallel4_vs_before | -8.46% [-16.34, -0.25] | 보류: latency, paired_ci |
| wide100000 · parallel4_vs_serial | -8.04% [-15.92, 0.93] | 보류: latency, paired_ci |
| overbudget131073 · serial_vs_before | -4.06% [-12.05, 5.37] | 보류: paired_ci |
| overbudget131073 · parallel2_vs_before | -4.49% [-14.01, 6.20] | 보류: paired_ci |
| overbudget131073 · parallel2_vs_serial | 2.98% [-11.09, 10.46] | 보류: latency, paired_ci |
| overbudget131073 · parallel4_vs_before | 0.04% [-7.74, 11.49] | 통과 |
| overbudget131073 · parallel4_vs_serial | 5.83% [-2.64, 16.23] | 보류: latency |
| tinyfolders1000 · serial_vs_before | -4.04% [-12.32, 0.91] | 보류: paired_ci |
| tinyfolders1000 · parallel2_vs_before | -1.34% [-14.98, 9.57] | 보류: paired_ci |
| tinyfolders1000 · parallel2_vs_serial | 8.07% [-1.73, 12.00] | 통과 |
| tinyfolders1000 · parallel4_vs_before | -4.01% [-12.05, 4.72] | 보류: paired_ci |
| tinyfolders1000 · parallel4_vs_serial | -4.21% [-10.88, 10.93] | 보류: latency, paired_ci |
| deep200 · serial_vs_before | 1.94% [-10.70, 17.47] | 보류: paired_ci |
| deep200 · parallel2_vs_before | -3.07% [-16.38, 8.90] | 보류: paired_ci |
| deep200 · parallel2_vs_serial | -6.74% [-20.10, 0.07] | 보류: paired_ci |
| deep200 · parallel4_vs_before | 3.39% [-3.63, 14.71] | 보류: latency |
| deep200 · parallel4_vs_serial | -12.24% [-25.99, 2.06] | 보류: latency, paired_ci |

모든 시도를 포함해 원시 결과에서 재계산한다. 7개 입력 전체와 최소20쌍, 결과 digest·파일/폴더/크기 일치, p50/p95 회귀≤10%, paired bootstrap CI 하한≥−10%, CPU p95 회귀≤20%, RSS p95≤max(기준×1.10, 기준+32MiB)를 요구한다.

## 실제 read-ahead 활성화

`parallel4`는 병렬도 상한 설정이다. 모든 입력에서4개 reader가 실행됐다는 뜻은 아니다.

| 입력 | parallel4 prefetch 수락 최소~최대 | 최대 동시 directory sections |
|---|---:|---:|
| small1000 | [0, 0] | 1 |
| normal10000 | [100, 100] | 4 |
| wide4100 | [0, 0] | 1 |
| wide100000 | [0, 0] | 1 |
| overbudget131073 | [0, 0] | 1 |
| tinyfolders1000 | [0, 0] | 1 |
| deep200 | [0, 0] | 1 |

현재 public scanner concurrency는1이다. 작은 입력·단일 폴더·깊은 트리의 회귀로 기본 앱과 Scope 후보 앱은 유지한다. V03 실제 GUI/watch 수렴·패키징과 V04 경량 개요는 미완료다.

병렬 read-ahead가 비활성인 입력에서도 회귀가 관측됐다. 다음 조사 대상은 추가 directory-count hint와 공통 처리 경로의 비용이다. 원인별 비용 분리는 아직 측정하지 않았다.

[설계·소유권](SCAN_PARALLEL_DESIGN.md) · [원시 결과·테스트·정리 기록](validation/scan-parallel-2026-11-19/README.md) · [재현 명령](../scripts/bench/scan-parallel/README.md)
