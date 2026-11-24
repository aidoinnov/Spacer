# disktree의 좋은 구현을 도입하기 위한 원인 분석과 TODO

작성일: 2026-11-20. 상태(2026-11-21): 안전한 할당·합산·표현·read-ahead 개선 및 최종 회귀/GUI/Universal 검증 완료. [정량 성과표](DISKTREE_ADOPTION_RESULTS.md). 아래 초기 원인표는 V9 조사 당시 기록이며, 체크되지 않은 전체 설계 항목은 일부 작업이 끝났어도 미완료다.

## 결론과 범위

현재 배포 V9와 고정 disktree Core를 비교한 90회 측정에서, 우리 기본 병렬도2의 중앙값은 단일 폴더 2만 파일 46.60ms, 200폴더×100파일 33.22ms였다. disktree 4 workers는 각각 21.45ms, 10.46ms로 우리 소요 시간이 2.17배·3.18배였다. 같은 실행의 disktree 1 worker도 각각 21.64ms·23.49ms였다. 따라서 worker 수 차이만으로 전체 격차를 설명할 수 없다.

이는 GUI 제외, warm/unknown cache, 공유 호스트의 작은 일반 파일 입력이다. 실제 앱의 전체 볼륨 스캔도 동시에 실행됐다. 두 엔진의 보유 필드·진행 snapshot 비용이 달라 완전히 같은 작업량은 아니다. 전체 1TB 성능·수백만 파일 메모리 우위를 입증하지 않는다.

근거: [현재 원시 결과와 조건](validation/disktree-2026-11-20/README.md), [90회 원시 표본](validation/disktree-2026-11-20/verification.json), [기존 채택 기준](SCAN_DELIVERY_RESULTS.md).

## 소스 조사 방식

- 오픈소스 원본을 직접 대조한다. 비교 기준은 disktree Core `9b18b272ca3c5a145f6ff58eaf89dc4d311eeaea`이며 원격 최신 버전으로 주장하지 않는다.
- [우리 reader](../Sources/SpaceSnifferCore/OrderedDirectoryReader.swift), [native metadata](../Sources/SpaceSnifferCore/NativeDirectoryMetadata.swift), [scanner](../Sources/SpaceSnifferCore/Scanner.swift), [node](../Sources/SpaceSnifferCore/Model.swift), [합산](../Sources/SpaceSnifferCore/NodeTable.swift)을 [disktree Mac I/O](../References/disktree/source/crates/disktree-core/src/macos.rs), [walk/scheduler](../References/disktree/source/crates/disktree-core/src/scan.rs), [node/합산](../References/disktree/source/crates/disktree-core/src/tree.rs)과 비교했다.
- 리버싱은 배포 바이너리와 확보 소스의 동작 차이가 의심될 때 사용한다. 현재 원인 검토는 소스와 실행 가능한 Core로 가능하므로 디컴파일이 선행 조건은 아니다.
- 코드 복사 시 해당 파일의 MIT 저작권·라이선스 고지를 유지한다. 아이디어 적용과 원문 코드 도입을 변경 기록에서 구분한다.

## 확인된 차이와 아직 검증할 원인

