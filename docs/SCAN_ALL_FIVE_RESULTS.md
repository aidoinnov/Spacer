# 스캔 엔진 다섯 개선 — 최종 V5, 2026-11-21

후속 재검토의 취소·경로 동등성·count 계측 결함을 수정하고 [별도 실행 결과](SCAN_REVIEW_FIX_RESULTS.md)에 기록했다. 아래 수치는 수정 전 V5 검증 당시의 기록이다. 배포 HOLD는 유지한다.

다섯 항목을 코드에 반영했다. **정확성 검증은 통과했고 배포 판정은 HOLD**다. 최종7개 입력 중6개가 기존 성능 gate를 통과했다. 작은 폴더1000개 입력은 p95 시간 기준이 실패했고, 같은 C3 바이너리끼리의 대조군도4개 중3개에서 시간/CI 기준을 통과하지 못했다. 따라서 전 입력의 속도 개선을 확정하지 않는다. 설치된0.2.1과 실행 중인 사용자 프로세스는 보존·재개했다.

[최종 측정표](validation/scan-all-five-2026-11-21/v5/MEASUREMENTS.md) · [수치/표본 SHA](validation/scan-all-five-2026-11-21/v5/summary.json) · [검증 상태](validation/scan-all-five-2026-11-21/verification.json) · [남은 TODO](SCAN_ALL_FIVE_TODO.md)

## 반영한 코드

| 개선 | 책임·구현 | 검증 |
|---|---|---|
| 첫 sibling 영구 거부 제거 | 공통 `DirectorySiblingAdmission`에 만료되는 거부 상태. Mac은4후보 표본과64기회 재확인 | tiny-first 혼합 입력에서 사용된 작업0→199; 전부 작은 폴더는 계속 inline |
| worker에서 metadata 완성 | Mac adapter가 bounded bulk/fallback stat 완료. 알려진 mount는 stat 전에 검사. ID/합산은 builder 소유 | 전체 노드·ID·SNS/TXT 비교, mount 제외, stat 실패 재관찰, 취소·FD 종료 |
| node/path 저장 축소 | `NodeOptionalMetadata` presence packing, `NodePathStorage` 부모 문자열 공유, `DiskNodeCoding` wire schema 분리 |192→184byte node. 공개 필드·nil/0/날짜·Windows literal·JSON/SNS·CoW 보존 |
| 수집·정렬·종료 확인 중복 감소 | bounded worker는 bulk collection 하나와 별도 streaming namespace census 사용 | 독립 raw 이름 대조를 유지. sparse candidate는 검증 후에만 사용; 누락 시 원래 fallback |
|64KiB scratch 재사용 | Mac pthread별 take/return. borrow 중 slot 비움, 재진입 별도 buffer, throw 반환, thread-exit destructor | 중첩 호출과 동시 scan/취소·FD 검증, TSAN |

일반 read/stream은 계속 native EOF까지 읽는다. `readCensusCandidate`만 sparse batch를 먼저 반환할 수 있으며 **짧은 반환을 EOF로 가정하지 않는다**. 독립 namespace census가 완전성을 증명하지 못하면 폐기한다. 따라서 OS 열거 두 번은 남는다.

폴더 경로는 frontier·reader·admission에서 재사용하므로 literal로 유지한다. 파일 경로는 부모 문자열을 공유하고, 전체 문자열은 stat·경계/오류 기록·진행 보고 등에 필요할 때 생성한다. native node를 compact storage로 직접 초기화해 완성 경로를 생성했다가 버리던 단계와 임시 migration setter를 제거했다. lstat 실패의 errno는 경로 생성 전에 즉시 보존한다.

최대 작업 수는4다. 같은 부모의64개 이상 폴더 frontier와 적합한64…1024-entry 표본이 있어야 병렬 작업을 시작한다. 작은 frontier·전부 tiny·깊은 단일 분기는 inline 경로를 유지한다. queue24, 공용 reader3, FD/I/O budget8과 cancellation/drain 계약은 유지했다. 공통 queue/admission/control은 OS API 없이 재사용하고 Mac native I/O·QoS·pthread만 adapter에 둔다. Windows native backend 실행은 별도 검증 대상이다.

## 실제 성과와 제한

최종 실제10만 파일, 같은 경로·파일/용량 oracle을 사용하는3쌍:

