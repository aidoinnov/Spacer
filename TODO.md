<!-- GPUI current status: docs/GPUI_COMPLETION_RESULTS.md -->

최신 GPUI 작업 결과와 남은 완료 조건: [GPUI_COMPLETION_RESULTS.md](docs/GPUI_COMPLETION_RESULTS.md). Mac/Windows GPUI 0.3.0 설치·주요 기능·실제 watch 검증 완료. OS 입력 전체·장시간 검수는 해당 결과의 미완료 항목을 따른다.

2026-11-23 추가 후속: [볼륨 범위·Windows preview·SNS 검증 결과](docs/GPUI_PREVIEW_SCOPE_RESULTS.md). Mac 실제 중첩 mount 100→6100→100개, Core285/Domain4/Rust16 통과. Windows preview 구현/교차 검사 완료, 132 PC 연결 불가로 실제 실행·정식 배포는 미완료.

2026-11-23 GPUI 후속: [문서·필터·태그 이식 결과](docs/GPUI_DOCUMENT_RESULTS.md). 원본 Swift SNS/DU/필터/기본 보고서 공유, metadata, Mac Quick Look, SNS 선택·취소, 경로 IPC 압축을 반영. 전체 이식·정식 배포 완료와 구분하며 [기능별 남은 항목](docs/GPUI_FEATURE_PARITY.md)을 따른다.

# Mac Space Sniffer — 최적화 실행 명세와 TODO

2026-11-23 GPUI 이식 진행 중: [기존 UI·애니메이션 보존과 미완료 목록](docs/GPUI_MIGRATION_TODO.md). 기존 엔진 재사용, 공통 GPUI 화면과 500ms 전환을 구현했으며 전체 기능 동등성·최종 교체는 아직 완료하지 않았다.


2026-11-21 최신 재확인: [C3 대 disktree 실측·남은 개선점](docs/DISKTREE_RECHECK_RESULTS.md), [우선순위 TODO](docs/DISKTREE_RECHECK_TODO.md). 513회 비교+warmup84회에서 속도/메모리 격차를 재확인했고, 첫 sibling에 따라 worker 수락이0/198로 달라지는 admission 맹점을 확인했습니다. 이번에는 production 동작·설치 앱을 변경하지 않았습니다.
2026-11-21 C3 품질 검토: [red/green 결과·수명/API 계약](docs/SCAN_ENGINE_QUALITY.md). 재현된 두 결함을 수정했으며 Windows native 검증과 전체 성능/배포 gate는 별도 유지한다.
2026-11-21 플랫폼 후속: [설계·검증](docs/SCAN_PLATFORM_ARCHITECTURE.md), [TODO](docs/SCAN_PLATFORM_TODO.md). shared package11개·root302개(skip4)·TSAN23개 실패0, ARM/Intel CLI/SNS 통과. Windows native reader와 실행 검증·신뢰 가능한 전체 성능 gate는 남음.
2026-11-21 후속 실험: [지속 공급 read-ahead 성과](docs/CONTINUOUS_READ_AHEAD_RESULTS.md), [TODO](docs/CONTINUOUS_READ_AHEAD_TODO.md). 개발 소스 구현·Core/TSAN·3108회 비교 완료, 분기 약24% 개선. 일부 p95 기준 미달로 기본 설치0.2.1 유지.
2026-11-21 후속: [disktree 도입 결과](docs/DISKTREE_ADOPTION_RESULTS.md), [항목별 TODO](docs/DISKTREE_ADOPTION_TODO.md). 안전한 이름 decoding·제자리 순열·합산 batch·숫자 identity·read-ahead cadence를 적용했다. 7입력×99쌍×3변형=2079회 회귀 gate와 GUI/Universal 검증 통과. compact 경로 저장·불균형 분기 지연·resumable cursor 및 live root/watch 계측은 남아 있다.

2026-11-20 완료: [최종 성과표](docs/SCAN_DELIVERY_RESULTS.md). 기본 병렬도2·64 sibling 진입 조건, bounded snapshot 개요 소비·50ms 활성화·native draw 계측을 적용했다. 7입력×51쌍×3변형=1071회에서 지연/CPU/RSS/정확성 gate를 기준선과 직렬 양쪽으로 통과했다. 전체294개(1skip), TSAN34개 실패0. 최종 GUI20회 개요 draw 확인 p95 299ms,20만 파일 상세 재검사1.01초·취소·rename 감시·빈 root 교체를 검증했다. ARM/Intel CLI와 SNS/TXT, 실제 nested-volume GUI도 통과했다. Universal0.2.0/20261120.1을 기본 앱에 설치·서명 검증·실행했고 이전 앱/ZIP은 dist/releases에 백업했다. 전체 실제1TB 완료 시간 보장은 아니며, 현재 선택 볼륨 검사와 관측 개요를 사용한다.

2026-11-19 V03 병렬 읽기 구현·엔진 검증: [성과표](docs/SCAN_PARALLEL_RESULTS.md). 고정 worker·bounded queue·별도 I/O permit, 단일 builder와 공통 ordered reader를 구현했다. 전체289개(1 skip)·TSAN29개·판정 도구6개 실패0. 7입력×100쌍×4변형=2800회에서 파일/크기/digest 불일치0. 4-worker의 1만 파일 분기 입력 p50은48.65→28.96ms지만 작은 입력·큰 단일 폴더·깊은 트리 회귀로 기본 적용은 보류한다. public concurrency는1이고 기본 앱·Scope 후보는 유지했다. V03 실제 GUI/watch 검증·패키징은 채택 후보가 생긴 뒤 진행하며, V04 경량 개요는 미구현이다.

2026-11-19 V00 볼륨 범위 구현·검증: [범위 성과표](docs/SCAN_SCOPE_RESULTS.md). 선택 볼륨 기본 / 다른 볼륨 포함 옵션, System/Data 연결·중복 별칭, mode별 캐시, anchored 부분 재검사, 제외 경계·다중 볼륨 용량 계산을 구현했다. 실제 중첩 이미지에서100개와6100개를 정확히 구분하고, 최종280개(1 skip) 검사 실패0, 동시성 변경의 TSAN17개 및 실제 GUI/CLI/watch를 검증했다. 기본 모드 회귀 gate 통과, optional allVolumes의 control10000 p95는 보류. 기본 배포본은 유지하며 [Scope 후보 앱](<dist/Mac Space Sniffer Scope Candidate.app>)에 반영했다. 폴더 병렬화의 최신 상태는 위 V03 기록을 따르며, 경량 개요는 미구현이다.

2026-11-19 V02 구현·정량 검증: [배치 조회 성과](docs/SCAN_BULK_RESULTS.md). V02 단독 8개 입력 통과, 1만 파일 paired30.3%·10만11.5% 개선. Swift269개(1 skip)·TSAN44개 실패0. 이전 앱 대비 small1000 p95 +1.74ms로 엄격 전체 gate는 보류하며 기본 배포본은 유지한다. Universal 후보의 ARM/Intel CLI·SNS 재로드·동일 TXT·GUI 오류/지도·watch 변경 수렴을 검증했다.

2026-11-19 V01 구현·레거시 정리 및 100-pair 검증 완료: [성과표](docs/SCAN_SPEED_RESULTS.md). 권한 오류 p50 약 97.5% 감소, Swift 260개(1 skip)·TSAN 20개 실패 0. 정상 입력의 latency CI 경계 때문에 기본 실행본 채택은 보류한다.

2026-11-19 신규 실행 목록: [분석 속도 개선 TODO](docs/SCAN_SPEED_TODO.md). V01 권한 오류 재시도 → V02 batch I/O → V03 폴더 병렬화부터 진행하며, 경량 개요·공정한 순회·메모리·합산·증분 캐시의 완료 조건을 함께 추적한다.

2026-11-19 속도 비교: [disktree 실측과 현재 정체 원인](docs/validation/disktree-2026-11-19/README.md). 우선순위는 권한 오류 재시도 분류 → batch I/O → bounded directory workers → 경량 개요. 실측만 완료했으며 생산 엔진 변경은 미적용이다.

2026-11-16 신규 계획: **빠른 개요 + 상세 스캔**은 [실행 TODO](docs/PROGRESSIVE_SCAN_TODO.md), [정량 테스트 시나리오](docs/PROGRESSIVE_SCAN_TEST_PLAN.md), [전후 성과표](docs/PROGRESSIVE_SCAN_RESULTS.md)에서 추적한다. 실험용 streaming bulk 구현과 release 엔진 525회 비교를 완료했으며, 앱 기본값 변경·개요 UI·캐시 통합은 미완료다. 기존 완료 기록과 구분한다.