| 항목 | 우리 현재 구현 | disktree 구현 | 확인 수준·가설 |
|---|---|---|---|
| 디렉터리 조회 | 이름 전체 조회·정렬 후 bulk metadata 조회·이름 대조 | bulk iterator로 이름과 metadata를 함께 소비 | 이중 열거는 코드·실행 counter로 확인. 제거 시 절감량은 미측정 |
| 정렬·검증 | 작은 batch 정렬/zip, 큰 batch raw UTF-8 이름 index 생성·대조 | 읽은 entry를 처리하고 최종 트리에서 metric 정렬 | 작업 단계 차이는 확인. 우리 결정적 순서·namespace 검증을 유지하는 대안 필요 |
| 폴더 병렬화 | 단일 builder + 미래 sibling read-ahead, 기본2; 64개 이상 대기 sibling 및 count 64…1024 조건, wave 소진 후 보충 | 폴더 task를 worker에서 실행; 각 폴더 결과를 완료 시 결합 | 구조 차이 확인. builder CPU와 I/O 중 어느 쪽이 제한인지 미측정 |
| 노드 표현 | full path/name, 문자열 fileIdentity, 날짜·native metadata, page 기반 저장 | 이름·트리 관계, 숫자 inode, Node 88-byte 크기 테스트 | 구조 차이 확인. 문자열/배열/작업 트리 포함 실제 RSS 우위는 미입증 |
| 합산 | 파일마다 조상에 delta 전파; 같은 page를 묶어 갱신 | 완료 트리 bottom-up 집계 | 깊이별 작업량 차이 확인. 현재 deep200에서 원인이 지배적이라는 증거는 없음 |
| 버퍼·문자열 | native read마다 64KiB allocate/free, 이름을 Data→String으로 변환, 집합/index 사용 | thread-local 64KiB 버퍼 반환·재사용 | 할당 차이 확인. 시간/메모리 기여도는 profile 필요 |
| metadata 필드 | 생성·접근·수정 시각과 권한 등 기존 기능에 필요한 필드 조회 | 다른 필드 집합 조회; link count 등도 포함 | 서로 필드가 다르며 단순히 불필요하다고 판단하지 않음 |
| 진행 결과 | immutable 상세 snapshot reader + 관측 개요 | 제한된 preview 및 완료 트리 | 비교 작업량 차이. 사용자에게 제공하는 기능을 유지하며 비용 분리 필요 |

현재 원시 결과의 첫 표본에서 flat은 readdir API 20,003회 + bulk 43회, branches는 readdir API 20,803회 + bulk 402회다. stat은 양쪽 입력 모두 1회, bulk 이름 불일치·fallback은 0이었다. branches의 read-ahead 예약/소비는 각각100회다. 따라서 이 정상 입력의 속도 차이를 '아직 매 파일 lstat하기 때문'이라고 설명하면 틀린다. readdir API 호출 수를 커널 syscall 수로 해석하지 않는다.

**정정:** disktree도 실행 중인 폴더를 중간에 쪼개 다른 폴더로 전환하지 않는다. 폴더 내부 pause/resume은 별도 개선 아이디어이며, 상대 앱에서 이미 해결한 기능으로 취급하지 않는다.

## 실행 TODO

### P0 — 기여도와 비교 조건 고정

- [x] A00: 과거5.4배 원시 재계산 및 현재 V9 대 고정 Core 90회 비교. 파일·폴더 수·할당 합계 일치, 소유 fixture 삭제, 소스 archive·binary hash 확인.
- [x] A01: 소스 대조로 이중 열거·순서 검증·제한 병렬화·노드·합산·버퍼 차이 기록. 메모리·공정성 과장 정정.
- [ ] A02: 엔진 단계별 wall/CPU/할당 profile 수집. 이름 읽기, 정렬, bulk decode, 이름 대조, node/path 생성, 조상 합산, publication을 구분하고 중첩 시간은 합산하지 않는다. 병렬 경로는 wall 합과 CPU 합을 구분한다.
- [ ] A03: 양쪽 프로세스의 메모리 측정 시점을 통일한다. 시작 RSS, scan peak, 최종 tree 보유 RSS, 종료까지 process peak를 따로 수집한다. Swift validation/digest 후처리 peak를 Rust scan peak와 직접 비교하지 않는다.
- [x] A04: Swift 1/2/4와 disktree 1/2/4를 같은 입력·순서 교차로 비교한다. full-product 계약과 공통 필드만 쓰는 조사 probe 결과를 분리하며 probe의 이득을 제품 성과로 기록하지 않는다.
- [ ] A05: allocation/CPU stack과 I/O counter로 병목 순위를 정하고 각 변경 전 가설·주요 지표·채택 기준을 고정한다. profile instrumentation 켜짐/꺼짐 오버헤드도 측정한다.

### P1 — 한 번 읽고 필요한 순서로 조립

