# R01~R15 후속 실행 기록

2026-11-09. 기존 최적화 실행116/116은 이전 단계다. 사용자 후속 지시는 별도 R01~R15까지 수행하는 것이다. 아래는 **진행 기록**이며 Windows 실행을 Mac 회귀나 정적 분석으로 완료 처리하지 않는다.

| ID | 진행 | 근거·구현·남은 확인 |
|---|---|---|
| R01 | 환경 필요·harness 준비 | 현재 Parallels 등록 VM은 비어 있다. 기존 Windows VM/PC 정보를 사용자에게 요청했다. 원본 실행·새 OS 설치·라이선스 동의를 했다고 주장하지 않는다. [실행 harness](R01_WINDOWS_RUNTIME_HARNESS.md)는 frozen hash/CLI help로 준비했으나 Windows 실행·PowerShell AST 검사는 미실행이다. |
| R02 | Windows 왕복 필요 | Mac codec/golden과 실제 원본 SNS 양방향 비교는 별개다. |
| R03 | Windows 장면 필요 | zoom500ms/곡선·paint 강조와 일반 rect 재배치를 구분한다. 실제 원본 재배치 영상은 없다. |
| R04 | 정적 추가 조사 | RAM cache는 경로/agent GUID 비교 후 miss에서만 ExpandFileName. 명시적 CLI save/autosnapshot은 재시작 자동 복원 cache가 아니다. 실제 경로 변형/재시작 관찰은 Windows에서 한다. |
| R05 | 후보 실험 | focus-first+skip·loop-fusion control·기존 full oracle 비교. immutable reader COW·cancel 포함. production 반영은 통합/실익 확인 후 결정한다. |
| R06 | owner 수명·직렬 admission 구현 | 별도 focused worker/동일 node busy guard와 Mac immutable publication을 연결해야 한다. [owner/job/범위 계약](R06_FOCUS_WORKER_CONTRACT.md)을 작성했다. 현재 root별 직렬 scope 작업을 별도 focus worker와 같다고 하지 않는다. |
| R07 | 수정·추가 분석 | 취소 rescan baseline/cancelled, 중간 결과 탐색 손실, 접근/삭제 회귀 수정. [회계 근거](R07_SPACE_ACCOUNTING_FINDINGS.md), [수명 수정](R07_R08_SCAN_FOLLOWUP.md). |
| R08 | 복구 수정 | truncated 오류 수 scoped merge를 root rescan으로 승격. 실제 FSEvents burst/loss·running scan 복구와 frozen reader 검사. Windows notify 동적 대조는 별도다. |
| R09 | 수정·선택 검증 | age 소수초/zero, glob LF·CRLF/끝, 빈 세미콜론, 같은 path의 다른 identity 오승계 수정. [근거·41개 선택 검사](R09_FILTER_FOLLOWUP.md). Windows Unicode/ACP 대조는 남는다. |
| R10 | SNS/DU adapter 통합 | SNS v2 원본 ANSI codepage 명시 선택, 복수 top-level tree 읽기/쓰기/선택 추가. 확인한 다른 loader는 `.DU`이며 `SNF`와 혼용하지 않는다. native UI/CLI/MCP 검증과 encoding 한계 기록 필요. |
| R11 | parser/adapter 구현 | XML·file class·export script 원문과 공식 manual 대조. 실제 file은 binary wb+·UTF8/LF, preview는 CRLF. 기존 CRLF 가정을 정정하며 과거 raw 보존. |
| R12 | 전체 scan 관측 | 6,236,823 files/855,528 folders, allocated487,455,928,320B, logical470,275,951,137B, 오류4, 약213초. capacity499,898,105,856B는 파일 합계가 아니다. |
| R13 | 정적 오해 해소 | payload는 tag byte+old/new 문자열, high byte는 isIncluded 반환. filterID는 generation/paint marker이며 skip proof가 아니다. [30개 기록·24함수](R13_INVALIDATION_FINDINGS.md), DU는 R07 근거와 연결. |
| R14 | 실측 후 선별 | 실제709만 노드 경로/stride, POSIX/bulk metadata oracle 비교. SNS batch pool은 동일 바이트로25만 파일5쌍 확인. [adaptive V2](R14_ADAPTIVE_V2.md)도 wide에서 약19% 느려 POSIX 기본값을 유지한다. SNS reader batch pool은25만파일5쌍에서 decoder RSS232.0→210.6MB, decode0.910→0.804초(공유 host 관측)였다. 자동 일괄 채택하지 않는다. |
| R15 | 구현·native QA 완료 범위 | subtree cursor/budget·context 재사용·explicit cancel·reset. [계약·21개 선택 검사](R15_QUERY_FOLLOWUP.md). STDIO notification 선점은 미지원. |

## 실제 develop와 메모리

[전체 scan raw](validation/r-backlog-2026-11-09/live-volume-baseline/result.json)는 이전 배포 CLI를 별도 경로에 고정해 실행했다. [실행기](../scripts/bench/live-volume-scan.py)는 statvfs 전후, 소유 CLI RSS 표본, time raw를 저장했다. 라이브 파일시스템·다른 사용자 작업과 겹친 절대 관측이며 원자적 snapshot/공정한 속도 비교가 아니다.

