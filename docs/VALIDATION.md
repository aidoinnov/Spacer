# 검증 결과

2026-11-09 최적화 후속의 현재 기준은 [최종 통합 검증](FINAL_OPTIMIZATION_VALIDATION.md)이다. 126개 전체 TSAN/release·Python 6개·정식 bundle MCP·Universal/strict signature·arm64/Rosetta CLI, 150 kernel 표본과 실제 앱 이동/resize 각 버전 200회를 기록했다. 실행 체크 116/116과 native Space/부분·완전 가림 matrix를 완료했다. 아래의 이전 수치는 당시 단계 기록으로 보존한다.

2026-11-08, Apple Silicon Mac, Swift 6.2.4, 최소 macOS 14.

| 항목 | 결과 | 근거 |
|---|---|---|
| 단위·통합 테스트 및 ThreadSanitizer | 51개 통과, 실패 0, 데이터 경합 보고 없음 | [로그](validation/mcp-thread-sanitizer.txt) |
| Universal release | arm64 + x86_64 빌드 성공 | [빌드 로그](validation/mcp-universal-build.txt) |
| 앱 서명 | `codesign --verify --deep --strict` 통과 | ad-hoc 서명, 공증 미실행 |
| 근거 연결 검사 | core 16파일 / 계약 23개 / REA 기록 107개 통과 | `scripts/check-engine-evidence.py` |
| arm64 CLI → SNS | 파일 13개, 폴더 9개, 논리 16,850,087 / 할당 16,883,712 bytes | [출력](validation/apple-silicon-cli.json) |
| Rosetta x86_64 SNS 읽기 → TXT | `*.zip;*.dmg` 결과 5,000,000 논리 bytes | [출력](validation/intel-rosetta-cli.json), [파일 목록](validation/native-files.txt) |
| 별도 QA 앱 UI | 확장 폴더 헤더 용량, 클릭 상세 노출, 확대 후 상위 이동 확인 | [용량 화면](validation/motion-capacity.png), [상위 버튼](validation/motion-parent.png) |
| 레이아웃 전환 | 전환 프레임 수집, 500ms 곡선과 사각형 보간 단위 테스트 통과 | [프레임](validation/motion-detail-1.png) |

ZIP SHA-256: `2dae626fdfd758974935763602448f01c46cd570c31f859e728b336b69ea5058`.

## 검사 범위

경로별 크기 합산(하드 링크 경로 포함), 심볼릭 링크 제외, 취소, 원본 필터·태그 계약, 독립 구성 SNS golden bytes와 잘못된 레코드 거부, Windows 경로 보존, 트리맵 면적, 선택 시 상세 단계 증가를 검사했습니다. 공유 루트의 중복 스캔 방지와 마지막 구독 정리, 실제 FSEvents 변경, 하위 트리 갱신, 이름 변경 태그 유지, 최신 대기 작업 교체와 메인 스레드 밖 실행, artifact actor I/O도 포함합니다.

이번 변경인 경로 큐·캐시 수명·NavigationState·rename 경로 대응·projection 연결까지 포함해 ThreadSanitizer 34개 테스트와 Universal 빌드를 통과했습니다. 사용자의 기존 실행 창은 종료하지 않았습니다.

## 한계

REA는 정적 분석입니다. Windows 원본과의 동적 결과·타이밍 동등성, 실제 원본이 생성한 SNS와 양방향 왕복은 검증하지 않았습니다. 근거 연결 검사는 추적성을 확인하며 동등성을 증명하지 않습니다. 일반 재배치의 원본 위치 보간도 미확인입니다.

Intel 실행은 Rosetta이며 실제 Intel 하드웨어 검증은 아닙니다. 수백만 파일 장기 부하, 전체 디스크 접근 권한을 적용한 전체 시스템 스캔, 실제 사용자 파일 휴지통 이동은 포함하지 않았습니다. SNS v2·복수 루트·SNF·전체 export scripting·master/focused scan 동시 실행 등의 남은 범위는 [분석 기록](ENGINE_REVERSE_ENGINEERING.md)에 명시합니다.


## 추가 캐시·탐색 검증

