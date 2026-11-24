# 빠른 개요 + 상세 스캔 성과표

2026-11-16. **엔진 후보 구현·실측 완료 범위만 보고한다. 앱 기본 backend는 POSIX이며 GUI·캐시·증분 통합은 미완료다.**

[실행 TODO](PROGRESSIVE_SCAN_TODO.md) · [테스트 계획](PROGRESSIVE_SCAN_TEST_PLAN.md) · [재현 명령](../scripts/bench/progressive-scan/README.md)

## 실제 release 엔진 전후 성과

S01=1천 파일/50폴더, S02=10만 파일/5천 폴더, S03-숫자=한 폴더의 해당 파일 수, S04=64단계 깊이, S05/S06=작은 파일 99,990개+32MiB 파일 10개의 큰 분기 방문 순서 역전, S07=한 분기에 9만 파일이 몰린 입력이다.

동일 물리 fixture를 순서를 바꿔 fresh process로 반복했다. 각 셀은 독립 POSIX oracle의 경로·종류·identity·크기·일부 속성 checksum과 합계를 확인한다. OS metadata cache는 oracle에 의해 warm/unknown 상태다. 공유 호스트 부하가 있어 paired CI와 원시 결과를 함께 본다.

| 시나리오 | 유효 pairs | 기존 p50 / p95 ms | streaming p50 / p95 ms | p50 감소율 | paired 감소율 [95% CI] | RSS 기존 → 후보 MiB |
|---|---:|---:|---:|---:|---|---:|
| S01 (exploratory) | 5 | 13.29 / 45.40 | 10.04 / 15.85 | 24.45% | -19.26% [-59.10, 87.19] | 6.02 → 5.98 |
| S02 (paired-20) | 20 | 858.12 / 1441.08 | 606.81 / 893.35 | 29.29% | 33.02% [16.79, 39.15] | 47.02 → 47.36 |
| S03-100000 (guarded-20) | 20 | 322.13 / 466.78 | 223.06 / 389.58 | 30.75% | 30.60% [25.50, 32.57] | 47.92 → 52.86 |
| S03-4095 (paired-20) | 20 | 24.82 / 34.70 | 13.58 / 31.40 | 45.31% | 44.06% [37.39, 49.20] | 7.07 → 7.33 |
| S03-4096 (paired-20) | 20 | 22.18 / 43.32 | 12.91 / 30.09 | 41.77% | 46.00% [26.84, 51.14] | 7.24 → 7.33 |
| S03-4097 (paired-20) | 20 | 36.28 / 102.57 | 22.72 / 58.13 | 37.38% | 33.98% [-6.96, 60.89] | 7.36 → 7.48 |
| S03-4100 (exploratory) | 5 | 41.86 / 145.54 | 23.56 / 27.12 | 43.73% | 47.09% [-12.40, 82.74] | 7.38 → 7.64 |
| S04 (exploratory) | 5 | 14.17 / 27.01 | 12.92 / 43.34 | 8.82% | 8.82% [-60.49, 38.73] | 6.30 → 6.62 |
| S05 (guarded-20) | 20 | 367.76 / 498.36 | 224.18 / 555.03 | 39.04% | 39.43% [36.50, 41.01] | 46.67 → 47.48 |
| S06 (guarded-20) | 20 | 470.13 / 706.62 | 306.18 / 482.25 | 34.87% | 34.09% [30.30, 41.13] | 47.06 → 48.09 |
| S07 (guarded-20) | 20 | 523.30 / 595.29 | 298.07 / 490.54 | 43.04% | 41.77% [38.34, 47.76] | 50.20 → 50.82 |

각 행의 기존/후보는 같은 볼륨·binary 조건에서 비교했다. exploratory/paired-20은 APFS image, guarded-20은 시스템 임시 폴더이므로 서로 다른 행의 절대 시간을 직접 비교하지 않는다. p50 감소율은 두 중앙값의 비율이고 paired 감소율은 각 pair 감소율의 중앙값이므로 서로 다를 수 있다. 5-pair 셀은 탐색 결과이며 채택 표본 기준 20 pairs에 미달한다.

## 첫 유용한 결과: 엔진 proxy와 화면 측정 구분

| 시나리오 | callback proxy p50 기존 → 후보 ms | 실제 화면 useful overview |
|---|---:|---|
| S01 | 13.28 → 10.03 | 미측정 |
| S02 | 858.63 → 603.07 | 미측정 |
| S03-100000 | N/A → N/A | 미측정 |
| S03-4095 | N/A → N/A | 미측정 |
| S03-4096 | N/A → N/A | 미측정 |
| S03-4097 | N/A → N/A | 미측정 |
| S03-4100 | N/A → N/A | 미측정 |
| S04 | 14.16 → 12.90 | 미측정 |
| S05 | 367.75 → 224.17 | 미측정 |
| S06 | 470.11 → 306.12 | 미측정 |
| S07 | 523.28 → 298.06 | 미측정 |

proxy는 top-k recall≥90%, byte error≤20%, 현재 관측 coverage≥70%를 이후 callback에서도 유지하는 최초 엔진 publication이다. 실제 draw와 1초 visible hold는 측정하지 않았다. direct-child 폴더가 없는 wide 입력은 N/A이며 0ms가 아니다.

## 정확성·채택 판단

| 항목 | 상태 |
|---|---|
| 선택된 엔진 비교 실행 | 525회, 실패·oracle 불일치 0회 |
| searchfs 상세 backend | 채택 보류: 실제 APFS 필드 oracle에서 symlink/FIFO 종류가 일반 파일로 반환되고 link 논리 크기가 기존 규칙과 다름 |
| 실제 develop catalog 조회 | 동일 inode·동일 alias record 반복을 감지하여 명시적으로 실패 처리 |
| GUI p50 ≥50%·p95 ≥30% 단축 | 미측정: 엔진 개선율을 GUI 성과로 대체하지 않음 |
| 캐시·FSEvents·동시 창·입력 지연·장시간 수명 | 미실행 |
| 최종 채택 | 전체 gate 미완료, POSIX 기본값 유지 |

## 원시 근거

- [exploratory 반복 실측 JSON](validation/progressive-scan-2026-11-16/exploratory/report.json): measured_engine_only, binary `72398a09a5a41683`
- [guarded-20 반복 실측 JSON](validation/progressive-scan-2026-11-16/guarded-20/report.json): measured_engine_only, binary `7c8b92540dd8d898`
- [paired-20 반복 실측 JSON](validation/progressive-scan-2026-11-16/paired-20/report.json): stopped_low_backing_space, binary `72398a09a5a41683`
- [전체 검증·I/O 호출 성과·중단/정리 기록](validation/progressive-scan-2026-11-16/README.md)
- [catalog 필드 실패 근거](validation/progressive-scan-2026-11-16/catalog-fields.json)
- [실제 볼륨 catalog 결과](validation/progressive-scan-2026-11-16/catalog-live.json)
- [호스트 동시 부하](validation/progressive-scan-2026-11-16/host-context.json)
- [측정 당시 소스 manifest](validation/progressive-scan-2026-11-16/source-manifest.json)

다음 단계는 개요용 상태·공정한 순회·상세 보정과 실제 화면 계측이다. 여기의 엔진 결과만으로 전체 계획 완료 또는 앱 가속 적용을 선언하지 않는다.
