# 재검토 정책 비교

macOS의 non-root 사용자로 실행한다. probe는 현재 Core를 같은 module에 넣고 공통 엔진은 별도 package로 빌드한다. 설치 앱을 덮어쓰지 않는다.

```sh
python3 scripts/bench/scan-platform/build_probe.py \
  --profile docs/validation/scan-review-fix-2026-11-21/profile.swift \
  --output /private/tmp/sniffer-review-probe
python3 scripts/bench/scan-review/policy_matrix.py \
  --binary /private/tmp/sniffer-review-probe \
  --output /private/tmp/sniffer-review-policy.json
```

출력·binary가 이미 존재하면 거부한다. 입력은 전용 임시 폴더에 생성하고 finally에서 지운다. 최소 reserve2GiB를 검사한다. tiny1000은100쌍, 나머지6입력은21쌍, 변형4개, warmup3쌍을 수집한다. 네 실행 위치를 회전하며4쌍 단위로 반전해100쌍에서 각 위치25회를 보장한다. 같은 binary/mode 대조군을 포함한다. 소멸 입력은 반복 성능 matrix가 아닌 결정적 제품 테스트에 있다.

프로세스 wall 시간은 검증·digest를 포함한다. `scan_complete_ms`는 engine 시간이다. count query 시간은 native API call 구간이며 전체 admission 비용이 아니다. 실제 수집에서는 별도 identity/watchdog/finally wrapper로 기존 앱을 일시 정지·재개했다. 이 스크립트 자체는 다른 프로세스를 정지하지 않는다. 실제 명령·lease·원자료·실패는 [검증 폴더](../../../docs/validation/scan-review-fix-2026-11-21)에 보존했다.

`--scenarios firstOversized firstDenied`로 입력을 선택할 수 있다. 실제 균등 순서 비교는 watchdog 한도 전에 완료5입력을 보존하고 의도적으로 중단한 뒤 나머지2입력을 별도 lease에서 수집했다. 첫 구간의 미완료 oversized 표본은 최종904회에서 제외했다. 원본 중단 보고서와 합산 규칙은 보존한다.

## 성능 재측정 전 환경 확인

```sh
python3 scripts/bench/scan-review/host_preflight.py \
  --output /private/tmp/sniffer-host-preflight.json
```

기본5개 연속 표본에서 CPU idle≥70%, load1≤논리 코어 수, swap-out 증가0, memory pressure level1, fixture volume reserve2GiB를 모두 요구한다. 이는 수집 전에 정한 보수적인 환경 진입 조건이며 성능 통과 기준을 대체하지 않는다. 실제 A/A·paired CI·p50/p95·CPU·RSS gate도 따로 통과해야 한다. `not_admitted`는 exit2이고 실패 원자료를 보존한다. 자동으로 다른 프로세스를 중지하지 않는다. 새 측정마다 새 output 경로를 사용한다.

GUI 기능 검증은 이 환경에서도 별도로 실행할 수 있으나, 부하가 있는 GUI 관측 시간을 배포용 latency 성과로 사용하지 않는다.

## 동일 바이너리 대조군부터 채택 기준까지 실행

```sh
python3 scripts/bench/scan-review/run_acceptance.py \
  --baseline /private/tmp/sniffer-performance-20261123/v5-common \
  --candidate /private/tmp/sniffer-performance-20261123/current-common \
  --output /private/tmp/sniffer-performance-new-run
```

두 경로는 사전 동결된 release probe다. 재부팅 후 사라지면 보존된 소스와 공통 프로필로 다시 빌드하고 새 SHA를 기록한다.11월23일 재구축 근거는 [검증 폴더](../../../docs/validation/scan-performance-2026-11-23)에 있다.

환경 진입 검사 → 동일 binary/parallel4 A/A(표준7입력 각각100쌍+warmup3쌍) → 환경 재검사 → 표준 V5/직렬/기본4 비교(각21쌍+warmup3쌍) → 환경 재검사 순서다. 어느 단계든 실패하면 그 원자료를 보존하고 종료한다. 자동 재시도·통과 표본 선택·기본 배포는 하지 않는다. A/A와 표준 결과는 input별 전체 gate를 모두 요구한다. 추가로 paired CI·p50/p95·CPU·RSS 기준은 기존 값을 유지한다.

`scan-parallel/compare.py --same-binary-aa`는 두 라벨 모두 candidate 파일의 같은 SHA와 `parallel4` 모드를 실행한다. 출력 `comparison_kind`로 일반 전후 비교와 구분한다. CLI의 `--before` 필수 인수는 호환성을 위해 남지만 A/A 모드에서는 candidate로 양쪽을 고정한다. 입력 순서는 매 pair마다 교대한다.2쌍 smoke는 실제 프로세스·oracle·digest·정리·20쌍 미만 채택 거부를 검증한 것만 의미한다.