후속 실행: 사용자 지시에 따라 별도 **R01~R15를 진행 중**이다. [현재 후속 기록](docs/BACKLOG_EXECUTION_2026-11-09.md)을 따른다. 아래116/116은 이전 최적화 실행의 완료 기록이며 R 백로그 전체 완료를 뜻하지 않는다.

기준일: 2026-11-08. 대상 원본은 Windows SpaceSniffer **2.2.0.27 x64**, EXE SHA-256 `192176a0ff46d84d27885e9d38e60157bc692eaf5d1e5b75ca56b3beaa0de7a6`이다.

이번 목표는 **원본에서 확인한 작업 축소·재사용 원리를 Mac의 실제 병목에 적용하고, 동일한 결과를 더 적은 시간·자원으로 내는 것**이다. 사용자가 만족한 UI, 폴더 진입/상위 이동, 500ms 애니메이션은 유지한다. 현재 실행 체크는 116/116이며, 처음 남은 59개를 모두 검증했다. native Space/부분·완전 가림 matrix를 포함한 이번 최적화 실행 범위를 완료했다. [최신 실제 검증](docs/FINAL_OPTIMIZATION_VALIDATION.md)과 [완료 항목 근거](docs/optimization-execution-progress.json)를 연결한다.

이전 TODO의 완료·미완료 기록은 [원문 보관본](TODO_HISTORY_2026-11-08.md)에 그대로 보존했다. 원본 30개 기법의 현재 대응 상태는 [통합 체크리스트](docs/OPTIMIZATION_CHECKLIST.md), 적용 후보 8개와 판단 이유는 [실익 기준 추림](docs/BENEFICIAL_OPTIMIZATIONS.md)을 따른다. 여기서는 같은 작업을 여러 섹션에 중복 등록하지 않고 A/B/E/R ID로 추적한다. 단일 책임 기준의 [모듈 설계](docs/OPTIMIZATION_MODULE_DESIGN.md)는 현재 결합·목표 책임·상태 소유권·입출력·허용 의존성·수명·추출 순서를 규정한다.

## 0. 완료 체크 규칙과 현재 상태

`[x]`는 그 줄에 적힌 산출물이 실제로 존재하거나 검사가 완료된 경우만 사용한다. 원본 조사, 설계, 구현, 성능 검증, 패키징은 각각 따로 체크한다. 상위 작업 완료는 **구현 + 결과 동등성 + 실제 개선 + 수명/회귀 확인**을 통과한 뒤 결정한다. 일부 대응·플랫폼 대체를 원본 기법 전체 구현 완료로 체크하지 않는다.

| 준비 상태 | 확인한 사실 | 근거 |
|---|---|---|
| [x] 원본 확보·고정 | 공식 배포물, EXE hash 고정 | [원본 분석](docs/ENGINE_REVERSE_ENGINEERING.md) |
| [x] 최적화 근거 목록 | 30개 기법, 최초 누락 10개 보강, 미참조 원문 55개 처리 상태 기록 | [체크리스트 JSON](docs/optimization-checklist.json) |
| [x] 근거 연결 | 기존 139개 + 추가 6개 REA 기록, Mac 소스와 연결 | [최초 bundle](docs/windows-optimization-rea-evidence.json), [추가 bundle](docs/windows-optimization-coverage-rea-evidence.json) |
| [x] 현재 비용 표본 | 탐색·큐·export·MCP scope 8개 시나리오 × 3회 | [raw 측정](docs/validation/optimization-audit.json) |
| [x] 이전 구현 검증 기록 | Swift 51개 ThreadSanitizer, Python 6개, QA MCP 요청 99회 기록 | [검증 결과](docs/VALIDATION.md) |
| [x] 이번 명세의 새 구현 | A00 경계 확보, B01~B08 및 E01/E02 결정에 따른 변경 | 이번 실행 구현·평가·실측 완료; Windows 동적 동등성 R01~R15 및 각 단계의 제약은 별도 |
| [x] 탐색 단계 실행 검증 | 당시 Swift 59 TSAN·Python 6·QA MCP 95요청·Universal/signature | [검증](docs/PROJECTION_SESSION_VALIDATION.md) |
| [x] 큐 단계 실행 검증 | Swift 88 TSAN·Python 6·100개 queue 표본, 실제 앱/패키징 결과는 별도 기록 | [검증](docs/REFRESH_QUEUE_VALIDATION.md) |
| [ ] Windows 동적 동등성 | 실제 Windows 결과·타이밍·파일 왕복 | R01/R02 미완료 |

2026-11-09 원본 기법 대응 코드는 8 / 부분 대응 7 / 핵심 미적용 6 / 플랫폼 대체 8 / 적용 검토 1이다. 이것은 원본 전체의 누락 0건이나 새로운 최적화 30개가 모두 구현되었다는 뜻이 아니다. 이전 51/6/99를 이번에 다시 실행한 수치로 보고하지 않는다.

## 1. 실행 순서와 의존성

노드 풀·스레드 풀은 **불필요하다고 제외하지 않는다.** E01/E02를 선행 평가로 두고 어떤 재사용 단위와 실행 모델이 이득인지 결정한다. 평가 완료와 실제 풀 도입 완료를 구분한다.

| ID | 상태 | 목적 | 선행 조건 | 완료 때 남길 산출물 |
|---|---|---|---|---|
| G00 | [x] 검증 범위 완료 | 재현 가능한 기준선·계측·oracle 고정 | 없음 | fixture manifest, source hash, raw baseline |
| A00 | [x] 설계·선행 경계 완료 | 단일 책임 경계·소유권 고정과 필요한 추출 | G00 | 책임표/의존 방향/입출력/수명, 최소 추출 동등성 |
| E01 | [x] 검증 범위 완료 | node/page/scratch pool의 이득·수명 평가 및 채택 구현 | G00, A00 | allocation 비교, pool 정책·채택/미채택 결정 |
| E02 | [x] 검증 범위 완료 | blocking I/O executor·동시 scan 상한·worker 재사용 평가 및 채택 구현 | G00, A00 | 실행 모델 비교, admission/취소/종료 계약 |
| B01 | [x] 검증 범위 완료 | 탐색에서 membership/weights 재사용 | G00, A00 | same-input key, fallback, 동등성·탐색 측정 |
| B02 | [x] 검증 범위 완료 | 변경 의존성별 재계산 최소화 | B01의 입력/공개 revision 구분 | change matrix, pass/submit 수·회귀 결과 |
| B05 | [x] 검증 범위 완료 | text/tooltip/AX 수명과 paint 분리 | G00, B02 paint 무효화 계약 | frame/할당 측정, UI·접근성 QA |
| B08 | [x] 검증 범위 완료 | 경로 index로 이벤트 큐 비용 축소 | G00, A00 | 기존 큐 oracle, 폭주/수명 비교 |
| B07 | [x] 검증 범위 완료 | 단일 판정·streaming SNS/TXT | G00, E02 I/O 모델 결정 | sink 정책, 바이트 대조, peak RSS |
| B04 | [x] 검증 범위 완료 | 정렬/변하지 않은 geometry 재사용 | B01/B02, E01 보유 메모리 정책 | cache key/상한, rect·정렬 oracle |
| B03 | [x] 검증 범위 완료 | 작은 변경의 membership/weights 증분 갱신 | B01/B02, E01 COW 비용 평가 | dirty 입력 계약, 전체 계산 differential 검사 |
| B06 | [x] 검증 범위 완료 | 가려진 창의 불필요한 시각 작업 억제 | B05, visibility 기준선 | 숨김/복귀/캡처 결과와 CPU 비교 |
| G90 | [x] 검증 범위 완료 | 통합 회귀·수명·재현 검증 | 채택한 작업들 | 결과 묶음, 미해결/제외 이유 |
| G99 | [x] 검증 범위 완료 | Universal 패키징·문서·상태 갱신 | G90 | 앱/ZIP/signature/hash, 최신 명세 |

선행 조건은 안전한 통합 순서다. G00 뒤에는 독립적인 비교 probe를 작성할 수 있지만, 서로 다른 최적화를 한 번에 적용해 개선 원인을 알 수 없게 만들지 않는다. E01/E02의 조사만으로 B01~B08 구현이 완료되지는 않는다. 2026-11-09 후속 구현은 [scan·scratch 검증](docs/SCAN_RESOURCE_VALIDATION.md)을 따른다. 이는 당시 중간 기록이며 E01/E02의 최종 평가는 [후속 검증](docs/FINAL_OPTIMIZATION_VALIDATION.md)을 따른다. production page/node object pool은 비교 뒤 미채택했다.