- [ ] B01: bulk entry 한 번 수집 → 기존 이름 순서로 정렬 → 단일 builder 전달 후보를 작성한다. 별도 readdir 및 이름 hash 대조를 없앨 수 있는 조건을 정의한다.
- [x] B02: 기존 namespace 검증이 방어하던 문제를 먼저 열거한다. 누락/중복, canonical-equivalent 이름, raw UTF-8 구별, 지원하지 않는 이름, metadata 누락/레코드 손상, 읽기 도중 create/delete/rename을 fixture로 검증한다.
- [ ] B03: 전체 metadata 수집 전에 정확한 entry 수를 모르게 되는 문제를 해결한다. 이름/metadata byte 예산, wide 폴더 상한 초과 시 fallback, 이미 처리한 항목 중복 방지, FD 종료 규칙을 명시한다. 한도 초과 후 앞부분을 다시 읽는 비용도 측정한다.
- [x] B04: 노드 ID·형제 순서·SNS/TXT 출력·hardlink 경로별 합산·필터 필드를 기존 계약대로 유지한다. 읽기 순서와 제품 표시/직렬화 순서를 구분하되 기존 결과가 변하면 자동 채택하지 않는다.
- [ ] B05: macOS/filesystem별 metadata 정책과 기존 POSIX fallback을 유지한다. 정상 flat에서 이름 readdir 제거 여부와 전체 latency/CPU/RSS를 동시에 판정한다.

### P2 — 할당·합산 비용 감소

- [ ] C01: reader 전용 scratch buffer 재사용을 단독 비교한다. 동시에 실행되는 reader끼리 버퍼를 공유하지 않고 반환·취소·fallback 후 수명을 검증한다.
- [x] C02: 이름 decoding의 Data 임시 할당, duplicate Set, ordered index의 비용을 profile로 분리한다. raw 이름 구별과 손상 데이터 검사를 유지하는 변경만 후보로 남긴다.
- [x] C03: 조상 delta 대신 directory 완료 집계 또는 batch delta를 후보로 비교한다. 중간 개요와 상세 snapshot에 어떤 값이 확정됐는지 명시하고 취소된 부분 결과·watch 변경 합계도 검증한다.
- [ ] C04: metadata 필드별 소비자를 조사한다. 조회 필드 축소는 필터·export·저장/로드·watch 의미가 유지될 때만 채택한다. 사후 상세 조회가 만드는 추가 I/O와 관측 시점 차이를 포함한다.

### P3 — 분기 처리량 개선

- [ ] D01: builder 처리와 reader 처리의 시간·대기·queue 깊이를 측정한다. reader 수 증가가 실제 병목에 작용하는지 먼저 확인한다.
- [x] D02: wave 보충 정책과 sibling 진입 조건을 각각 독립 변경해 비교한다. 작은 입력·flat·deep에서 worker 시작/entry-count probe가 회귀하지 않도록 한다.
- [ ] D03: 필요하면 폴더 단위 immutable batch 생산을 확대한다. worker는 tree/node ID/상위 합계를 변경하지 않고 builder만 상태를 소유한다. 결과 순서 결정과 backlog byte/entry/FD 예산을 둔다.
- [x] D04: cancellation, queued job 폐기, root 교체, 여러 창 동시 scan, worker drain, admission/I/O permit 교착 여부와 TSAN을 검증한다. worker4 고정 적용을 성공으로 정의하지 않는다.

### P4 — 수백만 노드 메모리와 공정성

- [ ] E01: 10만→100만 노드의 깊이·경로 길이별 RSS 기울기와 파일당 유지 bytes를 측정한다. fixture 구성 비용과 검사 비용을 분리하고, host 여유 공간/메모리 부족이면 실제 범위를 축소해 명시한다.
- [ ] E02: 숫자 device/inode identity 및 경로를 저장하지 않는 내부 표현 후보를 각각 평가한다. 문자열 경로 재구성의 CPU·cache 비용과 snapshot CoW, 필터·navigation·SNS adapter 비용을 함께 측정한다.
- [ ] E03: 노드 저장소와 공개 DiskNode/직렬화 형식을 분리할 필요가 있는지 결정한다. 핵심 저장소 변경을 reader/scheduler 변경과 한 PR/패치에 묶지 않는다.
- [ ] E04: 불균형 분기에서 작은 sibling의 첫 발견·완료 지연을 두 엔진에서 측정한다. 거대 폴더 진입 순서를 뒤집고 총 완료 시간과 별도로 기록한다.
- [ ] E05: 측정상 필요하면 resumable directory cursor를 별도 설계한다. pause 중 FD/버퍼 budget, 재개 시 중복/누락, 정렬/ID 순서, OS 호출 중 취소 한계를 명시한다. 기존 V05와 중복 구현하지 않는다.

