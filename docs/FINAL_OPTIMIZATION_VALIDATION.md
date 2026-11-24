# 최적화 최종 통합 검증 기록

**이번 실행 완료:** 처음 남았던 59개를 모두 검증해 실행 TODO는 116/116이다. native Space/부분·완전 가림 matrix를 포함한다. 아래 제약과 별도 R01~R15 Windows 동적 비교 backlog를 전체 기능 동등성 완료로 혼동하지 않는다.

원본은 Windows SpaceSniffer 2.2.0.27 x64, EXE SHA-256 `192176a0ff46d84d27885e9d38e60157bc692eaf5d1e5b75ca56b3beaa0de7a6`이다. 원본 의미는 기존 REA ledger와 [engine 계약](engine-contracts.json), [30개 대응 감사](OPTIMIZATION_CHECKLIST.md)를 따른다. opaque UUID·COW·Dispatch·AppKit cache/visibility는 Mac 구조에 맞춘 선택이다. 원본에 Swift 구조나 아래 개선율이 있었다는 주장이 아니다.

## 입력·재현·판정 경계

- 시작 시 Sources/Tests/Package를 [before manifest](validation/final-optimization-2026-11-09/before-manifest.json)와 `before/`에 고정했다. 과거 단계의 source/archive/ZIP/raw 수치는 바꾸지 않았다. LegacyTreemap·LegacyNavigationState·LegacyMapCanvas는 그 소스에서 이름/접근 범위/import만 조정한 reference다. 변환 스크립트는 `dist/final-optimization-2026-11-09/make-references.py`다.
- [fixture manifest](validation/final-optimization-2026-11-09/fixtures/manifest.json): fixed seed small/wide/deep/balanced/edges metadata와 SNS hash를 분리한다. 큰 입력은 최대 25만 파일이다. 실제 파일시스템 fixture는 수십 파일/별도 두 root 등 작게 제한하며 사용자 develop 전체를 실험 입력으로 쓰지 않았다. hard-link alias·symlink cycle·숨김 조상·0/1024/1025 경계·Unicode·긴 이름은 TestSupport/ReferenceContractTests에 있다. Windows SNS 경로는 Windows 파일을 Mac 경로로 해석하지 않는 기존 golden/vector 검사다.
- [최종 kernel 150개 표본](validation/final-optimization-2026-11-09/paired-final/report.json)은 case별 fresh process 5쌍, 순서를 번갈아 실행했다. RSS/CPU는 process 전체, seconds는 지정 stage다. fixture 생성·full oracle·frozen reader 유지 비용은 scope를 명시하고 시간 밖에 둔 경우가 있다. 5개 process 값으로 UI p95를 주장하지 않는다.
- [호스트 상태](validation/final-optimization-2026-11-09/host-pressure.json): 24 GiB RAM, swap 여유 0, 시스템 볼륨이 0~200 MiB까지 감소했다. background 작업을 종료하거나 OS 설정을 바꾸지 않았다. 작은 차이는 noise/초기화/환경 변동과 구별하며 전체 앱 배율·모든 디스크의 최고 성능·전체 RAM ceiling으로 일반화하지 않는다.

## 채택한 변경과 비용

[변경 matrix와 수명 계약](OPTIMIZATION_INVALIDATION.md)에 parse/membership/weights/navigation/sort/geometry/paint 경계와 fallback을 정리했다.