- 완료된 루트 재사용 시 재스캔 없이 이전 결과·태그 공유. 명시적 재스캔 후 갱신, 마지막 구독 해제 뒤 새 스캔·태그 초기화 확인.
- 정규화된 동일 경로 공유와 부모/자식 루트 분리, 감시 구독 수명 확인. 마지막 감시 구독 해제 시 다른 뷰로 상태 전달 누락을 수정하고 회귀 검사.
- 변경 경로의 중복·조상 packing, 독립 분기 FIFO, prefix 경계와 대기 항목 보존 검사.
- 삭제된 조상의 가까운 생존 부모로 focus 이동, selection 해제, history 중복 병합 및 index 보존 검사.
- 필터 제외 후 부모 이동, 필터 해제 후 위치 유지, 0바이트 일치 항목의 selection, rename 뒤 focus·selection·history 유지 검사.

최종 Universal 앱의 별도 QA 복사본에서 실제 FSEvents로도 확인했습니다. QA fixture의 `a/deep`을 `a/renamed`로 바꾼 뒤 확대 위치 `inner` 유지([화면](validation/state-rename.png)), `*.txt` 필터 적용 뒤 부모 `a` 이동([화면](validation/state-filter-parent.png)), 필터 해제 후 `a` 유지, 다시 확대한 폴더를 스캔 범위 밖으로 옮긴 뒤 `a` 이동([화면](validation/state-removed-parent.png))을 확인했습니다. 사용자 파일을 옮긴 실험은 아닙니다.

Windows 동적 비교는 미실행입니다. 이 호스트의 Parallels VM 목록은 비어 있었고 Wine 실행 파일도 없었습니다. [추가 분석](CACHE_AND_REPAINT_FINDINGS.md)에 정적 근거와 미확인 범위를 구분했습니다.


## 대규모 진행 정체 수정

원본 deltaSize에 따른 실시간 조상 합산, 중간 snapshot 발행량 제한, heartbeat와 tree revision 분리, POSIX 디렉터리 열거를 반영했습니다. 최종 소스 기준 ThreadSanitizer 34개 테스트, arm64/x86_64 release와 양쪽 CLI 검사를 통과했습니다.

실제 별도 QA 앱에서 현재 경로·검사/대기 폴더·일부 결과·진행 중 오류 수([화면](validation/scan-progress-live.png)), 접근 오류가 있는 완료 상태의 `검사 종료 · 접근 오류 있음`([화면](validation/scan-progress-errors.png))을 확인했습니다. 단일 접근 오류 fixture는 CLI exit 2와 issues=1도 확인했습니다([출력](validation/scan-access-error-cli.json)). fixture 권한은 검사 후 복원했습니다.

전체 develop 볼륨의 최종 합계 검증은 완료하지 않았습니다. 기존 앱은 관찰 당시 계속 스캔 중이었고 168.95GB에서 190.02GB까지 증가했습니다. 별도로 시작한 전체 볼륨 벤치마크는 시스템 부하를 줄이기 위해 중단했으며 완료 성능 수치로 사용하지 않습니다. [조사 기록](SCAN_PERFORMANCE.md)에 샘플·검사 범위와 한계를 남겼습니다.


## 메모리 수정 최종 검증

페이지 단위 snapshot, 추적 경로만 인덱싱, dictionary 없는 subtree 병합, 완료 작업 입력 해제를 포함한 최종 소스로 ThreadSanitizer 39개와 Universal 빌드를 통과했습니다. 동일 25만 파일 입력의 전후 peak RSS 및 실제 QA 앱 25만 파일 로드/탐색 관측은 [메모리 검증](MEMORY_VALIDATION.md)에 기록합니다.


## 추가 리소스 최적화 최종 검증

현재 소스는 ThreadSanitizer 44개, Universal arm64/x86_64, 서명 및 양쪽 CLI 검사를 통과했습니다. 필터/메타데이터 변경의 직전 빌드 대비 교차 측정과 실제 변경 감지 검사는 [추가 최적화 기록](RESOURCE_OPTIMIZATION.md)에 있습니다.


## 한 줄 헤더

별도 content 헤더를 제거하고 로고·제목·폴더 스캔·더 보기 버튼을 native unified compact toolbar 한 줄로 통합했습니다. Universal 빌드와 앱 재실행 후 버튼 라벨·좌우 정렬을 [실제 화면](validation/single-header.png)으로 확인했습니다. 이 변경은 UI에 한정하며 위 코어 테스트 이후 엔진 변경은 없습니다.


## MCP 실제 앱 검증

