# 성능 채택 재개 — 2026-11-23

**비교 준비 완료, 환경 진입 실패로 성능 판정·배포는 HOLD.** 이전 [기능·GUI 검증](SCAN_FINAL_GATE_RESULTS.md) 이후 production 소스95개 manifest는 모두 일치한다. 이번에는 production 코드를 바꾸지 않았다.

[상태·남은 조건](validation/scan-performance-2026-11-23/summary.json) · [사전 계획](validation/scan-performance-2026-11-23/plan.json) · [실행 절차](../scripts/bench/scan-review/README.md)

## 완료한 준비와 검증

재부팅 후 이전 `/private/tmp` probe가 사라져, 보존한 V5 archive의 production70개를 SHA로 대조하고 기준 바이너리를 다시 빌드했다. 현재 후보도 동일 toolchain·공통 profile로 release 재빌드했다. 원래 삭제된 바이너리와 같다고 주장하지 않으며 새 binary/source SHA를 기록한다. 최초 최신 진단 profile은 V5에 없는 sampling API를 참조해 컴파일 실패했다. 로그를 보존하고 두 비교 바이너리 모두 호환되는 공통 profile을 사용했다. [동결 확인](validation/scan-performance-2026-11-23/build-verification.json).

비교 스크립트에 `--same-binary-aa`를 추가했다. 두 라벨 모두 같은 candidate SHA와 `parallel4` 모드를 실행하며 output의 `comparison_kind`로 전후 비교와 구분한다. 실제 작은 입력2쌍+warmup1쌍(측정4회·warmup2회)으로 binary/mode 동일성, 전체 oracle/digest, fixture 삭제,20쌍 미만 채택 거부를 확인했다. 이는 스크립트 검증이며100쌍 A/A 또는 성능 통과가 아니다. [확인 결과](validation/scan-performance-2026-11-23/aa-harness-check.json).

새 `run_acceptance.py`는 고정된 환경 검사 → 표준7입력 A/A 각100쌍 → 환경 검사 → V5/수정 직렬/기본 정책 각21쌍 → 환경 검사 순서로 실행한다. warmup은각3쌍이다. 기존 latency·paired CI·CPU·RSS gate를 바꾸지 않았고, 어느 단계든 실패하면 종료한다. 자동 재시도·표본 선별·배포는 하지 않는다. 서로 다른 프로세스·입력 cache 편차까지 A/A가 따로 검증해야 한다.

## 실제 환경 검사

| 구간 | CPU idle | load1 | 메모리 압박 단계 | 결과 |
|---|---:|---:|---:|---|
| 최초5회 |42.5…68.6% |4.5…4.9|2|CPU·압박 기준 실패|
| 빌드 종료 후5회 |원자료 참고 |원자료 참고|2|CPU·load·swap-out·압박 기준 실패|
| 최종 acceptance5회 |29.7…61.8%|13.5…14.8|2|CPU·load·압박 기준 실패|

[최초](validation/scan-performance-2026-11-23/host-initial.json) · [빌드 후](validation/scan-performance-2026-11-23/host-post-build.json) · [최종](validation/scan-performance-2026-11-23/acceptance/host-before-aa.json).

10코어에서 기존 진입 조건인 연속5회 CPU idle≥70%, load1≤10, pressure1, swap-out 증가0, reserve2GiB를 그대로 적용했다. 보수적인 진입 조건이며 그 자체가 성능을 증명하는 기준은 아니다. 당시 다른 프로젝트 빌드와 가상머신 등의 활동을 관측했다. 해당 작업을 임의 정지하지 않았다.

최종 실행은 `host_not_admitted`·exit2로 끝났다. **100쌍 A/A와 표준7입력 성능 비교는 실행하지 않았다.** 실패 원자료와 명령을 보존한다. 이전 성능 gate 실패를 이번 smoke 통과로 덮지 않는다. 기본 설치 바이너리 SHA는 유지됐으며 배포하지 않았다.

## 재개

다른 빌드·무거운 앱을 정리해 환경 조건을 충족한 뒤 아래 명령을 새 output 경로로 실행한다. 이미 생성한 output은 덮어쓰지 않는다. probe는 재부팅 시 사라질 수 있으므로 그때는 공통 profile과 보존 소스로 다시 빌드해야 한다.

```sh
python3 scripts/bench/scan-review/run_acceptance.py \
  --baseline /private/tmp/sniffer-performance-20261123/v5-common \
  --candidate /private/tmp/sniffer-performance-20261123/current-common \
  --output /private/tmp/sniffer-performance-next
```

A/A 전체 기준과 표준 비교 전체 기준을 통과한 다음 기본 설치·배포를 진행한다. GUI/watch의 이전 검증 결과와 이번 성능 검증의 미완료 상태를 구분한다.