- SNS744,975,698B, SHA-256 `ffee4c3f9d58eb8fd62bb6f095a600db0ef495ccce0d02aa1c386d39e8f7a3f4`. [보존 위치](validation/r-backlog-2026-11-09/live-volume-baseline/archive.json)에 생성 파일 이동/hash를 기록했다.
- 최대 RSS1,982,005,248B, peak footprint6,442,819,696B. scan+filter+SNS 저장을 포함하며 RSS/footprint를 혼동하지 않는다.
- [batch pool 비교](validation/r-backlog-2026-11-09/artifact-pool-memory/report.json): 25만 long-path/Unicode 파일·fresh5쌍. 중앙 peak footprint201,589,504→178,914,072B, RSS203,915,264→181,288,960B. emit+finish0.495→0.509초로 소폭 증가했고 전체 scan 속도 개선으로 주장하지 않는다. SNS 출력은 old writer와 byte hash가 같다.
- free/unknown과 접근 오류 수는 같은 값이 아니다. APFS metadata/snapshot/공유·압축/하드 링크 경로별 집계·실시간 변경·접근 불가 때문에 OS used와 pathname 합계가 다를 수 있다. 오류4건의 경로는 최종 `--issues` 실행에서 추가 확인한다.

## 통합 원칙

과거 raw/source/ZIP은 덮어쓰지 않는다. 과거 Mac writer와 byte 일치만으로 Windows newline/tie 순서를 증명할 수 없었으므로 이번 원본 bytes/함수와 독립 fixture로 보완한다.

메인 사용자 scan/watch의 실행을 read-only MCP로 확인했다. 별도 QA bundle에서 새 엔진을 검증하고 사용자 창의 진행·탐색 상태를 보존한다. 전체 TSAN/release·native MCP·GUI codec 선택·Universal/signature/CLI는 코드 안정 뒤 순차 검증한다.

## 통합 회귀 중간 기록

전체 Swift202개(성능 전용1skip)/0실패, Python8/0실패 후, cursor reset-before-detached-start 및 terminal shutdown fence와 SNS drive capacity 독립 byte 검사를 추가했다. ThreadSanitizer209개(성능 전용1skip)/0실패. 로그는 `integration-tests-final.log`, `tsan-final-v2.log`, `python-tests-final.log`에 보존하며 이후 소스 변경의 최종검사와 구분한다.

[기존116단계 historical 검사](FINAL_OPTIMIZATION_HISTORICAL_VALIDATION.md)는 현재 소스를 과거 hash로 덮어쓰지 않고 frozen packaged archive/ZIP/signature에 대해 PASS했다. 새 Core41파일/49계약/통합284REA기록의 traceability 검사는 PASS했으나 Windows 실행 동등성 증명은 아니다.

## 새 엔진 실제 QA 관측

[현재 CLI 전체 scan](validation/r-backlog-2026-11-09/live-volume-current/summary.json): frozen binary779cfd108b6d…로 파일6,146,640·폴더839,769, allocated448,750,915,584B, logical431,748,826,746B, 약208초. capacity499,898,105,856B, OS used451,893,460,992B(종료 직후). .Trashes/.TemporaryItems/.Spotlight-V100/.DocumentRevisions-V100의 접근불가4건을 보존했다. peak footprint4,352,843,696B, maxRSS3,919,167,488B다. 전 실행과 파일수·용량·호스트 압축 상태가 달라 개선율로 계산하지 않는다. 출력SNS734,043,998B와SHA는 archive receipt에 보존한다.

별도 QA bundle에서 [SNS/config MCP161요청](validation/r-backlog-2026-11-09/qa-native/codec-config-v2/report.json)과 [subtree cursor48요청](validation/r-backlog-2026-11-09/qa-native/query-cursor/results.json)이 PASS했다. multi-root inspect는 revision을 바꾸지 않으며 선택누락/다른root손상/encoding누락은 기존창을 보존한다. configured export exactLF bytes·output cap 실패cleanup·무관옵션거부·기본report24파일을 확인했다. cursor는24경로일치·소비후재사용거부·8개bound·explicit cancel·revision reset을 확인했다.

[네이티브 UI](validation/r-backlog-2026-11-09/qa-native/ui-observation.json)에서 두루트 이름/용량과 선택대화상자, v2코드페이지선택후café.txt 표시를 직접확인했다. 이는 독립합성fixture 어댑터검사이며 실제Windows파일왕복의대체가아니다.

## 대형 snapshot 수명

[약699만 노드 native load/release](validation/r-backlog-2026-11-09/qa-native/large-snapshot-v2/report.json)가 PASS했다. 저장된 drive raw capacity와 leaf 기반 displayed448,750,915,584B를 분리했고 bounded cursor 생성/취소 뒤25노드 fixture로 교체했다. 이 실행은 load+projection+query+release 전체 약148초의 관측이다. decode 단독 시간으로 쓰지 않는다. 교체 후 Mach footprint137,218,328B를 관측했으며 전체 heap 즉시반환이나 모든 메모리 회귀 부재를 보장하지 않는다. 이 QA는 이후 validation bitset·DU 연결·입력 취소 변경 전 frozen binary이므로 최종 새 패키지검사와 구분한다.

