# V01 스캔 재시도 개선 성과

2026-11-19. 권한 오류의 무조건 재시도 제거와 관련 레거시 정리 결과다. V00/V02~V08 전체 완료를 뜻하지 않는다.

## 최종 V2 전후 비교

최초 20 pairs의 경계 근처 p95와 넓은 신뢰구간 때문에, 변경 없는 같은 binary로 사전에 80 pairs 추가 수집을 정했다. 아래는 빠른 표본만 골라내지 않고 총 100 pairs를 합친 결과다. 각 pair는 순서를 교대했다. 공유 호스트·warm/unknown OS cache·release 엔진 시간이며 GUI 또는 전체 볼륨 성과가 아니다.

| 입력 | valid pairs / 실패 실행 | 이전 p50 / p95 ms | V2 p50 / p95 ms | paired 감소율 [95% CI] | RSS p95 이전 → V2 MiB |
|---|---:|---:|---:|---|---:|
| denied20 | 100 / 0 | 2301.31 / 2636.21 | 56.05 / 136.90 | 97.52% [97.22, 97.77] | 8.81 → 8.81 |
| normal-10000 | 100 / 0 | 66.52 / 150.65 | 71.24 / 157.11 | -3.47% [-14.51, 4.25] | 10.27 → 10.23 |

## Gate 판정

| 입력 | 기준 | 판정 |
|---|---|---|
| denied20 | valid | 통과 |
| denied20 | denied_p95_le_200ms | 통과 |
| denied20 | one_open_per_denied_no_wait | 통과 |
| denied20 | rss | 통과 |
| denied20 | cpu_p95_regression_le_20pct | 통과 |
| normal-10000 | valid | 통과 |
| normal-10000 | normal_p50_p95_regression_le_10pct | 통과 |
| normal-10000 | paired_median_ci_not_crossing_minus10 | 미달/보류 |
| normal-10000 | rss | 통과 |
| normal-10000 | cpu_p95_regression_le_20pct | 통과 |

V01 최종 정량 gate: **미달/보류**. 이 판정만으로 실제 GUI·모든 볼륨·다른 최적화 gate를 통과했다고 보지 않는다.

## 구현과 책임

- `ScanRetryPolicy`: errno 결정표, 최대 3회 open·요청 대기 합계 20ms. EINTR 즉시, EAGAIN/EBUSY/ETIMEDOUT만 10ms, 나머지 즉시 오류.
- `POSIXDirectoryReader`: cursor·errno 즉시 캡처·FD cleanup·이름 정렬. POSIX 기본 경로와 bulk fallback이 같은 구현을 사용한다.
- `ScanControl`: 기존 hot cancellation 조회는 NSLock으로 보호하고 retry condition만 분리한다. cancel은 state lock을 해제한 뒤 condition을 깨워 역순 잠금을 피한다.
- 기존 모든 오류 10회 재시도 루프, 고정 Thread.sleep, `lastError!`, scanner 내부 열거 중첩 함수 제거. 오류 문자열의 중복 계산도 제거했다.
- node ID/정렬·집계·볼륨 범위·필터·SNS/TXT·public scanner API·POSIX 기본 backend는 유지한다. 비교/재현에 쓰이는 backend와 과거 archive는 보존한다.

## 정확성·회귀·실패 기록

- before/after 파일·폴더·bytes·오류 수·정규화 필드 digest 일치. denied20은 읽기 가능한 sibling 1개/3 bytes, 오류 20개를 보존한다. 원자적 filesystem snapshot 동등성을 주장하지 않는다.
- [V2 전체 Swift 검사](validation/scan-retry-2026-11-19/full-tests-v2.log): 260개, 명시적 release render probe 1개 skip, 실패 0.
- [V2 TSAN 검사](validation/scan-retry-2026-11-19/tsan-v2-final.log): 20개 통과. 오류/취소/FD·1,000개 admission callbacks·stale scheduling 포함.
- SwiftPM discovery helper는 macOS sanitizer 로딩 정책 때문에 검사 전에 실패했다. disposable ad-hoc xctest copy에서 동일 TSAN bundle을 실행했다. Xcode·system security는 변경하지 않았다. 초기 loader 실패와 XCTest support 경로 실패를 보존했다.
- V1 TSAN의 첫 실행에서 기존 admission stress가 8초 제한을 넘겼다. 변경 없는 재검사와 V2 최종 검사에서는 통과했다. 실패 로그는 삭제하지 않았다.
- 최초 baseline 빌드는 source 수정 중 컴파일해 invalid로 제외했다. 최종 baseline은 immutable before/core archive에서 다시 빌드했다.
- [V1 20-pair 결과](validation/scan-retry-2026-11-19/comparison-20.json)는 latency gate 미달이었다. V2에서 hot lock 복원과 중복 오류 formatting 제거를 수행했다. 원인 전체를 NSCondition 하나로 단정하지 않는다.

## 재현·원시 근거

- [실행 방법](../scripts/bench/scan-retry/README.md)
- [최초 V2 20 pairs](validation/scan-retry-2026-11-19/comparison-v2-20.json)
- [V2 보강 80 pairs](validation/scan-retry-2026-11-19/comparison-v2-supplement80.json)
- [추가 표본 수집 계획](validation/scan-retry-2026-11-19/supplement-plan.json)
- [baseline 빌드 manifest](validation/scan-retry-2026-11-19/comparison-build-manifest.json)
- [V2 source/binary manifest](validation/scan-retry-2026-11-19/after-v2-manifest.json)
- [근거 추적 검사](validation/scan-retry-2026-11-19/engine-evidence.log)
- [실행 TODO](SCAN_SPEED_TODO.md)

패키징·실제 앱 검증 결과는 별도 packaging.json에서 기록한다. 현재 실행 중인 기존 앱과 새 디스크상의 binary 버전을 구분한다.

## 후보 패키지 검증

- [Universal 후보 ZIP](../dist/MacSpaceSniffer-V01-Candidate-universal.zip), [후보 앱](<../dist/Mac Space Sniffer V01 Candidate.app>). 정량 gate가 보류 상태이므로 기본 앱/기존 ZIP을 교체하지 않았다.
- ARM64·x86_64 release 모두 빌드, lipo에서 두 architecture 확인, ad-hoc signature 검증 통과.
- 두 architecture의 실제 CLI에서 3개 denied 폴더+읽기 가능한 파일을 검사해 exit 2, 오류 3개, 파일 1개/3 bytes를 확인했다.
- [실제 GUI 상태](validation/scan-retry-2026-11-19/candidate-ui-status.json): completed_with_issues, 오류 3개, 실제 map item 표시. 전체 GUI 성능 측정을 의미하지 않는다.
- [패키징·hash·cleanup 기록](validation/scan-retry-2026-11-19/packaging.json): 후보 테스트 프로세스 종료·fixture 제거 완료, 기존 기본 binary hash 불변. 기존 사용자 스캔은 유지했다.