| 책임 | 구현 | 범위·상한 |
|---|---|---|
| 탐색 | 작은 추적 경로 cache + 계층 lookup, moveHistory 전체 firstIndex 제거 | 4096 paths/UTF8 추정 1 MiB; 실패·rename는 기존 복구 |
| projection | tag 비의존 같은 COW storage 재사용, parsed filter 재사용, opaque baseline/result에 묶인 sparse delta | 시간·filter/mode/hidden·unknown metadata/topology·dense는 full; 공개 revision과 metadata는 새 값 |
| 정렬/rect | GeometrySession과 별도 child-order cache | 정렬 65536 ID/value 슬롯·128 parent; rect 최근 두 key 합계 50000 tile; snapshot 미보유 |
| text/표시 | 현재 label/size/width와 4개 font/style 조합 재사용 | 4096 entries/추정 UTF8 1 MiB; 값·정확한 UTF8 name·font 변경 시 재생성 |
| 숨김/닫기 | geometry 취소·최신 intent 복귀, timer/중간 presentation 정리, async capture 준비, weak/generation observer | 데이터 scan/projection 계속; Store.shutdown에서 projectionSource/cache도 제거 |
| I/O | metadata PathIO / scan admission / artifact / metrics 각각 native Dispatch lane | scan8+pending64, path/artifact 각 serial+pending64, metrics outstanding33; 전 프로세스 thread ceiling 아님 |
| 재사용 | private ancestor scratch만 production 사용 | owner 1 MiB, idle process charge 4 MiB/최소 owner charge64 KiB; pressure/epoch/cooldown/oversize eviction |
| 계측 | monotonic duration·queue·terminal·active·thread sample 분리 | stage128, 최근 duration256/thread ID32; snapshot을 읽은 reader와 COW 격리 |

## Kernel 전후 측정

모두 release source probe다. 탐색은 조회/복구 20회, geometry는 20회, delta는 12회, pool은 8세대다. 아래 ms는 해당 묶음 중앙값이며 UI 한 번의 반응 시간이 아니다.

| 시나리오 | baseline ms | current ms | 해석 |
|---|---:|---:|---|
| navigation-default | 737.732 | 0.466 | 25만 파일, 작은 추적 경로 조회; initial evaluation·paint 제외 |
| geometry-alternating | 126.765 | 11.104 | 같은 weights, 두 bounds 반복; rect 재사용 |
| geometry-resize | 102.126 | 54.965 | bounds 매번 변경; 정렬만 재사용 가능 |
| geometry-branch | 0.741 | 0.226 | 같은 focus branch·정확한 bounds key의 subtree rect 재사용 |
| delta-sparse | 336.781 | 5.881 | 같은 ID/topology의 leaf size 경계 변경 |
| delta-independent | 327.242 | 14.101 | 독립 branch 네 곳 |
| delta-branch | 324.634 | 7.128 | 같은 branch 16개 leaf |
| delta-dense | 338.911 | 332.066 | 전체 변경; full fallback |
| delta-rename | 444.843 | 483.804 | ID 유지 in-place rename 모델; proof 뒤 full fallback 비용 포함 |

rename 모델은 current가 느린 표본도 있다. 바뀐 page의 노드 필드를 검증한 뒤 full로 내려가는 비용과 호스트 변동을 포함한다. production의 실제 rename은 SnapshotTree의 stable topology 조건을 깨면 새 table로 재구성되어 빠른 page-count fallback을 사용한다. 모든 rename이 빨라졌다고 주장하지 않는다. dense fallback은 full 비용을 그대로 남긴다. sparse도 flat membership/weights 첫 변경에 COW가 생겨 O(dirty)라고 표현하지 않는다.

### Pool 결정

| 후보 | 8세대 ms | peak RSS 중앙값 MiB | 결정 |
|---|---:|---:|---|
| fresh | 101.002 | 109.33 | 대조군 |
| current | 68.644 | 117.27 | 기존 NodeTable + private scratch 유지 |
| pages | 109.726 | 146.95 | 미채택: adapter/copy 및 reader 보유 비용이 이득 상쇄 |
| nodes | 134.083 | 134.42 | 미채택: 객체·adapter·busy 보유 비용 증가 |

page/node prototype는 Test target/probe에만 있다. 실제 malloc_size 또는 page capacity charge로 4 MiB를 제한하고 reader가 있으면 unique-reference 검사에서 제외한다. reset은 전체 DiskNode/children/string 상태를 교체한다. frozen reader 2세대·writer·evict 검사, reader가 없을 때 실제 reuse hit 검사와 값을 대조했다. charge는 deep heap/RSS cap이 아니다. 기존 값 타입 NodeTable에 객체 pool이 있다고 가정하지 않았다.