## 책임 경계와 레거시 정리

- Native reader: OS API, 레코드 해석, 오류/FD/버퍼 수명만 담당한다.
- Ordered reader: 지원되는 이름 규칙·순서·fallback 계획을 담당한다. UI/집계/scheduler 정책을 넣지 않는다.
- Scheduler: admission, bounded I/O, task/result 예산과 취소를 담당한다. tree를 소유하지 않는다.
- Builder/집계기: ID·node·부모 관계·합계의 유일한 변경 주체다.
- Overview/publication: 이미 수락한 관측값을 제한된 비용으로 노출한다. 파일시스템을 다시 훑지 않는다.
- [x] F01: 공통 계약을 먼저 정한 뒤 교체한다. production 미사용이 증명된 중복 경로만 제거하고, 성능 기준선/실험 소스는 evidence archive로 보존한다.
- [x] F02: 단일 책임을 이유로 per-entry 동적 dispatch·객체·복사를 추가하지 않는다. 책임 경계와 hot-path 비용을 함께 검토한다.

## 정량 테스트와 완료 기준

1. **정확성:** 파일/폴더 수, logical/allocated bytes, 경로별 metadata, canonical digest를 독립 oracle와 대조한다. 안정된 fixture의 deterministic 순서와 SNS/TXT 결과도 확인한다. 동적 fixture는 event 후 수렴과 중복 방지로 별도 판정한다.
2. **입력:** 기존7종(small1000, normal10000, wide4100, wide100000, overbudget131073, tinyfolders1000, deep200)에 기존 disktree2종, 4095/4096/4097·131072 경계, 긴 경로, 불균형 분기, denied/missing/손상 metadata를 추가한다. 대규모 입력은 실제 사용한 노드 수·스토리지 유형을 기록한다.
3. **비교:** 동일 fixture·동일 release 최적화·worker 조건·OS·filesystem·source/binary hash를 고정한다. 순서를 교차하고 warmup, cache 상태, host 부하를 기록한다. 도입 판정용 표본 수는 실행 전에 고정하고 실패한 실행/후보도 남긴다.
4. **수치:** p50/p95 wall, paired 감소율과95% CI, CPU p95, scan peak/retained/process RSS, first overview·작은 sibling 지연, reader/queue/FD peak 및 I/O counter를 원시 결과와 함께 출력한다. 두 엔진 전체 속도와 내부 before/after 개선을 구분한다.
5. **회귀 gate:** 기존처럼 latency p50/p95 회귀≤10%, paired CI 하한≥−10%, CPU p95 회귀≤20%, RSS p95≤max(기준×1.10, 기준+32MiB)를 현 배포 V9 및 후보 직렬 양쪽에 적용한다. 적은 수의 표본으로 gate 통과를 선언하지 않는다.
6. **주요 개선:** 각 후보는 사전 지정한 목표 입력에서 paired CI 하한>0인 시간 개선 또는 명시한 메모리/공정성 개선을 보여야 한다. 단순한 무회귀나 worker 수 증가는 채택 근거가 아니다. 메모리·공정성 목표 수치는 기준선 수집 후 구현 전에 고정한다.
7. **통합:** 관련 Core 테스트, 병렬 변경의 TSAN, 실제 GUI 개요·취소·root 교체·watch, ARM/Intel export/저장 호환을 확인한다. 최종 후보만 전체 검증·패키징하고 기존 버전으로 복구할 수 있게 배포한다.
8. **완료:** 원인별 기여도·채택/기각 근거·최종 disktree 재비교·미해결 항목을 새 성과표에 남긴다. 아직 구현하지 않은 메모리 절감이나 resumable 순회를 완료로 표시하지 않는다.