## 최종 소스의 통합 결과

[release 전체 검사](validation/r-backlog-2026-11-09/release-tests-final.log): 244개, 성능 전용1skip, 실패0. source는 [동결 manifest](validation/r-backlog-2026-11-09/final-source/manifest.json)의 구현/테스트와 hash가 같다. [TSAN244개/1skip/0실패](validation/r-backlog-2026-11-09/tsan-final-v4.log)는 일부 후속 helper/LocalizedError 수정 전 시점이며, 추가 targeted 재실행은 [macOS dylib policy 차단](validation/r-backlog-2026-11-09/validation-bitset-tsan-final.log)으로 테스트를 시작하지 못했다. 보안 정책을 바꾸지 않았고 새 실행의 성공으로 기록하지 않는다.

최종 QA source에서 [SNS/DU/config1201요청](validation/r-backlog-2026-11-09/qa-final/codec-config/report.json), [cursor48요청](validation/r-backlog-2026-11-09/qa-final/query-cursor/results.json), [20도구/61RPC](validation/r-backlog-2026-11-09/qa-final/mcp-integration/results.json)을 검증했다. 원본 DU의 CRLF를 Swift Character로 잘못 나누던 초기 회귀는 수정했고 이전 실패 로그를 유지했다. 실제 Windows 파일 비교는 아니다.

[대형 import 취소](validation/r-backlog-2026-11-09/qa-final/import-cancel-v2/report.json): 모델 할당이 관측된 실제 SNS 읽기에 새 작은 scan을 시작하자 취소+새 scan 완료 약1.38초. 이전 대형 결과는 새3파일/6byte scan을 덮지 않았다. 처음128MiB 증가를 기다리던 harness는30초 내 threshold 미도달로 실패했고, 원래 실행을 취소·정리한 뒤16MiB 실제 할당 확인으로 새 실행했다. 원시 실패를 제품 취소 실패나 성공으로 바꾸지 않는다.

[validation bitset](VALIDATION_BITSET_FINDINGS.md)은2,012개 frozen oracle와 동시취소 입력3종을 확인했다. 25만노드5쌍의 peakRSS93.0→70.3MB는 반복관측, 실제709만노드1쌍 검증15.07→11.57초는 단일관측이다. 실제 대형 RSS는 decode/압축 high-water가 섞여 개선을 입증하지 못했다. [DU](DU_SNAPSHOT_READER_FINDINGS.md), [focus owner lifecycle](R06_FOCUS_LIFECYCLE_IMPLEMENTATION.md)도 strict subset/직렬경계를 명시한다.

## 패키지와 남은 범위

[watch 반복](validation/r-backlog-2026-11-09/qa-final/watch-soak/report.json):180.66초·198회차·22,176쓰기/rename/delete, 매회 정확 파일/byte 합계·이슈0·감시중지 PASS. 종료 후 root1/subscriber1/active0/queued0, footprint153.5→146.0MB 표본. 이는48폴더의 bounded 반복이며 수시간·실제 대형 트리 watch/강제 OS overflow 보장은 아니다.

[Universal release](validation/r-backlog-2026-11-09/package.json)는 arm64+x86_64 빌드와 codesign verify를 통과했다. QA 창을 닫고 [배포 앱 PID10144의 idle/MCP 상태](validation/r-backlog-2026-11-09/main-ready.json)를 확인했다. 이전 사용자 scan이 실행 중일 때 덮어쓰지 않았고, 최종 교체 시 기본 bundle 실행 인스턴스가 없음을 확인했다. Intel slice 실행은 하지 않았다.

**전체 R01~R15 완료는 아니다.** 기존 Windows VM/PC가 없어 R01~R04 및 Windows 실제 SNS/DU/옵션/동시성/locale 대조가 남는다. R05는 작은 focus 이득과 root 회귀가 함께 있어 production 미채택이다. R06의 owner 수명은 연결했지만 독립 병렬 master/focus worker·watch 공정성 완전성은 미완료다. UI 설정 적용/사용자 class palette와 전체 Windows locale 재현도 codec/명시적 export 지원과 구분한다. path 압축·계층 hit-test·lookup hint·완전한 FILE stream reader는 profile 후 미채택/추후 조건으로 남겼다. STDIO disconnect/notification 선점 취소도 지원하지 않는다. 완료한 하위 단위만 TODO에서 체크한다.

MCP 새 입력을 쓰려면 새 패키지의 bridge를 사용하고 기존 클라이언트의 도구 목록을 새로 연결한다. 기존20개 도구 이름은 유지하며 typed settings·선택 template 원문·subtree cursor·SNS/DU 루트/encoding·용량 회계를 추가했다. API 명세와 catalogue의 소스 hash를 갱신했다.