[allocation raw 8종](validation/final-optimization-2026-11-09/allocations-final/report.json)은 first/repeat/add/delete/rename/filter를 별도 stack으로 구분한다. 첫 조사에서 WMO가 같은 scan wrapper를 한 함수로 합친 표본은 제외하고 고유 post-call marker로 재측정했다. node page·문자열·children/stack·membership/weights·budget bookkeeping으로 나누되 stack 우선 분류이고 모든 deep allocation의 정확한 type accounting은 아니다. 작은 2000-node cold scratch 표본은 전역 budget 초기화/보관 비용 때문에 allocation 감소를 보이지 않았다. 이전 scratch 단계의 이득과 이번 25k/40-pass CPU·RSS 결과를 구별한다.

25만 Int64 배열 한 원소를 바꾸는 COW probe는 old/new live buffer가 다르고 old sum이 유지됨을 확인했다. 두 array payload는 각각 2,000,000 bytes다. [raw](validation/final-optimization-2026-11-09/allocations-final/cow-current.txt.gz)의 실제 ALLOC와 payload를 혼동하지 않는다. 이는 flat weights의 작은 변경도 전체 배열 복사를 만들 수 있다는 근거다.

변경 항목 재삽입은 별도 실험했다. sparse/16개 변경은 제한적 이득이 있었지만 dense에서는 크게 악화됐다. production에는 같은 weights 정렬 재사용을 채택했고, 전체 변경 provenance와 end-to-end 이득이 입증되지 않은 재삽입은 보류했다. 부모 rect가 달라진 branch layout을 이전 rect로 재사용하지 않는다.

## AppKit render와 계측

[전체 render 표본](validation/final-optimization-2026-11-09/render-dense-final.json)은 200개 label·선택 윤곽을 바꾸며 각 renderer 1250 frames(5쌍×250), 800×600 bitmap 생성·copy를 똑같이 포함한다. preserved LegacyMapCanvas와 pixel oracle도 일치했다. 실제 compositor FPS가 아니다.

| renderer | frames | p50 ms | p95 ms |
|---|---:|---:|---:|
| legacy | 1250 | 21.741 | 37.906 |
| current | 1250 | 19.630 | 32.520 |

4-item 표본의 시간 차이는 작아 일반적인 FPS 개선으로 보고하지 않는다. 초기 dense 표본에는 비교 앱 초기화가 겹쳤으므로 보존하고 최종 표와 분리했다.

[warm draw allocation](validation/final-optimization-2026-11-09/render-allocations-warm/report.json)은 sampledPixels stack 안의 20회씩만 집계한다. 첫 font 초기화·10 warmup·pixel oracle 및 MallocStackLogging 내부는 제외한다. 첫 cold font 비용이 current에 몰렸던 표본과 크게 긴 최초 trace는 보존하되 채택 근거로 쓰지 않았다. 이 계측 시간은 성능 비교 시간이 아니다.

| renderer | draw ALLOC calls | draw 누적 bytes |
|---|---:|---:|
| legacy | 17256 | 8,954,036 |
| current | 17085 | 8,848,160 |

계측 observe 10만 회×5 process의 호출당 비용은 0.143~0.206 µs였다. 매번 recent array를 local copy하는 COW를 dictionary inout 갱신으로 없앴다. immutable 진단 snapshot과 동시 writer 4000회도 대조했다. 중첩 stage duration을 합해 wall time으로 사용하지 않는다.

## 동시성·reader·종료 검증

