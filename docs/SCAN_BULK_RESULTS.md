# V02 메타데이터 배치 조회 성과

2026-11-19. V01 재시도 개선을 포함한 자동 선택 후보. 같은 V4 binary의 POSIX와 비교해 V02를 분리하고, 이전 앱의 고정 binary와도 비교했다.

정량 gate: **미달/보류**. 기본 20 pairs/입력, small1000은 100 pairs. 세 변형 실행 순서 교대. 공유 호스트·warm/unknown OS cache·릴리스 엔진 완료 시간이며 GUI/전체 볼륨 성과가 아니다.

| 입력 | V01 POSIX p50 / p95 ms | 자동 배치 p50 / p95 ms | paired 감소율 [95% CI] | RSS p95 이전 → 배치 MiB | 판정 |
|---|---:|---:|---|---:|---|
| small1000 | 5.25 / 9.40 | 5.00 / 10.26 | 5.36% [3.45, 7.99] | 5.89 → 6.25 | 통과 |
| normal10000 | 52.39 / 64.74 | 38.21 / 47.71 | 30.27% [17.13, 36.63] | 10.11 → 10.56 | 통과 |
| wide4100 | 21.88 / 27.80 | 13.48 / 22.67 | 31.80% [15.86, 44.32] | 7.14 → 8.05 | 통과 |
| wide100000 | 269.66 / 299.70 | 232.64 / 255.48 | 11.51% [11.03, 14.87] | 55.81 → 73.45 | 통과 |
| overbudget131073 | 376.36 / 440.47 | 364.89 / 425.85 | 2.83% [0.16, 4.96] | 64.17 → 64.19 | 통과 |
| denied20 | 21.14 / 31.98 | 20.33 / 21.57 | 2.39% [-1.72, 9.93] | 7.97 → 7.39 | 통과 |
| tinyfolders1000 | 17.94 / 25.73 | 17.21 / 24.20 | 3.61% [2.12, 5.11] | 5.91 → 6.03 | 통과 |
| deep200 | 6.32 / 8.52 | 6.34 / 6.48 | -0.36% [-2.58, 6.17] | 5.19 → 5.02 | 통과 |

기준: 완료 p50/p95 회귀 ≤10%, paired median 95% CI 하한 ≥−10%, CPU p95 회귀 ≤20%, RSS p95 ≤max(POSIX×1.10, POSIX+32MiB), denied20 p95 ≤200ms. 모든 시도·pair가 정확성 검증을 통과해야 한다.

## 이전 앱과 비교

| 입력 | 기존 p50 → 후보 p50 ms | paired 감소율 [95% CI] | 판정 |
|---|---:|---|---|
| small1000 | 5.25 → 5.00 | 3.57% [1.98, 6.40] | 보류 |
| normal10000 | 51.99 → 38.21 | 27.81% [18.73, 37.79] | 통과 |
| wide4100 | 18.96 → 13.48 | 26.32% [18.35, 35.76] | 통과 |
| wide100000 | 264.20 → 232.64 | 11.89% [9.55, 13.54] | 통과 |
| overbudget131073 | 372.50 → 364.89 | 0.71% [-1.42, 3.60] | 통과 |
| denied20 | 2099.29 → 20.33 | 99.05% [99.02, 99.08] | 통과 |
| tinyfolders1000 | 17.87 → 17.21 | 2.93% [1.99, 6.86] | 통과 |
| deep200 | 6.19 → 6.34 | -1.30% [-3.76, 2.33] | 통과 |

V02 단독 비교: 8개 입력 통과. 전체 채택은 이전 앱 비교도 모두 통과해야 한다. 남은 미달 항목:

- small1000 / original: latency.

small1000은 최초20+사전 고정80 pairs를 모두 합쳤다. 원시 보강 측정은 [comparison-v4-small80.json](validation/scan-bulk-2026-11-19/comparison-v4-small80.json), 계획은 [v4-small-supplement-plan.json](validation/scan-bulk-2026-11-19/v4-small-supplement-plan.json)이다. 기존 S01 제품 계획은 50ms 절대 예산을 허용하지만, 이번 수집 전에 고정한 더 엄격한 10% 기준을 사후에 완화해 채택하지 않았다.

개별 V01의 과거 CI 보류 판정은 유지한다. 이번 판정은 변경된 V01+V02 후보에 한정한다. 실패·느린 표본을 제외하거나 이전 시리즈를 임의로 합치지 않았다.

## 구현·정확성·한계

- POSIX 이름 열거/정렬을 먼저 수행하고, 16~131,072개 및 추정 32MiB 예산 안에서만 native metadata를 수집한다. 너무 작거나 큰 폴더는 prefix 조회 없이 POSIX를 사용한다.
- 두 목록의 raw UTF-8 이름이 일치할 때만 metadata를 원래 순서로 사용한다. 실패·불일치는 첫 이름 목록을 재사용해 lstat하며 두 번째 readdir를 피한다.
- `ScanMetadataPolicy`가 실행 내 device별 local APFS 여부를 판정한다. 중첩 mount는 별도로 판정하고 미지원·remote·판정 실패는 POSIX다. 범위 축소로 얻은 속도 차이는 없다.
- parser와 예산은 `NativeDirectoryMetadata`, FD/errno/retry는 `POSIXDirectoryReader`와 `ScanRetryPolicy`, tree/합계는 기존 단일 scanner worker가 소유한다. model 필드·정렬·export 형식은 추가하지 않았다.
- 예산은 추정치이며 hard RSS 제한이 아니다. 10만 파일 셀의 실제 RSS를 위에 보고했다. 두 번의 디렉터리 열거는 atomic snapshot이 아니며 rename 경합 시 오류/부분 결과를 보존하고 다음 스캔의 수렴을 검사했다.
- V2 탐색에서 tinyfolders/deep가 회귀해 V3에서 16개 미만을 건너뛰었다. V3의 wide RSS gate 미달로 V4에서 정확한 count로 배열을 예약하고 검증한 이름 목록을 먼저 해제했다. 각 후보의 실패 근거와 고정 20-pair 시리즈를 보존했다.
- 이전 streaming/adaptive backend는 benchmark·회귀 비교에 사용 중이므로 보존한다. obsolete retry/sleep/강제 unwrap 제거는 V01에서 완료했다.

원시 측정: [comparison-v4-20.json](validation/scan-bulk-2026-11-19/comparison-v4-20.json). 소스·테스트·TSAN·패키징 근거: [검증 기록](validation/scan-bulk-2026-11-19/README.md). 재현: [실행 방법](../scripts/bench/scan-bulk/README.md).