사용자 전용 Unix socket과 STDIO bridge를 통해 실제 앱의 ScanStore/worker를 제어했습니다. 원본 엔진 계약을 바꾸지 않았습니다. ArtifactWorker에는 MCP 저장의 덮어쓰기 거부 옵션만 추가했으며 기존 UI 저장 기본값은 유지했습니다. 연결 탐색 중 즉시 닫힌 클라이언트에 답변할 때 발생하던 SIGPIPE를 `send(MSG_NOSIGNAL)`로 방지하고 해당 연결 패턴을 소켓 테스트에 추가했습니다.

- Swift ThreadSanitizer **51개**, 실패·경합 0. Python 프로토콜/검증/STDIO 테스트 **6개** 통과.
- 별도 bundle ID의 실제 QA 앱에 **99회 MCP 요청**, 도구 20개 카탈로그, 정확한 3,145,728 bytes/파일 2개 스캔 확인.
- node 상세·페이지·stale revision·native filter·상위 K·오류, 상위/뒤로/루트 이동·크기 모드·깊이·태그 확인.
- 실제 RSS/physical footprint/누적 CPU·worker·볼륨 정보와 MCP resource 읽기 확인.
- SNS 저장/오프라인 읽기·TXT export 작업 완료, 기존 출력 거부, scoped rescan/stop 확인.
- MCP PNG를 디코딩하고 [화면](validation/mcp-capture.png)을 직접 확인했습니다. content view 캡처로 native toolbar는 포함하지 않습니다.
- Universal arm64/x86_64 재빌드 및 `codesign --verify --deep --strict` 통과. QA 앱을 종료하고 대기 중이던 메인 앱을 새 빌드로 재실행해 실제 MCP 상태·자원 조회를 확인했습니다.

[99회 호출 결과](validation/mcp-integration.json), [메인 앱 조회](validation/mcp-main-status.json), [사용법](MCP.md). Codex `mac_space_sniffer` 등록은 enabled 상태입니다. 현재 대화의 도구 목록은 재연결/새 세션 전에는 갱신되지 않을 수 있습니다. 이번 검사는 실제 STDIO 클라이언트로 수행했습니다. 수백만 노드에서의 MCP 장기 부하와 실제 Intel 하드웨어 실행은 이번 검사에 포함하지 않았습니다.


## MCP 기술문서 검증

2026-11-08에 [기술 설계서](MCP_TECHNICAL_DESIGN.md)와 [API 상세 명세](MCP_API_REFERENCE.md)를 현재 코드·보관된 실행 기록과 대조해 작성했습니다. 도구 20개의 입력표와 예시는 런타임 `TOOLS` schema와 대조했고, [카탈로그](mcp-tool-catalog.json)에 원본 bridge 소스 SHA-256을 기록했습니다.

[문서 검사 결과](validation/mcp-documentation-check.json): JSON 예시 34개 파싱, 도구 arguments 예시 20개 schema 검증, 문서 내 로컬 링크 31개 대상 존재, 기록된 창 상태 필드 38개 설명 포함을 확인했습니다. 이 단계는 문서 변경 검증이며 앞서 보관한 Swift 51개·Python 6개·QA 99회 실행을 새로 수행한 것으로 보고하지 않습니다. 실제 구현의 timeout/취소·공유 루트·비동기 반영·대규모 조회/출력 메모리·통합 smoke 한계도 문서에 명시했습니다.


## Windows 원본 최적화 재조사

2026-11-08에 동일 SpaceSniffer 2.2.0.27 x64 EXE를 Ghidra/REA로 추가 분석했습니다. 기존 107개 + 새 32개, 총 [139개 기록](windows-optimization-rea-evidence.json)에서 [20개 기법](WINDOWS_OPTIMIZATIONS.md)을 추출하고 함수 53개의 원문을 별도로 보관했습니다. `scripts/check-windows-optimization-evidence.py`로 EXE SHA-256, bundle digest, Evidence의 target/authority/operation/address, 모든 추출 payload 일치를 확인했습니다. 원문 문서의 로컬 링크 69개와 20개 항목의 연결도 확인했습니다. 기존 core 16파일/계약23개/기존 REA107개 추적성 검사도 통과했습니다.

이는 정적 관찰과 문서 정합성 검증입니다. Windows를 실행해 성능·동시성·실제 옵션을 측정하거나 Mac 엔진에 새 기법을 적용한 검증은 아닙니다. 특히 원본 큐의 TList 중첩 비교, thread pool data 기본 제한값 1, SNS writer decompiler 경고, 일부 tooltip TextExtent 잔존을 함께 기록했습니다. Swift/Python runtime 테스트를 이번 문서 변경 때문에 새로 실행했다고 보고하지 않습니다.