- [122개 TSAN](validation/final-optimization-2026-11-09/final-v2-tsan.log): failure0/race warning0, 별도 release performance case만 skip1. [release122](validation/final-optimization-2026-11-09/release-v2-tests.log)는 performance case를 포함해 failure0였다. 후속 [reader/motion 2개](validation/final-optimization-2026-11-09/reader-motion-final.log)를 더했고 최종 전체 재검사는 별도 로그로 기록한다.
- 실제 native scan worker 8개를 gate에서 대기시킨 채 8개 waiting thread ID와 OS thread count를 관측하고 filter/geometry/metrics가 응답함을 확인했다. native running slot은 종료 전 반환하지 않는다. admission 1000 submit과 LatestWorker pending1000 교체/즉시 capture 해제, running old root 완료 뒤 재생성 entry 보호를 검사했다.
- UI MapTransition·QueryContext 20회·대기 export·실제 ScanService running baseline을 동시에 유지하고 writer rename/cancel/unsubscribe를 겹쳤다. 이전 nodes/weights/SNS bytes가 유지되고 roots0·IO/admission active0로 정리됐다. 단순 값 타입 선언만을 반납 증거로 쓰지 않았다.
- scoped rescan은 새 scanning scope를 gate로 관측한 뒤 final revision 증가와 새 파일·full scan 합계를 확인했다. 기존 smoke의 settled helper만으로 새 cycle 완료를 증명하지 않았다.
- Store.shutdown은 snapshot뿐 아니라 projectionSource/cache/geometrySource도 비운다. 기존 query reader는 그대로 읽힌다. 늦은 load/projection/monitor callback은 generation에서 거절한다. 이전 단계의 실제 FSEvents arena weak 해제와 stale monitor 검증도 유지한다.

## 실제 앱·MCP·패키지

[실제 STDIO MCP](validation/final-optimization-2026-11-09/mcp-final/results.json)는 20개 도구, 61요청을 통과했다. 실제 2파일/3,145,728 bytes, 탐색 up/back/root, tag toggle, filter/mode/depth, revision pagination, SNS/TXT job·기존 출력 거부, PNG, scan admission 진단을 확인했다. 기존 필드는 보존하고 thread/queue/duration/scratch/canvas/window 진단을 추가했다.

검사용 외부 volume 경로의 한 scan이 opendir 커널 호출에서 대기했다. [sample](validation/final-optimization-2026-11-09/scan-stall-sample.txt)과 [상태](validation/final-optimization-2026-11-09/scan-stall-status.json)를 남겼다. 그때 MainActor/MCP는 계속 응답했다. 원인은 이 sample만으로 권한/디스크 결함이라고 단정하지 않는다. 독립 QA PID를 정상 종료하고 내부 임시 경로에서 통과했다. `/private/tmp`→`/tmp` 정규화는 API가 보고한 root를 사용하도록 smoke를 수정했다.

전후 실제 window 비교를 위해 [neutral baseline](validation/final-optimization-2026-11-09/instrumented-baseline.json)을 만들었다. frozen engine 파일은 모두 동일하며 App의 두 파일에 scalar 진단·window size/state 제어·async geometry-ready capture만 추가했다. 렌더링/정렬/계산/수명 최적화는 추가하지 않았다. foreground가 가려진 최초 시도는 제외했다.

첫 v2 패키지(이후 수명 보완 전): Universal x86_64 arm64, strict ad-hoc signature, packaged MCP 동일성, arm64 및 Rosetta x86_64 CLI의 SNS/TXT 바이트 일치를 확인했다. Rosetta는 실제 Intel 하드웨어 검사가 아니다. ZIP SHA-256 `6f378df3ee77797e7fafa35d72b243fa98eff710e4cec148821eb30cdd736870`, 버전 보관본 `dist/releases/final-optimization-2026-11-09-6f378df3ee77.zip`.

## 판정 경계

이 문서는 원본 30개 기법 전체 구현/Windows 동적 동등성/모든 volume 성능 상한을 인증하지 않는다. R01–R15 backlog는 실행 명세 116개와 별도다. 각 acceptance evidence가 존재할 때만 TODO와 progress JSON에 체크하며, GUI 환경 문제를 통과로 바꾸지 않는다.

## 실제 창 성능·숨김 수명 후속 검증

[실제 앱 전후 집계](validation/final-optimization-2026-11-09/app-comparison.json)는 5회 교차 쌍, 각 버전 이동 200회와 resize 200회다. 모든 채택 표본은 시작/종료 `window_occluded=false`를 확인했다. 이동은 Bridge/IPC부터 projection publish까지, resize는 최신 geometry 준비와 AppKit PNG 생성·encoding까지 포함한다. compositor FPS 측정이 아니다.

