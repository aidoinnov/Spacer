# 지속 공급 read-ahead 결과 — 2026-11-21

후속: [공통 플랫폼 분리·동일 binary A/A 결과](SCAN_PLATFORM_ARCHITECTURE.md). 아래는 C1 완료 시점의 고정 결과이며 이후 shared C2 개발 소스와 구분한다.

**판정: 개발 소스 구현·실험 완료, 기본 배포 HOLD.** 분기 입력에서 개선을 반복 확인했지만 전체 회귀 기준을 통과하지 못했다. 설치된0.2.1의 wave 방식은 유지한다. 현재 작업 소스의 public 기본2는 rolling 후보이므로 일반 build 스크립트를 실행하면 아직 미채택인 후보가 패키징된다.

## 무엇을 바꿨나

기존 read-ahead도 native worker pool을 사용했다. worker를 새로 붙인 것이 아니라 공급 방식을 변경했다. 기존에는 미래 sibling 묶음을 모두 소비한 뒤 보충하고 wave 사이 inline 폴더 하나를 처리했다. 후보는 ticket 하나를 꺼내자마자 다음 작업을 예약하고 현재 ticket을 기다린다. 대기 중에는 worker가 다음 폴더를 읽고, builder는 결과를 기존 DFS 순서대로 반영한다.

완료된 미소비 ticket도 슬롯을 점유한다. 미래 ticket은 concurrency−1개, 소비 중 결과를 포함한 listing은 concurrency개 이내다. 전역 native reader3개·queue24개·I/O permit8개, speculative names2048개/128KiB 및 metadata512KiB 예산을 유지한다. 이 추정 예산은 프로세스 RSS의 강제 상한이 아니다. worker는 tree를 받지 않으며 ID·합산·publication 변경은 기존 단일 builder에 남긴다.

[Scanner 구현](../Sources/SpaceSnifferCore/Scanner.swift), [worker pool](../Sources/SpaceSnifferCore/DirectoryReadAhead.swift), [순서·취소·재보충 테스트](../Tests/SpaceSnifferCoreTests/DirectoryReadAheadTests.swift). 사용하지 않는 wave cadence 타입·테스트는 제거했다.

## 실험과 판정

같은 release Core·입력·순서 교차, 내부 APFS 실제 일반 파일, fresh process, 공유 호스트 조건이다. 우리의 기존 root 앱을 일시 정지하고 finally/watchdog로 복귀했다. 다른 호스트 부하와 cold cache는 통제하지 않았다. GUI·전체1TB 완료 시간이나 disktree와의 최신 재대결 결과가 아니다.

1. 예비7입력×9쌍×4변형=252회. 정확성 일치, 채택 판정에 사용하지 않음.
2. 사전 고정7입력×51쌍×4변형=1,428회. normal10000 기본2는 전 기준 통과. small1000 p95가4.713→5.899ms라 전체 HOLD.
3. worker가 동작하지 않은 작은 입력의 초반 tail을 확인하려고 별도 조건을 고정했다. 모든 변형에 입력별3회 동일 워밍업 후51쌍=1,428회, 별도 검증·보존한 워밍업84회. 앞 실험과 합치지 않았다. 작은 입력은 통과했으나 wide4100 p95가7.495→8.665ms라 다시 HOLD.

모든 표본은 fresh process다. 사전 반복은 OS·파일·실행 이미지 캐시 조건을 맞추는 실험이며 같은 프로세스의 런타임 상태를 재사용하지 않는다.

측정3,108회와 별도 워밍업84회를 모두 보존했다. 실패 표본을 삭제하거나 기준을 완화하지 않았다. 후속 조건이 첫 실행의 tail 불확실성을 해결했다고 주장하지 않는다.

## 동일 워밍업 조건의 수치