## 최적화 통합 체크리스트 누락 감사

2026-11-08에 최초 20개에서 빠진 독립 기법 10개를 추가하고 [30개 항목](OPTIMIZATION_CHECKLIST.md)을 현재 Mac 소스와 대조했습니다. 상태는 대응 구현 6 / 부분 대응 6 / 핵심 미적용 11 / 플랫폼 대체 6 / 적용 검토 1입니다. 최초 bundle의 미참조 pseudocode 55개를 차집합으로 구해 모두 처리 상태를 부여했고, 1개 DU/SNF agent 항목은 미해결로 남겼습니다. 이는 원본 전체 함수·모든 instruction의 완전성 검증이 아닙니다.

기존 139개와 이번 새 세션에서 보관한 [추가 6개 REA 기록](windows-optimization-coverage-rea-evidence.json)을 분리해 총 145개를 추적합니다. `scripts/check-optimization-checklist.py`는 30개 ID/최초 ID 보존, 추가10개, 미참조55개 차집합, 두 bundle/EXE/원문/source hash, source/test anchor, 상태 합계, 문서 링크148개 일치를 확인했습니다. 기존 원본20개 근거 검사와 core16파일/계약23개 추적성도 유지했습니다.

이번 작업은 목록·근거·소스 정합성 감사입니다. 새 최적화를 Mac 코드에 적용하거나 Swift/Python runtime 테스트를 새로 실행한 것으로 세지 않습니다. Windows runtime 동등성 검증은 30개 모두 미완료로 표기했습니다.


## 최적화 실행 TODO 구체화

2026-11-08에 [실행 TODO](../TODO.md)를 13개 작업 그룹·106개 미완료 실행 항목으로 정리했습니다. G00 기준선 → E01 노드/page/scratch 풀 및 E02 blocking I/O 실행·worker/admission 평가 → B01~B08 → G90 회귀 → G99 패키징의 의존성과 완료 기준을 기록했습니다. W15/W16은 단순 보류에서 선행 평가로 변경했으며 실제 코드 대응 상태는 변경하지 않았습니다. 이전 TODO 259줄은 [보관본](../TODO_HISTORY_2026-11-08.md)에 SHA-256 `ffe5f5cf86157ff1bd4dbccbc3abff376099a9e728a915c72a87374b67972350`로 보존했습니다. 남은 원본 동등성·기능 과제는 R01~R15로 이어갑니다.

`python3 scripts/check-optimization-plan.py`로 실행 항목 ID/미완료 상태·30개 원본 판정/집계·풀 평가 우선순위·source checklist hash·로컬 링크·보관본 hash를 확인했습니다. [문서 검사 결과](validation/optimization-plan-documentation-check.json)를 보관합니다. 기존 core/Windows/checklist 근거 검사 3종도 통과했습니다. 이번 변경은 TODO·선택 문서와 문서 검사 도구에 한정합니다. 엔진 변경, 새 성능 측정, Swift/Python 앱 테스트, Windows 실행 비교는 수행하지 않았습니다.


### 단일 책임 모듈 설계 보강

후속 검토에서 기존 TODO의 모듈 소유권 명세가 부족함을 확인하고 [설계 문서](OPTIMIZATION_MODULE_DESIGN.md)를 추가했습니다. 현재 코드의 책임 결합 7곳, M01~M16 논리 경계, UI/MCP adapter의 책임, 입력/출력·의존 방향·cache/pool/worker 종료 계약을 기록했습니다. TODO A00 10개를 추가해 최신 실행 명세는 **14개 작업 그룹·116개 미완료 항목**입니다. 이전 절의 13개/106개는 보강 전 기록입니다.

문서 checker는 M01~M16 및 A00 연결, 기존 30개 원본 판정, 잔여 R01~R15, 보관본 hash와 로컬 링크를 확인합니다. 근거 checker 3종도 재확인했습니다. 이 검사는 설계 문서 정합성에 한정되며 실제 SRP 추출, pool/executor 도입, 런타임 회귀·성능 측정은 미완료입니다.


## ProjectionSession 실제 구현 — 2026-11-09