| 실제 창 시나리오 | baseline p50/p95 ms | current p50/p95 ms |
|---|---:|---:|
| 25만 파일 이동 | 213.227 / 365.543 | 137.810 / 235.515 |
| resize + 최신 PNG | 73.588 / 93.563 | 64.568 / 81.104 |

초기 load 시간과 before/after RSS·CPU·worker 표본은 원시 report에 별도로 있다. 위 측정 뒤 hidden-window 수명과 frame 진단을 보완했다. 측정 당시 Core/renderer source와 최종 Core/renderer는 같고, App 전체 source hash가 같다는 주장은 하지 않는다. `paired-final/source-archive`, `delivery-source-archive`, `release-source-archive`, `packaged-source-archive`를 서로 덮어쓰지 않고 보존했다.

[표시·숨김·최소화](validation/final-optimization-2026-11-09/app-visible-hidden-minimized/report.json)는 각각 geometry-only 변경 20회를 관측했다. normal은 모두 unoccluded, hidden/minimized는 모두 occluded였다. 숨김·최소화의 timer/text cache는 0이다. [별도 관측](validation/final-optimization-2026-11-09/app-current-state-observations/report.json)의 normal은 실제로 완전히 가려져 있었으므로 표시 상태 측정으로 쓰지 않았다. [CPU 비교 시도](validation/final-optimization-2026-11-09/visibility-cpu.json)와 small 변형은 `all_occluded=false`여서 완전 가림의 baseline/current 효과 근거로 사용하지 않는다. CPU 차이는 이 짧은 관측 범위로 제한하며 새로운 paint scheduler나 전역 polling을 추가하지 않았다.

단일 창을 숨기는 과정에서 `ContentView.onDisappear`가 shutdown/unregister를 호출해 앱이 정상 종료되는 문제를 발견했다. [AppKit 정상 종료 로그](validation/final-optimization-2026-11-09/hidden-exit-app.log)를 보존했다. 실제 willClose에서만 shutdown하고, ExplicitWindowRetention이 hidden window/model 및 automatic termination 억제를 균형 있게 소유하도록 수정했다. [실제 단일 창 검증](validation/final-optimization-2026-11-09/hidden-smoke/events.json)에서 hidden 상태 20회 생존·데이터 변경·stale revision·PNG 후 재정리·normal lease 해제·minimize/restore를 확인했다. 마지막 native close 후 [controller 인스턴스 없음](validation/final-optimization-2026-11-09/hidden-qa-after-close.json)도 확인했다.

[네이티브 더블 클릭](validation/final-optimization-2026-11-09/native-double-click.json)에서 폴더 focus가 실제 하위 경로로 바뀌었고 상위 폴더 버튼으로 복귀했다. native AX 항목 활성화로 선택한 항목 상세가 변경됐다. label/frame/activation·전환 중 hit target·hover 등록·snapshot ID 재배치와 실제 변경 rect의 Reduce Motion 분기는 Swift 회귀와 함께 확인했다. VoiceOver 음성 낭독을 수동으로 들었다는 의미는 아니다.

[다중 창](validation/final-optimization-2026-11-09/multiwindow/events.json)은 같은 root의 2 subscribers/1 cache, 서로 다른 root의 2 subscribers/2 caches, 한 창 close 후 1 subscriber/1 cache를 확인했다. [마지막 창 close](validation/final-optimization-2026-11-09/multiwindow/last-close.json) 후 앱 인스턴스는 0이다. 이 시도의 외장 volume 저장 두 작업은 kernel `open`에서 대기했으며 완료로 판정하지 않았다. [stack](validation/final-optimization-2026-11-09/multiwindow/after-close-sample.txt)에서 artifact native lane만 대기하고 UI/MCP는 응답했다. 원인이나 즉시 syscall 취소를 보장하지 않는다.