## 기존 계획 연결

본 문서는 경쟁 엔진과의 남은 격차를 다루는 후속 작업이다. V9 배포 완료를 취소하거나 과거 실패 후보를 숨기지 않는다. B/C/D는 [속도 계획](SCAN_SPEED_TODO.md)의 V02/V03/V07 후속, E는 V05/V06 후속과 연결한다. 영속 캐시 V08은 별도 범위다.


## 2026-11-21 처분과 잔여 TODO

최종 검증은 [성과표](DISKTREE_ADOPTION_RESULTS.md)와 raw/계획/실패 기록을 기준으로 한다. 완성하지 않은 복합 항목은 체크하지 않았다.

| 항목 | 결과·남은 일 |
|---|---|
| A02/A05 | 중첩 phase wall·instrumentation 대조·할당 probe 수집. 완전한 CPU stack/queue 기여도 분해는 남음 |
| A03 | 같은 SDK API/검증 전 지점과 process peak 분리. scan 중간 전 시점의 양 엔진 동등 샘플링은 남음 |
| A04 | Swift1/2/4·disktree1/2/4 및 V9 matrix210회 완료. 공통 필드 probe를 제품 성과로 사용하지 않음 |
| B01/B03/B05 | bulk-first 기각. 기존 namespace·POSIX fallback 유지. count/byte 예산과 상한 초과 동작 검증; 별도 readdir 제거는 미채택 |
| B02/B04 | raw 이름·손상·누락·중복·순열/alias 계약과 기존 기능 테스트, SNS/TXT·watch 통과 |
| C01 | scratch 재사용 독립 비교 미실시 |
| C02/C03 | Data 임시 할당·두 번째 배열 제거, 합산 batching 채택. 부분 publication·취소 합계 검증 |
| C04 | metadata 필드 유지. 소비자 전수 조사/지연 조회 미실시 |
| D01 | worker별 전체 wall/CPU와 일부 실행 counter 확보. builder/reader 대기·queue 전체 profile은 남음 |
| D02 | wave 사이 inline cadence 채택; 기본2 유지,4 고정 기각 |
| D03 | 기존 bounded immutable read-ahead 유지. task 병렬 생산 확대는 미채택 |
| D04 | Core 취소·root/worker 수명·TSAN 및 GUI 취소/root/watch 통과. 새로운 task 생산 구조는 도입하지 않음 |
| E01 | 실제10만 현재/V9, 실제100만 V9/Rust, 합성100만 현재/V9 측정. 최종 실제100만·깊이/길이별 기울기 미완료 |
| E02 | 숫자 identity 채택, public String/JSON 계약 보존. 경로 미보유 표현은 보류 |
| E03 | 이번에는 공개 node와 저장소의 전면 분리를 하지 않음. 별도 설계로 남김 |
| E04/E05 | 불균형 sibling 지연 비교·resumable cursor 미완료. 상대 엔진의 해결 기능으로 간주하지 않음 |
| F01/F02 | 미사용 배열/identity 생성 제거, 작은 값 타입별 책임 분리, 후보/실패 소스 보존. hot path 동적 dispatch 추가 없음 |

- [ ] G01: live root/watch 반복 작업의 발생 사유·빈도와 전체 앱 footprint를 계측한다. issueCount/불완전 issue set에 따른 root escalation, snapshot 수명, utility QoS는 검증할 가설이다.
- [ ] G02: 최종 후보의 실제100만 파일과 불균형 분기 지연을 고정 조건으로 재측정한다. 이번 합성 모델 절감과 구분한다.
- [ ] G03: E04 결과를 바탕으로 cursor/compact path store의 사전 목표와 비용을 정한 별도 설계를 작성한다.


2026-11-21 최신 상태: [shared C3 재확인](DISKTREE_RECHECK_RESULTS.md), [구체적 성능 후속 TODO](DISKTREE_RECHECK_TODO.md). 첫 sibling admission, names-only worker fallback, 큰 node/path store를 새 우선순위로 고정했다. 위 C6 도입 체크를 전체 격차 해소 완료로 해석하지 않는다.