[구현 검증 기록](PROJECTION_SESSION_VALIDATION.md)에 최소 책임 추출·탐색 reuse·동일 값/복합 요청 축소를 정리했습니다. 수정 전 Swift 51개와 수정 후 **59개 TSAN**, Python 6개, 별도 실제 QA STDIO 95요청, Universal arm64/x86_64 빌드·strict signature 및 packaged CLI SNS/TXT 왕복 바이트 비교를 수행했습니다. 사용자 메인 앱은 재시작하지 않았습니다. 새 앱과 ZIP은 dist에 갱신했습니다. ZIP SHA-256은 `1b0dd94ac14b9a1e612bbfb2b0e9249b80c2ce716e1e49d2f1f65ba1df414727`입니다.

최종 release 5쌍의 25만 파일 metadata/탐색10회 비교는 전체 평가 766.27ms → 실제 session 34.06ms 중앙값입니다. 초기 pass·geometry/paint·디스크 I/O·전체 develop·UI p95는 별도이며 전체 앱 배율로 일반화하지 않습니다. [raw](validation/projection-session-2026-11-09.json)와 [QA counter/실행 로그](PROJECTION_SESSION_VALIDATION.md)를 보관했습니다. W02는 대응 구현, W06은 부분 대응으로 재검토해 현재 상태는 7/7/9/6/1입니다. Core 18개 파일/25개 contract로 새 파일도 분류했습니다. Windows runtime과 pool/executor·나머지 최적화는 미완료입니다.


## 스캔 실행기와 private context — 2026-11-09 후속

[상세 검증](SCAN_RESOURCE_VALIDATION.md)에 ScanAdmission/ScanWork/FilterScratch 구현과 한계를 기록했습니다. active8/queued64는 OS thread 수가 아닌 작업 슬롯 상한입니다. 실제 membership allocation은 80회/162,640bytes → 45회/83,625bytes였습니다. 누적 할당이며 전체 앱 RSS 감소 수치가 아닙니다. 실제 파일시스템 1/8/32 roots×K조건을75표본, filter/response25표본, allocation5profiles로 보관했습니다.

이번 기준선에서는59개 assertion 성공 뒤 TSAN 경고7개/exit1이 재현됐습니다. Job payload 인계를 명시적으로 동기화한 뒤 최종 **Swift68 TSAN exit0/경고0**, Python6, 분리된 QA 실제 STDIO101요청이 통과했습니다. 포화·취소·재구독은 injected scanner의 controlled 회귀로 보완했습니다. xctrace attach 실패는 원문을 남기고 MallocStackLogging으로 대체했습니다.

Universal arm64/x86_64·strict signature·packaged MCP·CLI SNS/TXT 왕복을 확인했습니다. 새 ZIP SHA-256: `550fd9fd5c327e9c6b1ea321b2eb17c77d58d2f561306bd7c96efc197e44b953`. 이전 절의 ZIP hash/59개 검증은 그 단계의 기록입니다. 최신 기준은 이 절과 상세 검증입니다. 메인 앱의 idle/실행 job 없음·구독0을 확인한 뒤 새 bundle로 재실행했고, 새 PID와 실제 scan_limit8/capacity64를 read-only MCP로 확인했습니다. Core21파일/28contracts로 재검토했으며 node/page pool 전체·ArtifactWorker 격리·Windows runtime 동등성은 미완료입니다. `scripts/check-scan-resource-validation.py`는 기록된 source/raw/ZIP hash와 결과·상한의 정합성만 검사하며 테스트를 새로 실행하는 도구가 아닙니다.


## Artifact I/O·SNS/TXT streaming — 2026-11-09 후속

[상세 검증](ARTIFACT_STREAMING_VALIDATION.md)에 B07·ArtifactWorker I/O 이관을 기록했습니다. 수정 전68/최종81개 TSAN, Python6, 별도 실제 QA STDIO133요청이 통과했습니다. independent 이전 writer와 Unicode/Windows path/flags/tags/시각/zero-byte·scope를 대조하고 write/close/publish/race·actor queue·scan+artifact 겹침을 검증했습니다.

25만 metadata 파일 full/scoped SNS/TXT release40표본의 bytes/SHA가 일치했습니다. full TXT peak RSS 중앙값108.45→81.64MiB, SNS111.84→90.33MiB입니다. fixture를 포함한 process peak이며 앱 전체 RSS 개선율이 아닙니다. 작은 focus SNS 시간은 소폭 증가하고 범위가 겹쳤습니다. [raw](validation/artifact-export-2026-11-09.json)를 보관했습니다.