내부 임시 경로의 [25회 native 수명 반복](validation/final-optimization-2026-11-09/lifetime-cycles.json)은 매회 실제 scan/query/SNS 저장/offline load/hide/show를 끝냈다. 매회 roots/subscribers/active/queued scan=0, 숨김 timer/text=0을 확인했다. 첫 5회를 warmup으로 제외한 RSS는 약 102.4→103.8 MiB, physical footprint는 약 109.5→110.1 MiB 범위였다. 짧은 반복에서 유한한 보유량을 관측한 것이며 장시간 전체 메모리 누수 부재나 전체 RAM cap의 증명은 아니다. 실제 8-worker gate·frozen query/export/transition·취소·늦은 완료·weak release는 통합 회귀가 보완한다.

[최종 패키지 source 126개 TSAN](validation/final-optimization-2026-11-09/packaged-126-tsan.log)은 실패 0/경쟁 경고 0, [release 126개](validation/final-optimization-2026-11-09/packaged-126-release.log)도 실패 0이다. 두 실행은 opt-in 성능 case 1개를 skip하며 해당 case의 별도 2500 frames 측정은 위에 있다. [Python protocol 6개](validation/final-optimization-2026-11-09/final-python-tests.log)와 [정식 bundle의 실제 MCP 20도구](validation/final-optimization-2026-11-09/main-mcp/results.json)도 통과했다.

패키지의 최신 값은 [package.json](validation/final-optimization-2026-11-09/package.json)을 따른다. 이전 package JSON/ZIP은 각 `package-before-*.json` 및 버전 ZIP에 보존했다. CLI의 첫 교차 검사에서 directory access time이 scan 사이 바뀌어 SNS timestamp bytes가 달랐다. [실패 로그](validation/final-optimization-2026-11-09/final-package-check.log)를 보존하고, 모든 scan 직전 fixture atime/mtime을 고정한 [재검사](validation/final-optimization-2026-11-09/package-frame-check.log)에서 native arm64/Rosetta의 SNS/TXT 바이트 일치를 확인했다. 결과를 맞추기 위해 파일 내용을 사후 수정하지 않았다.

## B06.01 native matrix 완료

[부분 가림](validation/final-optimization-2026-11-09/two-window-partial.json)은 같은 앱에서 실제 생성한 두 창의 native frame 교차 면적 525,546 / 746,720 points²와 target `occluded=false/on_active_space=true`를 확인했다. [완전 가림](validation/final-optimization-2026-11-09/two-window-full.json)은 앞 창을 키워 target frame 전체를 덮고 `occluded=true/on_active_space=true`를 확인했다. 각각 depth-only 변경 20회이며, target을 전면 활성화하지 않고 측정했다. 완전 가림에서는 geometry deferred가 20회 늘고 layout/timer/text 생성은 없었다. 짧은 CPU 합계는 부분 가림 약 0.323초 / 완전 가림 약 0.319초로 noise 수준이므로 유의한 CPU 감소율은 주장하지 않는다. 기존 AppKit scheduling에 별도의 paint scheduler를 더하지 않았다.

[다른 Space](validation/final-optimization-2026-11-09/other-space/report.json)는 실제 `on_active_space=false`에서 geometry dirty 20회, 필터 publish와 query, 최신 PNG 생성 후 cache 재정리를 확인했다. 숨김 presentation의 timer/text=0이며, PNG를 만든 뒤에도 다른 Space에 남았다. 최초 단축키/도구 접근 실패와 `space-switch-attempt.json`은 보존했다. [복귀](validation/final-optimization-2026-11-09/visibility-return.json)에서는 최신 filter/depth를 반영해 PNG를 준비하고 text cache가 다시 생성됨을 확인했다. 창 분리/close의 geometry 취소·observer/tooltip/AX/cache 정리는 native 다중 창과 detach/weak 회귀가 확인한다.

현재 패키지 ZIP SHA-256은 `3f4e09f3932e0caaec0691b1ebdb2bfbc96aa6a7e65da721ca9872b956c8a94e`다. [최종 evidence 검사](validation/final-optimization-2026-11-09/final-evidence-check.json)는 보존 source/raw/ZIP hash, 150 kernel checksum, 2500 renderer frames, 각 버전 native 이동·resize 200회, 25회 수명 반복, native visibility matrix와 116개 체크의 정합성을 검사한다. 실행: `python3 scripts/check-final-optimization-validation.py --require-complete`.