## 2. 모든 작업이 지켜야 할 계약

| 영역 | 유지할 계약 | 확인 방법 |
|---|---|---|
| 합산 | 경로별 파일 기여, hard-link 임의 dedup 없음, 폴더 자체 metadata 미가산 | 파일별/조상별 logical·allocated 비교 |
| 필터 | native 문법·경계 포함·OR/제외·태그 상속·숨김·시간 의미 | 기존 전체 판정 oracle과 differential 검사 |
| 탐색 | 삭제/필터 제외의 생존 부모 이동, selection/history 복구, 유일한 rename만 연결 | 기존 NavigationState 결과 비교 |
| 값 snapshot | reader가 가진 이전 노드·태그·weights·문자열을 후속 writer가 바꾸지 않음 | frozen reader + 동시 변경/풀 재사용 검사 |
| 취소/교체 | 오래된 generation의 결과 publish 금지, 대기·실행 작업 수명 정리 | 취소 지점·stale publish·해제 확인 |
| 표시 | 현재 UI, 선택 경로 상세화, 양수 항목 면적 참여, 500ms 곡선·Reduce Motion | geometry oracle·실제 UI QA |
| 파일 | SNS/TXT 필드·순서·인코딩·종료 bytes, 기존 output 덮어쓰기 정책 | golden bytes·기존 writer 비교·경합 실패 검사 |
| MCP | 접수와 완료 분리, pagination revision, bounded 결과, 상태/오류·job 일관성 | 실제 STDIO 및 QA 앱 호출 |
| 플랫폼 | macOS 14 배포 기준, Swift actor/COW/AppKit 규칙 | Package.swift·availability·양 아키텍처 빌드 |

모듈화는 **변경 이유와 가변 상태의 소유권**으로 판정한다. M01~M16 논리 경계와 ScanStore/MapCanvas/AutomationHub adapter 계약은 [모듈 설계](docs/OPTIMIZATION_MODULE_DESIGN.md)를 따른다. Core의 UI/Automation 역참조, 전역 CacheManager/PoolManager, 불필요한 per-node protocol/await를 만들지 않는다. 각 E/B 작업은 설계의 소유자에게 구현하고 기존 adapter에 같은 정책을 복사해 남기지 않는다.

이번 체크는 현재 범위의 개별 산출물에 한정한다. 상위 그룹은 부분 진행이며, E01/E02 평가·전체 change matrix·실제 앱 지연/장시간 관측 등 미체크 항목을 생략하지 않는다.

새 core 파일을 추가하면 `docs/engine-contracts.json`의 파일/anchor/classification도 추가한다. 원본 동작은 REA 근거에 연결하고 page pool·executor·trie·AX 수명 같은 플랫폼 구현은 그 분류를 명시한다. 근거 없는 free/unknown/missing 집계나 영구 캐시를 성능 작업에 끼워 넣지 않는다.

## G00 — 기준선·fixture·계측을 고정한다

### 입력과 환경

- [x] G00.01 현재 source/package/fixture hash, Swift·OS·architecture, 빌드 옵션, 실행 순서와 명령을 기록한다. 출력 경로는 새 실험 디렉터리로 고정한다.
- [x] G00.02 기존 25만 파일 metadata probe를 유지하고 small(기능), wide(형제 다수), deep, 변경 폭주, 다중 root fixture를 분리한다. 큰 입력은 25만부터 시작하고 더 큰 입력은 메모리 여유를 확인한 뒤 확장한다.
- [x] G00.03 0바이트·hard-link alias·symlink·숨김 조상·Unicode/대소문자·긴 이름·Windows SNS 경로·filter 경계 파일을 고정 seed로 준비한다.
- [x] G00.04 디스크 scan/E02용 fixture와 metadata-only 입력을 분리한다. 사용자 develop 전체를 초기 성능 실험 입력으로 사용하지 않는다. 작은 QA tree에서 시작한다.
- [x] G00.05 현재 전체 projection·기존 RefreshQueue·기존 SNS/TXT writer를 reference oracle로 고정한다. 새 구현이 스스로 만든 expected 값만 검사하지 않는다.

### 계측과 판정

- [x] G00.06 필요한 지점에 monotonic stage duration과 시작/취소/완료/stale-drop 카운터를 둔다. 기존 `WorkerTelemetry.runs`를 완료 수·동시 실행 수로 해석하지 않는다.
- [x] G00.07 RSS/physical footprint/할당량·횟수/보유 pool bytes, active/queued scan 수, queue 대기 시간, geometry/draw 횟수·duration을 분리한다. 누적 CPU 초와 CPU 사용률을 혼동하지 않는다.
- [x] G00.08 계측은 사용자 파일 내용·모든 path를 장기 보관하지 않는 bounded 진단으로 구성하고, 계측 자체 overhead를 확인한다. MCP 진단을 확장하면 기존 필드를 보존한다.
- [x] G00.09 release 빌드로 before/after를 같은 입력에서 순차 교차 실행한다. 새 최종 비교는 기본 5회 이상으로 raw 표본·중앙값·범위를 남기고, warmup/초기 할당 포함 여부를 구분한다.
- [x] G00.10 UI p95를 주장할 때는 충분한 interaction/frame 표본(예: 200개 이상)을 모은다. 5개 process 실행값만으로 안정적인 UI p95라고 보고하지 않는다.
- [x] G00.11 의미·바이트 차이는 0건이어야 한다. geometry 허용 오차는 기존 검사 기준을 따르고, 새 실패를 숨기려고 오차를 넓히지 않는다.
- [x] G00.12 주 지표가 baseline 변동폭과 구분되어 개선되고 보유 메모리·취소/입력 지연에 설명되지 않는 회귀가 없어야 채택한다. 차이가 noise 수준이면 반복 측정 또는 보류한다. 임의 개선율을 원본에서 얻은 수치처럼 사용하지 않는다.

기존 관측은 **탐색 10회 320.733→12.707ms 재사용 probe**, 독립 경로 4천개 현재 큐 삽입 **1,941.877ms**, scoped export 계산 **54.161ms**다. 새 구현의 목표 달성값이나 전체 앱 배율이 아니다. [조건과 raw](docs/OPTIMIZATION_AUDIT.md)를 보존한다.

## A00 — 단일 책임 경계와 상태 소유권을 확보한다

**설계 근거:** [현재 코드 감사·목표 모듈 설계](docs/OPTIMIZATION_MODULE_DESIGN.md). 원본 W 동작은 유지하고 모듈 경계는 Mac 구조의 선택으로 구분한다. A00은 모든 목표 모듈을 한 번에 새로 만드는 작업이 아니다. 최소 선행 추출을 수행하고 나머지는 해당 E/B 작업에서 적용한다.

- [x] A00.01 현재 LatestWorker/FilterProjection, ScanService, ScanStore, ArtifactWorker/Model, MapCanvas, AutomationHub의 책임 결합을 실제 호출/가변 상태와 함께 확인한다.
- [x] A00.02 M01~M16 각각의 변경 이유·소유 상태·입출력·맡기지 않을 일을 확정한다. 논리 경계와 새 파일/target/protocol 생성을 구분한다.
- [x] A00.03 Core → 모델/계산, Automation → Core, App → Core/Automation 의존 방향을 확인한다. Core의 AppKit/SwiftUI/Automation 역참조와 service locator를 허용하지 않는다.
- [x] A00.04 root generation·공개 projection revision·계산 cache key·storage lease·job id의 소유자를 따로 확정한다. 같은 가변 상태를 두 모듈이 쓰지 않게 한다.
- [x] A00.05 LatestWorker의 실행/취소와 FilterProjection의 계산을 분리한다. 계산은 실행기·AppKit 없이 호출 가능하게 하고 실행기는 필터 의미를 알지 못하게 한다. 기존 알고리즘은 바꾸지 않는다.
- [x] A00.06 ScanStore/MapCanvas/AutomationHub를 intent·결과 반영 adapter로 남기는 이동 계획을 작성한다. UI와 MCP가 동일 서비스/무효화 진입점을 사용하도록 한다.
- [x] A00.07 각 cache/pool/worker/file sink의 생성자·단일 소유자·반납/eviction·취소·shutdown을 확정한다. 실행 중 scan의 slot을 취소 접수만으로 조기 반환하지 않는다.
- [x] A00.08 각 추출을 E01/E02/B01~B08에 배정한다. 구조 추출과 자료구조/성능 변경을 분리하고, 작은 독립 변경마다 결과 동등성을 확인한다. 전체 엔진 재작성은 하지 않는다.
- [x] A00.09 실제 교체가 필요한 scanner/clock/sink 경계에만 주입 지점을 둔다. pool frozen reader, admission 완료 한 번, codec 바이트, presentation/AX 수명 검증을 각 소유자에 배정한다. forwarding만 검사하는 테스트는 만들지 않는다.
- [x] A00.10 선행 추출의 관련 회귀·release 비용과 근거 contract를 확인한다. 필요한 source/test anchor를 갱신하고, 아직 E/B에서 추출하지 않은 모듈은 미완료로 남긴다.