Universal/strict signature·packaged MCP·CLI full/filtered SNS-TXT 왕복을 확인했습니다. 새 ZIP SHA-256은 `f0a92ca9c7312435c1eb20816d325fc4fe34761b072a28b831413fed8d5be590`이며 exact ZIP/source archive를 별도 보관했습니다. 이전 scan 검증은 당시 source/tests를 이전 SHA와 일치시켜 보관한 historical mode로 유지합니다. 과거 benchmark hash를 현재 코드의 hash로 덮어쓰지 않았습니다. Core28파일/34contracts, W19 대응 구현으로 현재 상태8/7/8/6/1입니다. Windows runtime·장시간 실제 볼륨/확장 filesystem·job 영속/cancel·나머지 최적화는 남아 있습니다.

메인 앱의 idle/실행 job 없음을 확인하고 새 bundle로 재실행했습니다. artifact 검증 폴더의 main-before/main-after에 새 PID·idle와 volume I/O main_thread_runs0을 보관했습니다.


## 이벤트 큐 후속 검증

2026-11-09 B08 큐 index/FIFO 구현 및 전후 측정은 [이벤트 큐 검증](REFRESH_QUEUE_VALIDATION.md)에 별도로 기록한다. Swift ThreadSanitizer 88개/Python 6개, 독립 배열 oracle과 연산별 대조, 작은 큐/대량 큐 100개 교차 표본을 포함한다. 대량 큐에서 속도 이득과 추가 peak RSS가 함께 발생했다. B08.08의 active burst 취소/stale callback/live queue bytes 직접 관측은 아직 완료하지 않았다.


큐 단계 최종 앱 검증: 별도 QA 앱 MCP 106회, 추가 실제 48분기 burst 25회 요청 통과. Universal/signature 및 메인 앱 새 PID 재실행 확인. 현재 core 29파일/계약 35개·Windows 보존 근거·30개 항목·116개 TODO 상태·기존 scan/artifact historical hash·새 큐 결과 검사를 모두 통과했다. [검사 출력](validation/refresh-queue-2026-11-09/evidence-checks.json). TODO는 53개 체크/63개 미완료이며 B08.08은 부분 진행이다.


## B08.08 후속 완료

[수명·취소 검증](REFRESH_LIFECYCLE_VALIDATION.md): Swift TSAN 90개/Python 6개 통과. 실제 FSEvents 대기 48개/인덱스 152슬롯에서 running scan 취소, 실제 Storage weak 해제, stale monitor/root recreation callback 차단 및 재스캔 96 bytes 수렴을 확인했다. weak 소멸이며 deep byte/RSS 반환량 측정은 아니다. B08.01–08 검증 범위 완료, 전체 TODO 54개 체크/62개 미완료. 이전 53/63 상태와 88개 테스트는 앞 단계 기록이다.


이번 lifecycle QA 앱 MCP 87회 + 추가 burst 27회, Universal/signature 및 메인 앱 새 PID 재실행 확인. [최종 근거 검사](validation/refresh-lifecycle-2026-11-09/evidence-checks.json)와 source/버전 ZIP을 보존했다. 과거 queue 성능 raw와 hash는 그대로 두고 historical 검사로 구분한다.


## B05 AX 부분 후속

[접근성 요소 재사용](ACCESSIBILITY_CACHE_VALIDATION.md): Swift TSAN 94개/Python 6개/MCP 175회 통과. native AX 버튼 선택을 UI와 현재 selected_path로 확인했다. AppKit 구성 요소 60회/1만 후보에서 요소 생성 30,000→500개·후보 방문 600,000→30,000회, duration 중앙값 197.35→17.08ms. 실제 draw/full-frame 측정은 아니다. Universal/signature·보존 근거 검사를 통과했다([검사](validation/accessibility-cache-2026-11-09/evidence-checks.json)). B05.05/06만 완료, 전체 TODO 56개 체크/60개 미완료다.


## B05.04 툴팁 등록 수명

[검증](TOOLTIP_REGISTRY_VALIDATION.md): Swift TSAN 99개/Python 6개, tooltip 단위 5개 추가 및 실제 MCP 92회 통과. native registry 구성 요소 1천 영역/60회 고정 갱신은 206.25→4.68ms, 등록 60,000→1,000회였다. 이동 중에는 양쪽 60,000회 등록을 유지하며 새 peak RSS가 약 1.6MiB 늘었다. 전체 frame 결과가 아니다. B05.04만 추가 완료해 TODO 57개 체크/59개 미완료. W14는 원본 bitmap cache와 구분한 플랫폼 대체이며 현재 30개 상태는 대응8/부분7/미적용7/플랫폼7/검토1이다.
