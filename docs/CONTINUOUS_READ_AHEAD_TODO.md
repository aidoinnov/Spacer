# 지속 공급 read-ahead 실험 — 2026-11-21

목표: 0.2.1의 묶음 read-ahead와 폴더 worker를 결합한 지속 공급 후보를 비교한다. read-ahead 자체도 이미 native worker pool을 사용한다. 비교 대상은 worker 유무가 아니라 scheduler의 공급 방식이다.

## 책임과 예산

- Builder만 tree/ID/합계를 변경한다. 기존 DFS 반영 순서를 유지한다.
- Scheduler는 ticket을 소비할 때 다음 폴더를 예약한다. ticket 대기는 I/O permit 밖에서 한다.
- Worker는 독립 names/metadata 결과만 생산한다. tree나 callback을 소유하지 않는다.
- 완료했어도 미소비 ticket은 window 슬롯을 점유한다. future ticket은 concurrency−1개, 현재 소비 중 결과를 포함한 listing은 concurrency개 이내다.
- 전역 native reader3개, queue24개, I/O permit8개, speculative names2048개/128KiB와 metadata512KiB 예산을 유지한다. 상한 초과는 inline retry다.
- 기존 sibling64개(default2)·첫 entry count64…1024 진입 조건을 유지해 공급 방식 하나를 우선 비교한다.
- 취소 시 queued job 제거 및 자신이 예약한 모든 ticket drain 후 반환한다. 여러 scan이 같은 pool을 공유해도 서로의 job을 취소하지 않는다.

## 실행

- [x] 배포0.2.1 Core와 profile 기준선 동결.
- [x] 소비 즉시 재보충하는 후보 작성. 현재 ticket이 늦어져도 다음 read가 시작되는 결정적 동기화 테스트 추가.
- [x] 관련12개 테스트 통과: 순서/metadata/export, FD·취소·8 scan permit 교착 포함.
- [x] 7입력×9쌍×4변형 예비 비교. 예비 결과로 채택하지 않는다.
- [x] 고정 최종 비교에서 정확성·latency·CPU·RSS 기준을 기준선과 후보 직렬 양쪽에 적용한다. normal10000을 사전 목표 입력으로 두고 paired CI 하한>0도 요구한다.
- [x] 채택 여부와 실패 포함 원시값을 보존하고, 채택 시에만 최종 전체/TSAN/GUI·Universal 배포 검증을 수행한다.

[사전 계획·실험 기록](validation/continuous-read-ahead-2026-11-21/pilot-plan.json). warm/unknown cache·공유 호스트다. 기존 root 앱은 비교 수집 동안에만 SIGSTOP하며 finally/watchdog로 복귀시킨다. 첫 시작 시 binary 완성 전에 benchmark를 실행해 표본 수집 전 실패한 기록도 보존한다.


## 첫 고정 비교 판정

[1,428회 판정](validation/continuous-read-ahead-2026-11-21/final-scorecard.md)은 HOLD다. 기본2의 normal10000은 모든 기준을 통과했지만 small1000 p95가 기준을 넘었다. 4 고정은 normal10000 CPU 및 일부 p95도 미달이다. 이 결과를 삭제하거나 후속 표본과 합치지 않는다.

- [x] 전체301개 실패0(환경 skip4), signed disposable host TSAN22개 실패0.
- [x] 원시값 byte 동일성을 검증한 gzip 보존 및 기준선/후보 source 동결.
- [x] 워밍업 분리 도구2개 통합 테스트: 별도 보관·정확성 검사·실패 시 측정 중단.
- [x] 별도 [warm 계획](validation/continuous-read-ahead-2026-11-21/warm-plan.json): 모든 변형에 동일3회 워밍업 후51쌍. 첫 실행 꼬리 지연의 불확실성은 별도 남긴다.

작은 입력에서 모든 prefetchUsed가0이므로 worker 비용이라고 단정할 수 없다. 처음 몇 pair에 몰린 tail을 확인하기 위한 조건 변경 실험이며 회귀 기준을 완화하지 않는다. 워밍업 표본도 검증·보존하고 measured 표본과 분리한다.


## 최종 상태

[성과표](CONTINUOUS_READ_AHEAD_RESULTS.md): warm 후속도 wide4100 p95 미달로 HOLD. 구현·전체/TSAN/정량 실험은 마쳤고 현재 소스에 후보를 남겼다. 기본 설치0.2.1은 변경하지 않았다. 최종 GUI/Universal 배포는 gate 통과 후에 진행한다.

- [ ] 비활성 입력 tail의 A/A 대조·off-CPU/OS I/O 계측으로 원인 분리.
- [ ] 원인이 확인된 경우에만 새 후보를 작성하고 별도 고정 gate 평가.
- [ ] 전체 gate 통과 후 최종 GUI/watch·Universal 패키징·배포.


2026-11-21 후속: [공통 플랫폼 엔진과 A/A 검증](SCAN_PLATFORM_ARCHITECTURE.md), [새 실행 TODO](SCAN_PLATFORM_TODO.md). A/A와 rusage/SDK I/O는 수집했지만 정확한 off-CPU stack 원인 분리는 남았다. 현재 작업 소스는 이후 shared C2이며 위 C1 기록은 완료 당시의 고정 소스/판정이다.