**완료 기준:** 책임/소유권/의존/수명 계약이 확정되고 선행 최소 추출이 동일 결과를 낸다. 후속 E/B 완료 기준에는 해당 모듈 경계의 실제 적용도 포함된다. 설계 문서 존재나 파일 분리 개수만으로 전체 모듈화 완료를 체크하지 않는다.

## E01 — 노드 풀·페이지·임시 버퍼 재사용

**목적:** 반복 변경/재스캔에서 할당이 실제 병목인지 확인하고 재사용 단위를 선택한다. 원본 W15의 FS/TM recycle can과 busy 제외가 근거다. [원문](docs/validation/windows-optimization-functions/0x448450.txt). 현재 수정점은 [NodeTable](Sources/SpaceSnifferCore/NodeTable.swift), [Scanner](Sources/SpaceSnifferCore/Scanner.swift), [SnapshotTree](Sources/SpaceSnifferCore/SnapshotTree.swift), [LatestWorker](Sources/SpaceSnifferCore/LatestWorker.swift)다.

[실제 구현·측정](docs/SCAN_RESOURCE_VALIDATION.md): FilterScratch context 재사용만 적용했다. node/page pool 도입이나 E01 전체 완료를 뜻하지 않는다.

### 조사·설계

- [x] E01.01 첫 scan과 반복 scan/추가·삭제·rename·filter의 allocation 횟수·bytes·CPU를 분리한다. page, children 배열, path/name/identity 문자열, membership/weights/context, 순회 stack 중 상위 원인을 기록한다.
- [x] E01.02 같은 입력으로 세 후보를 비교한다: worker 전용 scratch buffer 재사용 / reader가 없는 page 저장소 재활용 / 실제 node 객체 pool. 현재 값 타입 DiskNode에 객체 pool이 있는 것으로 가정하지 않는다.
- [x] E01.03 checkout→사용→reader 소유→반납→eviction 상태와 소유자를 정의한다. pool 반납 조건은 **참조 중인 snapshot이 더 이상 사용하지 않는 저장소**임을 증명해야 한다.
- [x] E01.04 UI transition, QueryContext, export job, ScanService baseline이 잡은 reader도 반납 판정에 포함한다. 새 node에 이전 id/path/tag/issue/children이 섞이지 않게 reset 계약을 적는다.
- [x] E01.05 worker별/전체 retained bytes 상한, oversized buffer 처리, root 해제·idle·memory pressure의 eviction을 정한다. allocation 감소와 RSS 감소를 같은 지표로 취급하지 않는다.

### 실험·검증·도입

- [x] E01.06 current 방식과 후보를 같은 seed/입력에서 비교한다. pool hits/misses·allocated/retained/evicted bytes와 취소 후 생존 reader 수를 함께 남긴다.
- [x] E01.07 frozen snapshot을 여러 세대 유지한 채 writer·cancel·rename·export·MCP reader를 겹친다. 이전 node/children/weights 값 불변과 race 부재를 검사한다.
- [x] E01.08 root 구독 해제·worker shutdown 뒤 사용자가 소유하지 않은 입력과 oversized buffer가 해제되는지 확인한다. 무제한 high-water 보유를 허용하지 않는다.
- [x] E01.09 실제 이득을 보이는 재사용 단위만 채택해 구현한다. node pool을 채택하지 않으면 측정값과 이유를 기록하고 scratch/page 채택 여부를 따로 체크한다.
- [x] E01.10 적용 후 `MemoryLifetimeTests`의 page 격리·동시 reader/writer·capture 해제를 유지하고, **실제 재사용된 저장소**에 대한 추가 회귀 검사를 통과한다. 이번 완료 범위는 FilterScratch context이며 node/page pool은 미도입이다.

**완료 기준:** allocation 원인과 채택/미채택 판단이 표본으로 뒷받침되고, 채택 구현은 결과/수명·retained bytes 상한을 통과한다. 조사만 끝났다면 도입 완료로 체크하지 않는다. COW가 있다는 이유만으로 pool이 필요 없다고 결론 내리지 않는다.

## E02 — 스캔 I/O 실행 경로·스레드/worker pool·동시성 한도

**목적:** 스레드 재사용, blocking I/O 격리, 실행 작업 수 제한을 별개로 확인한다. 원본 W16의 working/pooled list와 event wait, W30의 별도 focus worker가 근거다. [pool 원문](docs/validation/windows-optimization-functions/0x45a7c0.txt), [focus 원문](docs/validation/windows-optimization-functions/0x430270.txt).