| 지표 | C3-2 | 최종 최대4 |
|---|---:|---:|
| RSS 중앙값 | 41.58MiB | 28.06MiB |
| footprint 중앙값 | 39.86MiB | 26.22MiB |

footprint는 이 입력에서 **34.2% 감소**했다. 최종 재측정은 외부 APFS에서 수행했다. 내부 디스크의5GiB reserve 중단은 표본0개 실패로 보존했고, 완료된 자체 test build cache 약817MiB를 정리한 뒤10만 파일에 한해 외부 backing/reserve2GiB를 명시해 별도 실행했다. 모든 측정용 파일과 전용 부모 폴더를 삭제했다.

100만 파일은 V1에서 실제3쌍 측정했다: footprint314.33→205.53MiB, RSS99.94→132.12MiB. 이는 [V1 결과](validation/scan-all-five-2026-11-21/MEASUREMENTS.md)이며 V5 실측으로 치환하지 않는다. RSS와 footprint 방향이 달랐던 결과도 보존했다. 수치는 엔진과 retained progress reader의 사용량이며 GUI 전체 메모리는 별도다.

최종21쌍 비교에서 보통 분기 입력(normal10000)은 paired 중앙값34.28% 개선(95% CI18.88…37.45), gate 통과였다.20k worker matrix의 p50은 분기200×100에서22.109→16.615ms, tiny-first 혼합에서38.877→22.619ms였다. 다만 A/A 신뢰도 문제가 있어 이 시간 차이를 모든 실행 환경의 확정적 개선으로 일반화하지 않는다.

정확히 재현된 counter는 분기 입력의 bulk 호출402→203, tiny-first 혼합의 stat101→2·bulk202→201이다. readdir 순회는 유지하며 이 수치를 모든 kernel syscall의 총합으로 표현하지 않는다. 고정 disktree4는 같은 matrix에서 분기10.358ms, flat21.602ms였으므로 격차가 모두 사라진 상태도 아니다. 두 엔진의 필드·발행 비용은 다르다.

검증·digest 등을 포함한 전체 process wall 시간도 저장했다. 예를 들어 wide100000은321.25→381.21ms였다. 이는 GUI 시간은 아니지만 경로 재구성 비용을 추가로 검토할 근거다. V4→V5 ablation의 시간 CI도 통과하지 못해 임시 경로 제거의 속도 기여를 단독 확정하지 않는다.

## 검증과 채택 기준

- 최종 전체 프로젝트309개: 실패0, 명시적 performance fixture 등4skip. 공통 debug/release각19개: 실패0.
- 최종 Mac TSAN27개, source가 변하지 않은 공통 TSAN19개: 실패/경합0.
- ARM/Intel9600파일 oracle, TXT bytes 일치, SNS 저장 및 양쪽 architecture load 통과.
- 외부 consumer의 ticket wait 허용·생성/완료 금지 컴파일 검사,70 engine files/78 contracts/309 원본 근거·10 portable production files 경계 검사.
- 최종21쌍×7표준 입력, 별도 warmup2쌍. worker4입력×21쌍×7변형, 별도 warmup2쌍. 고정 disktree revision `9b18b272ca3c5a145f6ff58eaf89dc4d311eeaea` 비교.

기존 기준은 p50/p95≤1.10배, paired95% CI 하한≥−10%, CPUp95≤1.20배, RSSp95≤max(1.10배,+32MiB), 최소20쌍이다. 최종7입력 모두 CPU/RSS 기준은 통과했다. tinyfolders1000은 p50 16.166→16.719ms, p95 17.234→20.355ms로 시간 gate가 실패했다. 대조군도 흔들리므로 원인을 확정하지 않았으며 gate를 완화하지 않는다.

V1의 deep CPU 실패, V2 directory literal 수정, V3 검증된 sparse tail, V4 frontier64/최대4 정책, V5 lazy child path의 source·결과·실패를 전부 보존했다. 최종 source manifest와 현재 코드75개 항목 일치, 측정 binary SHA·raw gzip SHA·fixture 삭제·앱 재개를 확인했다.

남은 채택 조건은 안정적인 A/A와 tinyfolders p95 기준, 경로를 많이 소비하는 검증/필터/내보내기 CPU, 최종 GUI/watch 확인이다. 거대한 한 폴더 중간에서 다른 분기로 전환하는 선점과 Windows native 실행은 별도 후속이다. 배포는 이러한 결과를 통과한 뒤 진행한다.