| 입력 | 설치0.2.1 기본2 p50 / p95 ms | rolling 기본2 p50 / p95 ms | 기본2 판정 |
|---|---:|---:|---|
| small1000 | 3.608 / 4.404 | 3.604 / 4.011 | 통과 |
| normal10000 | 14.014 / 15.178 | 10.763 / 11.866 | 통과 |
| wide4100 | 7.201 / 7.495 | 7.157 / 8.665 | HOLD: p95 |
| wide100000 | 166.484 / 179.281 | 167.468 / 172.138 | 통과 |
| overbudget131073 | 236.465 / 251.429 | 232.940 / 246.002 | 통과 |
| tinyfolders1000 | 14.588 / 15.754 | 14.484 / 15.743 | 통과 |
| deep200 | 5.555 / 6.005 | 5.593 / 5.958 | 통과 |

normal10000은100폴더×100파일이다. paired 중앙 개선율은 **23.77% [95% CI 22.52, 24.06]**였다. 워밍업 없는 첫 고정 실험에서도24.76% [22.68,25.52]로 같은 방향이었다. 단순 p50 비율과 paired 감소율은 별개다.

이 입력에서 기본2의 CPU p95는20.680→20.558ms, RSS p95는8.781→8.953MiB였다. prefetchUsed는33→98, 최대 동시 directory sections는2→2다. 이 변경의 목표는 같은 동시 I/O 상한에서 준비된 작업을 더 자주 공급하는 것이다. 전체 앱 thread 수가 같다는 뜻은 아니다.

rolling4의 normal10000 p50은6.939ms였지만 CPU p95가25.880ms여서 기준선20.680ms 대비20% 회귀 상한을 넘었다. 후보 직렬18.751ms에 대한 CPU 기준도 미달이다. 4 고정으로 속도만 앞세워 채택하지 않는다.

7입력 전체에서 정확성, latency p50/p95≤기준×1.10, paired CI 하한≥−10%, CPU p95≤기준×1.20, RSS p95≤max(기준×1.10,기준+32MiB)를 실제 설치 기본2 및 후보 직렬 양쪽으로 요구했다. 두 고정 실험 모두 이 전체 조건을 충족하지 못했다.

## 확인된 것과 미해결 원인

기능·총량·digest·순서 계약은 실험 및 테스트에서 일치했다. 모든 측정 입력에서 오류0·취소false를 oracle와 대조했다. controlled gate 테스트는 현재 b8 ticket이 막혔을 때 대기 전에 예약된 b7이 실행되어 풀어 주는지 확인한다. 기존 wave라면 해당 재보충이 일어나지 않는다.

Core 전체301개 실패0, 환경 skip4. TSAN22개 실패0(기존 disposable ad-hoc signed xctest host; 시스템 정책 변경 없음). benchmark/report/warmup 도구11개와 merge8개도 통과했다. warmup의 누락·중복·잘못된 oracle/digest는 판정기에서 HOLD로 처리하고, merge는 워밍업 collection을 묵시적으로 합치지 않도록 거부한다.

small1000과 wide4100 모두 실제 prefetchUsed가0이다. 따라서 관측된 p95 미달을 worker 경쟁 때문에 발생했다고 단정할 수 없다. 소스 구조/코드 배치, 첫 실행 비용, filesystem·호스트 대기 등의 기여도는 아직 분리하지 못했다. p50·CPU가 비슷하다는 이유로 p95 gate를 무시하지 않는다.

## 다음 작업

- 같은 바이너리를 A/A로 비교하는 고정 대조군과 off-CPU/OS I/O 관측으로 tail의 재현성과 호스트 변동을 구분한다. 첫 실행과 워밍업 뒤 지연을 별도 지표로 남긴다.
- 비활성 입력의 inline 경로와 helper 호출 비용은 profile 근거가 있을 때만 변경한다. 현재 결과를 새 후보와 합치거나 통과할 때까지 동일 조건을 반복하지 않는다.
- 전체 회귀 기준을 통과한 뒤에만 최종 GUI/watch·ARM/Intel·패키징·기본 설치를 진행한다. 이번 후보의 최종 GUI와 배포는 미실시다.

[실행 TODO](CONTINUOUS_READ_AHEAD_TODO.md), [사전 계획·원시값·소스·로그](validation/continuous-read-ahead-2026-11-21/README.md).