Swift는 기본 cooperative thread pool을 사용하며 actor도 자체 전용 스레드라고 볼 수 없다. 스레드를 막는 작업·숨겨진 semaphore 의존성은 별도 검토해야 한다. [Apple 런타임 설명](https://developer.apple.com/videos/play/wwdc2021/10254/), [공식 executor 문서](https://developer.apple.com/documentation/swift/globalconcurrentexecutor). 기존 `Task.detached`의 동기 scanner는 [ScanAdmission](Sources/SpaceSnifferCore/ScanAdmission.swift)·[ScanWork](Sources/SpaceSnifferCore/ScanWork.swift)로 분리했다. [ArtifactWorker](Sources/SpaceSnifferCore/ArtifactWorker.swift)의 동기 I/O와 root 경로 정규화 등은 추가 점검이 남아 있다. actor로 옮긴 사실만으로 blocking I/O 전용 executor가 확보된 것은 아니다.

- [x] E02.01 `opendir/readdir/lstat`, 재시도 sleep, SNS/TXT 읽기·쓰기, actor/lock 대기 위치를 그린다. 실제 thread 수·blocked 시간·filter/geometry/MCP 응답 지연을 측정한다.
- [x] E02.02 single root / 서로 다른 roots / 느린 I/O / scan+export / cancel·재시작 fixture를 나눈다. projection mailbox와 scan worker를 같은 pool로 세지 않는다.
- [x] E02.03 현재 방식과 **동시성 상한이 있는 blocking I/O 실행 경로**를 비교한다. 가능한 구현 후보는 bounded OperationQueue/명시적 작업 큐 등이며, 채택 API의 macOS 14 호환성을 먼저 확인한다.
- [x] E02.04 root별 실행과 프로세스 전체 admission limit K를 분리한다. 비교값 1/2/4는 실험 조건이지 원본 정답이나 CPU core 수 기반 기본값이 아니다. 실제 I/O·응답성·메모리를 보고 선택한다. 이번에는8도 비교해 active8/queued64를 채택했다. 고정 OS 스레드8개를 뜻하지 않는다.
- [x] E02.05 queued→running→cancel_requested→finished 상태, FIFO/우선순위·같은 root 중복·starvation 방지·정리 순서를 정의한다. 원본 pending scope/FIFO 계약과 worker admission 순서를 혼동하지 않는다.
- [x] E02.06 queued 취소는 I/O를 시작하지 않고, running 취소는 기존 ScanControl로 빠져나오게 한다. 결과·오류·취소의 완료 전달은 정확히 한 번만 수행한다.
- [x] E02.07 await 대기는 task를 suspend하도록 설계한다. cooperative executor에서 semaphore로 자식 task 완료를 기다리는 방식은 도입하지 않는다. lock을 보유한 채 await하지 않으며 actor 재진입 뒤 세대·취소 상태를 다시 검증한다.
- [x] E02.08 느린 scan이 filter/geometry와 상태 조회를 고갈시키지 않는지 검사한다. entry 제거/세대 교체 뒤 늦은 완료가 새 entry를 수정하지 못하게 한다.
- [x] E02.09 active 작업이 설정 K를 넘지 않고, 대기 task·thread·snapshot이 무한 증가하지 않는지 검증한다. pool 생성/재사용과 전체 scan 시간·취소 지연·RSS를 함께 비교한다.
- [x] E02.10 채택 executor/admission을 구현하고 multi-root·취소·마지막 구독 해제·종료·artifact 경합 회귀를 통과한다. 채택하지 않을 때도 current 경로가 충분하다는 측정 근거를 남긴다.

**완료 기준:** 실행 경로·상한·취소/종료의 의미가 명시되고, 실제 응답성/자원 지표와 결과 동등성이 통과한다. 원본 pool data의 초기값 1을 Mac의 최적 동시성이나 원본 앱 전체 thread 상한으로 복사하지 않는다.

## B01 — 탐색만 바뀔 때 판정·합계를 재사용한다

**근거:** W02 `setNewFocus(0x428bb0)`의 기존 TM tree 재사용. **수정점:** [ScanStore](Sources/MacSpaceSniffer/ScanStore.swift), [FilterProjection](Sources/SpaceSnifferCore/FilterProjection.swift)·[ProjectionSession](Sources/SpaceSnifferCore/ProjectionSession.swift), [NavigationState](Sources/SpaceSnifferCore/NavigationState.swift), [Filter](Sources/SpaceSnifferCore/Filter.swift).

- [x] B01.01 엔진 입력 identity와 공개 projection revision을 분리한다. snapshot/root generation·태그/metadata·적용 filter·hidden·mode에 대한 same-input 조건을 명시한다.
- [x] B01.02 navigation 변경으로 공개 UUID가 바뀌어도 내부 판정 cache는 재사용할 수 있도록 key를 설계한다. UUID 값만 같다고 서로 다른 snapshot을 재사용하지 않는다.
- [x] B01.03 leaf membership과 weights를 함께 보존하고, navigation/history 복구·현재 focus children 생성만 실행하는 경로를 둔다. **0바이트 파일의 포함 여부는 weights로 대체하지 않는다.**
- [x] B01.04 상대 시간 조건은 처음에는 기존 전체 pass로 fallback한다. 만료 시점 기반 cache를 추가하려면 별도 경계 시험을 통과한다.
- [x] B01.05 start/load/disconnect, pending snapshot 도착, filter 오류 fallback, hidden/mode/tag/metadata 변경에서 무효화한다. 오래된 worker completion은 기존 token 검사로 버린다.
- [x] B01.06 뒤로/앞으로의 전체 `firstIndex(path)`를 같은 입력의 작은 추적 경로/계층 lookup으로 대체할 수 있는지 함께 측정한다. 전체 path dictionary를 추가해 RAM을 되돌려 늘리지 않는다.
- [x] B01.07 전체 projection oracle과 focus/selection/history/index/children/membership/weights를 모두 비교한다. 정상 진입·상위·뒤로/앞으로·root·삭제·rename·필터 제외·0 matches를 포함한다.
- [x] B01.08 같은 입력의 navigation에서 전체 membership/weights 실행 수가 증가하지 않는지 계측한다. 신규 input/fallback에서는 필요한 pass가 실제 수행되는지도 검사한다.
- [x] B01.09 기존 25만 파일 probe와 실제 QA 앱 이동을 before/after 측정한다. initial cache 생성·retained membership 비용은 별도로 보고한다.

**완료 기준:** 모든 oracle 결과가 같고 같은 입력 navigation에서 full pass가 제거되며 실제 이동 시간/할당이 개선된다. MCP focus와 revision·projection_pending은 최종 publish와 일치해야 한다.

## B02 — 변경 의존성별로 필요한 단계만 실행한다

**근거:** W06 `reapplyFilterIfTagInvolved(0x430400)`, 원본 같은 tag 값 쓰기 생략. **수정점:** ScanStore, ScanService, Filter, [AutomationHub](Sources/MacSpaceSniffer/AutomationHub.swift).

- [x] B02.01 입력 변경 matrix를 작성한다: navigation / selection / depth·bounds / filter / logical↔allocated / hidden / own·ancestor tag / size / 이름·시간·속성 / topology / 시작·SNS load.
- [x] B02.02 각 변경에 필요한 parse·membership·weights·navigation·sort·geometry·paint를 표시하고, 판정 근거가 불명확한 변경은 full projection으로 fallback한다.
- [x] B02.03 tag 비의존 filter의 색 변경은 membership 재판정을 생략한다. tag 정보 자체, inherited tag 조회, UI 색·MCP metadata·공개 revision은 갱신한다.
- [x] B02.04 실제 동일 underlying tag mask 쓰기는 scan revision/broadcast를 생략할 수 있게 한다. **같은 색을 다시 누르면 해제되는 UI/MCP toggle 의미는 그대로 유지한다.**
- [x] B02.05 mode/hidden 동일값 setter와 복합 view_set의 중복 submit을 줄인다. filter 문자열이 같아도 시간 재평가 요청은 별도 의미로 다룬다.
- [x] B02.06 계산을 건너뛰었다고 metadata가 같은 것으로 처리하지 않는다. query pagination에서 바뀐 tag/이름/size가 이전 revision에 섞이지 않게 한다.
- [x] B02.07 변경 matrix의 각 셀을 기존 전체 경로와 비교한다. ancestor tag, hidden 조상, 시간 경계, 필터 오류, 변경 중 연속 navigation/다른 client 요청을 포함한다.
- [x] B02.08 full pass·submit·시작·취소·publish 횟수와 실제 지연을 측정해 줄어든 작업과 유지한 작업을 보고한다.

**완료 기준:** 동일한 최종 데이터/화면/MCP 상태를 내면서 불필요한 pass/submit이 제거된다. 공개 revision을 내부 cache key와 혼용하지 않는다.

## B05 — 문자열·툴팁·접근성 수명을 paint와 분리한다

[접근성 후속 검증](docs/ACCESSIBILITY_CACHE_VALIDATION.md): B05.05/06 완료. path 기반 AX 요소 재사용·현재 ID 재검증·500개 후보 조기 중단을 구현했다. [툴팁 등록 후속](docs/TOOLTIP_REGISTRY_VALIDATION.md)에서 B05.04도 완료했다. text/font/full-frame 및 종합 전환 검증은 미완료다.

**근거:** W13 TTextBox dirty/font 치수 cache, W14 지속 tooltip/dirty rebuild. AX 재사용은 Mac 플랫폼 확장이다. **수정점:** [TreemapView](Sources/MacSpaceSniffer/TreemapView.swift), [MapTransition](Sources/MacSpaceSniffer/MapTransition.swift).

- [x] B05.01 draw에서 text 구성/측정, tooltip 등록, AX element 생성, rect index 생성 각각의 횟수·시간·할당 기준선을 분리한다.
- [x] B05.02 현재/직전 presentation 범위의 text/font/value key와 무효화 조건을 정의한다. 전체 트리 이름을 무제한 cache하지 않는다.
- [x] B05.03 같은 제목·크기·font 상태의 측정과 서식 재생성을 건너뛴다. 값이 바뀌면 label·width 모두 갱신한다.
- [x] B05.04 tooltip 등록 수명을 geometry/presentation에 연결하고 hover outline redraw에서 전체 제거/재등록을 피한다. 전환 중 위치 정확성은 별도로 유지한다.
- [x] B05.05 AX element는 안정적인 path/현재 ID로 재사용한다. activation callback은 새 snapshot의 id/path를 다시 확인하고, 과거 MapItem/snapshot을 강하게 잡지 않게 한다.
- [x] B05.06 후보 수집은 최대 500개에서 중단하도록 lazy/direct 순회로 만든다. 불필요한 전체 filter 중간 배열을 피한다.
- [x] B05.07 중단 전환·hover·snapshot ID 재배치·resize·클릭/더블 클릭·Reduce Motion·VoiceOver label/frame/activation을 검증한다.
- [x] B05.08 실제 frame 시간·할당·retained cache를 비교하고 마지막 창 종료 때 timer/tooltip/AX cache가 해제되는지 확인한다.

**완료 기준:** 사용자 UI와 hit/AX 동작이 같고 반복 draw의 불필요한 측정/등록/객체 생성이 줄어든다. font cache가 있으니 모든 font 비용이 사라졌다고 추정하지 않는다.

## B08 — 이벤트 큐의 prefix 비교 비용을 줄인다

구현·측정: [이벤트 큐 검증](docs/REFRESH_QUEUE_VALIDATION.md). B08.01–08 검증 범위 완료. [B08.08 후속](docs/REFRESH_LIFECYCLE_VALIDATION.md)에서 실제 FSEvents pending=48/index=152 상태의 running 취소, 이전 callback 차단, Storage 객체 해제를 확인했다. weak 수명 관측이며 전체 deep byte/RSS 반환량을 측정한 것은 아니다.

**근거:** W09의 중복·조상 packing/FIFO 계약. **index/trie는 Mac 자료구조 선택**이며 원본은 TList 중첩 비교다. **수정점:** [RefreshQueue](Sources/SpaceSnifferCore/RefreshQueue.swift), ScanService.changed/refreshPending.

- [x] B08.01 기존 배열 큐를 oracle로 보존한다. 명시적 전체 root·중복·조상/후손·독립 분기·removeCovered·pop·removeAll 결과를 고정한다.
- [x] B08.02 component index/radix 등 후보와 FIFO 순서를 분리해 설계한다. 현재 `SnapshotTree.contains`의 경로 경계·구분자 의미를 보존한다.
- [x] B08.03 `/a/x`, `/b` 뒤 `/a` 삽입 결과가 `/b`, `/a`가 되도록 한다. 새 조상을 지워진 후손의 앞자리로 당기지 않는다.
- [x] B08.04 `/a`와 `/ab`, root, Unicode, Windows 구분자, 정규화되지 않은 입력의 fallback을 검사한다. 빈 component를 제거하면서 기존 lexical 관계를 몰래 바꾸지 않는다.
- [x] B08.05 삭제 mark/슬라이딩 FIFO를 쓰면 compaction과 index 제거·retained bytes 상한을 정한다. pop 비용을 줄이다 tombstone이 무한히 쌓이지 않게 한다.
- [x] B08.06 고정 seed의 임의 연산 시퀀스를 기존 큐와 매 단계 대조한다. 일괄 결과만 같고 중간 FIFO가 다른 구현은 실패다.
- [x] B08.07 독립 경로 1천/2천/4천·중복 폭주·ancestor 폭주·root 덮기·장기 insert/pop을 같은 명령으로 전후 측정한다.
- [x] B08.08 실제 작은 QA FSEvents burst에서 다른 scope 보존, 감시 세대 교체, scan cancel, status 응답 지연·큐 메모리 회수를 확인한다.

**완료 기준:** oracle 연산 결과가 같고 폭주 삽입 비용/actor 점유가 개선되며 정상 소량 큐와 메모리 수명에 회귀가 없다. 원본보다 항상 빠르다는 주장은 Windows 측정 없이 하지 않는다.

## B07 — 판정 공유와 SNS/TXT sink 출력

**근거:** W19 원본 `FILE*` 순차 쓰기. **수정점:** [ArtifactWorker](Sources/SpaceSnifferCore/ArtifactWorker.swift), [SNS codec](Sources/SpaceSnifferCore/SNSSnapshot.swift), [Report](Sources/SpaceSnifferCore/Report.swift), AutomationHub job.

- [x] B07.01 한 시점의 filter 판정에서 leaf membership·weights·부모 포함 IDs를 만든다. 부모 포함으로 바꾼 membership을 leaf weights에 잘못 넣지 않는다.
- [x] B07.02 기존 Data/String writer를 reference로 유지하고 공통 record/line emitter와 Data/file sink를 분리한다. 형식/집계 의미 변경을 streaming 변경에 섞지 않는다.
- [x] B07.03 출력 범위·filter·hidden·mode·revision은 접수 시 캡처한다. 저장 중 UI 변경과 무관하게 그 입력을 끝까지 쓴다.
- [x] B07.04 [이전 writer 비교; 원본 file LF/child-order 동률은 R11에서 정정] 파일 우선·크기/동률 순서·0바이트·UTF8/CRLF·UTF16LE Base64/LE/FILETIME/노드 종료 bytes를 기존 writer와 대조한다.
- [x] B07.05 UI 덮어쓰기/atomic 경로와 MCP 미존재 output 경로를 구분한다. **exists 확인 후 덮어쓰는 rename**으로 MCP exclusive 계약을 구현하지 않는다.
- [x] B07.06 임시 파일/배타적 publish·partial write/close 오류·중단 시 정리 정책을 먼저 정한다. 이 작업이 만든 파일만 정리하고 타 프로세스가 바꾼 파일을 지우지 않는다.
- [x] B07.07 짧은 write·권한 오류·용량 부족·동일 output 경합·읽기 오류를 주입한다. 완료 job은 실제 출력 성공 뒤에만 completed가 된다. crash durability는 별도 보장 없으면 주장하지 않는다.
- [x] B07.08 현재 artifact 동시 2개/최근32개 상태와 loading generation 검사를 유지한다. 취소 API를 추가한다면 별도 schema/문서/테스트 작업으로 분리한다.
- [x] B07.09 큰 전체 export와 큰 트리의 작은 focus export에서 peak RSS·allocation·시간·출력 bytes를 전후 비교한다. E02에서 정한 I/O 실행 경로를 사용한다.

**완료 기준:** 모든 바이트/출력 범위가 같고 대량 출력의 buffer 중복·peak 메모리가 개선되며 실패/경합에서 기존 파일을 보호한다. 순회 stack/형제 정렬까지 O(1)이라고 보고하지 않는다.

## B04 — 정렬·unchanged geometry 재사용

**근거:** W05 sorted-state/변경 child 국소 교환, W11 layout/paint 분리. **수정점:** FilterProjection, [Treemap](Sources/SpaceSnifferCore/Treemap.swift), TreemapView geometry key.

- [x] B04.01 정렬 순서 cache와 rectangle cache의 key를 분리한다. weights/child 집합/order/comparator version과 scope/bounds/depth/selection-path/layout policy를 각각 명시한다.
- [x] B04.02 처음에는 같은 weights·형제 집합의 정렬 재사용부터 적용하고, 변경 child 재배치·branch layout 재사용은 각각 독립 비교한다.
- [x] B04.03 원래 Int64/Double 변환·동률 기준을 확인한다. 새 comparator가 큰 값의 순서를 바꾸지 않도록 기존 layout 결과를 oracle로 사용한다.
- [x] B04.04 selected path의 상세화, depth 변경, 추가/삭제/rename, mode/filter 변경, resize에서 올바르게 무효화한다. selection을 cache key에서 단순 제거하지 않는다.
- [x] B04.05 sub-pixel이어도 모든 양수 항목의 면적 참여를 유지한다. tiny chunk 원본 표시 정책은 별도 UI 판단이며 자동 도입하지 않는다.
- [x] B04.06 cache는 현재/직전 표시 범위 등 bounded 수명으로 두고 이전 snapshot/page를 불필요하게 잡지 않는지 확인한다.
- [x] B04.07 rect·순서·area·selection 확대 oracle과 실제 선택/resize p95·retained bytes를 비교한다.

**완료 기준:** 같은 입력의 배치/선택 결과를 보존하고 정렬/geometry 작업 횟수 또는 시간이 실제로 줄어든다.

## B03 — 작은 변경의 filtered projection을 증분 갱신한다

**근거:** W04 FS/TM delta와 W21 기존 filtered node 보존. **수정점:** ScanService update, SnapshotTree, FilterProjection/Filter, ScanStore.

- [x] B03.01 dirty payload의 baseline/result revision, 변경 IDs·속성 종류, topology 유지 여부, 제거/추가 범위와 full-rebuild fallback 조건을 정의한다.
- [x] B03.02 같은 ID라고 같은 데이터라는 가정을 금지한다. dirty payload가 baseline과 맞지 않거나 변경 범위가 불명확하면 full projection을 사용한다.
- [x] B03.03 size-only 변경과 조건 경계 통과를 구분해 membership 및 leaf 기여 delta를 계산하고 영향을 받는 조상만 반영한다.
- [x] B03.04 ancestor tag/hidden, rename·추가/삭제, 시간 조건, filter/mode 변경은 첫 버전에서 보수적으로 full fallback한다. 최적화 범위를 넓힐 때마다 별도 근거/검사를 추가한다.
- [x] B03.05 flat Swift weights 배열의 COW가 작은 변경에도 전체 복사를 만드는지 측정한다. E01 결과에 따라 batch/저장 단위를 결정하고 O(dirty)라고 성급히 주장하지 않는다.
- [x] B03.06 연속 변경·취소·오래된 completion·MCP reader·export reader가 겹쳐도 기존 snapshot/weights를 보존한다.
- [x] B03.07 전체 pass oracle과 모든 leaf/ancestor 값·membership·navigation·history를 매 변경마다 비교한다. 양수/음수 delta·filter 경계·0바이트·detached 상태를 포함한다.
- [x] B03.08 sparse/dense 변경, 동일 branch와 독립 branch burst의 시간/RSS를 비교하고 full fallback 비용도 보고한다.

**완료 기준:** 안전하게 설명한 변경 범위에서만 full pass가 줄고 결과는 동일하다. dirty provenance·COW 비용·fallback이 확인되지 않으면 아직 완료가 아니다.

## B06 — visibility에 맞게 시각 작업을 유예한다

**근거:** W10 pending repaint/occlusion. AppKit에 맞춘 구현이며 원본 DynaSmooth timer 수치를 복제하지 않는다.

- [x] B06.01 표시/부분 가림/완전 가림/최소화/다른 Space/창 분리 상태에서 현재 draw·geometry·timer·CPU를 측정한다. AppKit이 이미 생략한 작업을 이중 제어하지 않는다.
- [x] B06.02 paint-only dirty와 layout dirty를 보관하고, 다시 보일 때 최신 하나를 반영한다. 데이터 scan/projection·MCP 상태 조회는 계속 올바르게 동작한다.
- [x] B06.03 숨김 상태에서 timer/중간 presentation cache가 필요 이상 살아 있지 않도록 한다. 복귀 시 500ms 정책·최신 rect·hit 상태를 일관되게 정한다.
- [x] B06.04 `view_capture` 요청은 현재 상태의 화면을 얻도록 준비한다. geometry 대기를 MainActor semaphore로 막지 않는다. 기존 capture 크기·timeout/오류 계약을 검토한다.
- [x] B06.05 복귀 직후 선택·tooltip·AX·MCP PNG·resize, 창 닫기와 작업 완료 경합을 검사한다.
- [x] B06.06 실제 억제된 작업과 CPU 차이를 확인한다. noise 수준이면 불필요한 새 scheduler를 넣지 않고 측정/미채택 이유를 남긴다.

**완료 기준:** 가려진 조건에서 줄어든 시각 작업이 있고 복귀/캡처가 최신 상태를 보존한다. foreground frame time을 희생하지 않는다.

## 3. 공통 회귀 시나리오

단순 구현을 그대로 반복하는 검사 대신 다음 입력→결과/수명/비용을 확인한다. 기존 검사는 유지하고 변경한 경로에 필요한 검사만 추가한다.

| 시나리오 | 대상 | 반드시 확인할 결과 |
|---|---|---|
| 같은 입력 10회 navigation | B01/B04 | full pass 추가 없음, focus/history/0바이트 선택 같음 |
| 시간 경계를 넘는 같은 filter 재적용 | B01/B02 | 만료 항목 누락 없는 fallback/재평가 |
| tag 미사용/사용·조상 tag·같은 underlying mask | B02/B03 | 필요한 경우만 재판정, metadata/색/revision은 정확 |
| 파일 1개 size 증가·감소/필터 경계 통과 | B03/B04 | leaf·조상·정렬·표시 결과 일치 |
| 추가/삭제/rename·기존 hard-link alias | B01/B03 | 잘못된 id/path/태그 이관 없음 |
| 대량 독립 큐 + 나중 ancestor + root 덮기 | B08 | oracle FIFO·범위·정리 일치 |
| 오래된 snapshot reader + pool 재사용 | E01/B03 | frozen 값 불변, stale pointer/slot reuse 없음 |
| 여러 root·느린 I/O + cancel/닫기/export | E02 | active 상한, starvation/대기 유실·완료 중복 없음 |
| 연속 선택/resize/중단 animation | B04/B05 | geometry·hit·tooltip·AX 현재 위치 일치 |
| 숨김 중 변경 후 복귀/화면 캡처 | B06 | 데이터 최신, 화면 준비·timer 수명 정확 |
| SNS/TXT 대량 출력·권한/용량/경합 오류 | B07 | bytes 동일, 기존 파일 보호, job 실패 정확 |
| 다중 MCP client·stale revision·offline SNS | B01~B07 | 버전 혼합/잘못된 창 선택·접수=완료 오판 없음 |

기존 검사 위치: [NavigationTests](Tests/SpaceSnifferCoreTests/NavigationTests.swift), [MemoryLifetimeTests](Tests/SpaceSnifferCoreTests/MemoryLifetimeTests.swift), [RefreshQueueTests](Tests/SpaceSnifferCoreTests/RefreshQueueTests.swift), [ResourceOptimizationTests](Tests/SpaceSnifferCoreTests/ResourceOptimizationTests.swift), [ReferenceContractTests](Tests/SpaceSnifferCoreTests/ReferenceContractTests.swift), [AutomationTests](Tests/SpaceSnifferAutomationTests/AutomationTests.swift).

## G90 — 통합 검증과 실제 QA

- [x] G90.01 각 채택 작업의 결과 oracle·개선 raw·source hash·명령·미해결 항목을 `docs/validation/`의 새 실험 디렉터리로 묶는다. 기존 baseline raw를 덮어쓰지 않는다.
- [x] G90.02 source/근거 추적성 검사와 변경에 맞는 Swift/TSAN·Python 검사를 실행하고 실제 실행 개수·실패·플랫폼을 기록한다.
- [x] G90.03 별도 QA 앱 인스턴스에서 live scan·filter·navigation·tag·SNS/TXT·MCP 상태/페이지/캡처를 확인한다. 사용자 작업 중인 메인 창과 분리한다.
- [x] G90.04 scoped rescan은 새 cycle/scope/revision 관찰을 포함한다. 현재 smoke의 settled helper만으로 새 rescan 완료를 증명하지 않는다. stop은 실제 진행 중 취소 시나리오를 추가한다.
- [x] G90.05 반복 변경·여러 reader·다중 root·닫기/취소 이후 RSS/retained bytes·active/queued worker·timer가 안정되는지 관측한다.
- [x] G90.06 개선이 없는 후보는 미채택 사유와 측정 결과를 남긴다. 전체 앱 배율·최대 메모리 상한을 제한된 metadata probe로 일반화하지 않는다.

## G99 — 패키징과 완료 판정

- [x] G99.01 Universal arm64/x86_64 release 빌드와 `codesign --verify --deep --strict`를 통과한다. macOS 14 지원을 유지한다.
- [x] G99.02 최종 앱 Resources/MCP script 포함·정식 앱 실제 연결·SNS/TXT CLI 회귀를 확인한다. Rosetta 실행을 실제 Intel 하드웨어 검사로 적지 않는다.
- [x] G99.03 ZIP SHA-256, 실행 로그, 실제 UI/MCP 산출물과 잔여 위험을 `docs/VALIDATION.md`에 갱신한다.
- [x] G99.04 B/E 항목의 설계·구현·검사·측정 결과를 구분해 체크하고 원본 30개 상태 JSON/문서/source hash를 실제 코드에 맞게 재검토한다.
- [x] G99.05 근거 contract, MCP 기술문서·API, 최적화 추림과 README를 최종 상태로 맞춘다. 기록만 갱신하려고 잘못된 `[x]`를 만들지 않는다.

B07과 ArtifactWorker 이관의 결과는 [artifact 검증](docs/ARTIFACT_STREAMING_VALIDATION.md)에 연결한다. E02는 OS thread/긴 I/O 관측 등이 남아 있어 부분 진행이다. A00 완료는 설계·필요한 선행 경계 추출이며 목표16개 전체 구현 완료가 아니다.

### 현재 실행 가능한 검사 명령

아래는 존재하는 명령이다. 이 문서 작성만으로 실행 완료가 되지 않는다. checker가 source hash 변경을 알리면 새 코드를 재검토한 뒤 문서/manifest를 갱신한다.

```sh
python3 scripts/check-engine-evidence.py
python3 scripts/check-windows-optimization-evidence.py
python3 scripts/check-optimization-checklist.py
python3 scripts/check-optimization-plan.py
python3 scripts/check-scan-resource-validation.py --historical
python3 scripts/check-artifact-validation.py --historical
python3 scripts/check-refresh-validation.py --historical
python3 scripts/check-refresh-lifecycle-validation.py --historical
python3 scripts/check-accessibility-cache-validation.py --historical
python3 scripts/check-tooltip-registry-validation.py
swift test --sanitize=thread
python3 scripts/mcp/test_server.py
./scripts/build-app.sh --universal
codesign --verify --deep --strict 'dist/Mac Space Sniffer.app'
```

```sh
# 별도 QA 앱을 실행한 뒤, 존재하지 않는 새 output 경로를 사용
python3 scripts/mcp/integration_smoke.py --bundle-id local.macspacesniffer.mcpqa --output dist/qa-mcp-new-run
```

### 측정 도구·새로 작성할 산출물

| 구분 | 현재 존재/할 일 |
|---|---|
| 기존 metadata probe | `scripts/bench/optimization-audit.swift`, `mcp-query-audit.swift`, `audit-optimizations.py` — [재현 명령](docs/OPTIMIZATION_AUDIT.md) |
| 기존 filter/tree 비교 | `scripts/bench/filter.swift`, `memory.swift`, `compare-resource.py` — [기존 비교](docs/RESOURCE_OPTIMIZATION.md) |
| G00 추가 | cancel/completion·dirty pass·draw/geometry 계측, fixture manifest와 5회 교차 runner |
| E01 추가 | allocation·pool hit/miss/retained/evicted·frozen reader probe |
| E02 추가 | active/queued/blocked·multi-root/느린 I/O·정확히 한 번 완료 probe |
| 결과 보고 | 각 실행의 source/fixture/tool hash·원시값·집계·출력 checksum·측정 범위·미실행 항목 |

새 probe 이름을 문서에 적었다는 이유만으로 해당 도구가 구현되었다고 보지 않는다.

## 4. 후속 실행 R01~R15 — 이전 116개 완료와 별도

사용자 후속 지시에 따라 아래 R ID도 현재 실행 범위다. 이전 TODO에서 남아 있던 기능·원본 동등성 작업을 이어간다. 최적화 채택과 별도 완료 조건을 갖는다. 원래 줄별 체크와 주소/설명은 [보관본](TODO_HISTORY_2026-11-08.md)에 남아 있다.

| ID | 연결 | 미완료 범위·다음 판정 | 현재 상태 |
|---|---|---|---|
| R01 | Q01/Q02 | Windows 실행 환경·동일 fixture로 결과/옵션/동시성/CPU/RSS 비교. 자동 설치·성능 동등성 가정 금지 | [ ] |
| R02 | SNS/Report | Windows 생성 SNS→Mac, Mac 생성 SNS→Windows 양방향 실제 왕복 | [ ] |
| R03 | Q03/W20 | 원본 일반 재배치의 rect 시간 보간·옵션·갱신과 zoom 구별 | [ ] |
| R04 | Q03/W01 | 경로 대소문자/끝 구분자/caller 정규화 cache hit와 종료·재시작 자동 영구 cache 유무 관찰 | [ ] |
| R05 | W03 | focus-first 부분 필터·이미 처리한 subtree skip. 반응성 이득/중간 publish 비용 측정 후 별도 채택 | [ ] |
| R06 | W22/W26/W30 | master/focused scan·직접 변경 처리·중복 범위·취소/병합 순서. E02와 중복되지 않게 의미 계약부터 확보 | [ ] |
| R07 | scan | 접근 거부·스캔 중 삭제·취소 부분 결과, 재스캔 partial publish의 focus/history 조기 정리, free/unknown/missing 규칙 | [ ] |
| R08 | watch | `elementChange` 추가/수정/삭제/rename delta 대조, 부모 재검사 불일치, overflow/폭주/재스캔 중 변경 복구 | [ ] |
| R09 | filter/navigation | 잘못된/반복/빈 조건·Unicode·대소문자·크기/시간 경계, navigation 상세/선택·삭제/rename/태그의 Windows 동적 비교 | [ ] |
| R10 | formats | SNS v2 ANSI·복수 root·확인된 DU loader 문법/escaping·실제 fixture·오류 처리 | [ ] |
| R11 | W27 | Windows XML 엔진 설정 값/범위·사용자 파일 클래스·전체 export scripting/정렬/encoding. lazy cache는 기능 도입과 함께 판단 | [ ] |
| R12 | 대규모 실측 | develop 전체 scan의 실제 최종 합계/오류/OS 용량 차이, 장시간 최대 메모리·종료/취소·반복 변경 관측 | [ ] |
| R13 | Q04/Q05 | filter ID·tag payload·isIncluded 반환 high byte 분리, DU agent `0x4547f0`(body에 `0x455440` 포함) 분석 | [ ] |
| R14 | W17/W18/W23/W25/W28/W29 | bulk metadata·path 압축·계층 hit-test·stream reader·lookup hint는 개별 profile 뒤 재선정. 불필요하다고 단정하지 않음 | [ ] |
| R15 | MCP P03 | subtree cursor/검사 budget/취소 연동·query context 재사용. 원본에 MCP가 있었다고 표현하지 않음 | [ ] |

### R 후속 반영 단위

상위 R 전체 요구가 남아 있더라도 실제 반영·관측한 부분은 별도로 체크한다. 근거와 측정 시점은 [후속 실행 기록](docs/BACKLOG_EXECUTION_2026-11-09.md), 누락 검토는 [독립 검토](docs/R_BACKLOG_REVIEW_2026-11-09.md)를 따른다.

- [x] R07/R08 취소 rescan baseline·중간 navigation 보존·truncated issue root 승격.
- [x] R07 live volume 회계 계산과 MCP 시점/잔여/진단 노출. 완료율 계산은 제공하지 않는다.
- [x] R09 age 소수초/zero·glob 줄바꿈·빈 세미콜론·identity replacement 회귀 수정.
- [x] R10 SNS v2 원본 ANSI page·복수 root 읽기/선택·CLI/MCP·네이티브 UI 합성 fixture 검증.
- [x] R11 XML/file classes/export script Core·CLI/MCP 명시 선택·atomic output/cap 검사.
- [x] R11 원본 file LF·child-array 동률 순서를 독립 bytes로 정정하고 과거 raw 보존.
- [x] R12 새 고정 CLI 전체 develop scan·4개 실제 접근 오류·용량/메모리 raw 보존.
- [x] R13 tag payload/isIncluded high byte/filter generation/paint marker 정적 의미 구분.
- [x] R14 bulk/adaptive를 실측하고 wide 회귀로 기본 미채택. SNS write/read batch pool 실익 측정.
- [x] R15 subtree cursor/context/budget/cancel/revision reset·늦은 시작 fence·실제 MCP 검사.
- [x] 대형 실제 SNS 6,986,409노드 열기·조회·교체 후 작은 모델/137MB footprint 회복 관측.
- [x] R06 owner별 focus 요청 수명·직렬 admission·앱 연결·26개 회귀. 별도 병렬 master/focus 동등성은 미완료.
- [x] R10 원본 DU grammar strict reader·CRLF·missing6·정확 UTF16 이름·adapter/오류 처리 검증. Windows 실제 DU 비교는 미완료.
- [x] R11 XML 생성 경계·템플릿 반복 길이 최적화 회귀, 전체 release244개/1성능skip/0실패.
- [ ] R01~R04 및 Windows 동적 대조가 필요한 항목: 실제 Windows 실행 환경에서 검증.
- [x] R12 최종 새 엔진에서180초·198회차·22,176변경 수렴/감시중지와 실제 대형 import 취소 관측. 수시간/생산 환경 보장은 아님.

기존 상속 tag context·root 공유·palette cache·최신 작업 취소·필터 사전 파싱은 유지 대상이다. 다시 구현하는 대신 영향을 받는 회귀 검사를 수행한다. 원본/플랫폼/UI 경계와 미해결 전체는 [30개 체크리스트](docs/OPTIMIZATION_CHECKLIST.md)를 참조한다.

문서 자체는 `python3 scripts/check-optimization-plan.py`로 검사한다. [검사 기록](docs/validation/optimization-plan-documentation-check.json)은 116개 실행 체크 항목·14개 작업 그룹(완료/미완료는 별도 집계)·15개 잔여 범위·30개 원본 판정의 정합성과 보관본 hash를 확인하며, 실제 최적화 구현이나 성능을 증명하지 않는다.

## 5. 작업 종료 때 남길 한 장의 기록

각 B/E 작업은 다음 필드를 채우고 관련 `[ ]`를 체크한다. 문서만 채운 상태와 코드를 채택한 상태를 구별한다.

| 필드 | 기록할 내용 |
|---|---|
| 작업/판정 | ID, 범위, 채택/미채택/부분/계속 조사 |
| 원본 근거 | W ID, 함수 주소, 전체 Evidence ID 또는 이를 가진 원문 링크 |
| Mac 변경 | 실제 파일·의미 변화·cache/worker 수명·fallback |
| 동등성 | reference 입력·결과 checksum/바이트·새 회귀와 기존 검사 로그 |
| 비용 | before/after raw 경로, sample 수·중앙값/범위, RSS/할당·대기/취소, 포함/제외 구간 |
| 실패/한계 | 불일치·noise·누수/과도한 retained memory·실제 미실행 환경 |
| 패키징 | 최종 build/signature/ZIP hash; 해당 작업 단계에서 패키징했을 때만 |
| 상태 갱신 | 이 TODO, 관련 checklist/선택 문서·source hash·검증 문서의 반영 여부 |

**전체 완료 판정:** 선택한 작업의 체크만 모두 채우는 것이 아니라, 개선이 입증된 변경만 채택하고 보류/미해결을 남겨 사용자가 현재 상태를 오해하지 않게 한다. Windows 동적 비교 미완료를 Mac 단위 테스트나 정적 근거 검사로 대신 완료 처리하지 않는다.
