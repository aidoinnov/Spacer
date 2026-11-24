현재 마감·후속 작업: [작업 인수인계](docs/WORK_HANDOFF.md) · [설치파일·배포 준비](docs/RELEASE_PREPARATION.md). 검증된 184B 엔진을 패키징하며 168B 후보는 미배포입니다.

추가 검증: [성능 채택 조건·종료 지연 재검사](docs/PERFORMANCE_EXIT_RECHECK_RESULTS.md).

최신 검증: [실제 OS 입력·취소 역할 수정·양쪽 설치](docs/GPUI_OS_INPUT_RESULTS.md).

# Mac Space Sniffer

현재 제품 UI는 **Mac/Windows 공통 Rust/GPUI 0.3.0**이며 기존 Swift 스캔·문서 엔진을 재사용합니다. Mac 설치본과 Windows 132 PC의 바로가기·실행 검증: [최신 결과](docs/GPUI_COMPLETION_RESULTS.md). **2026-11-24 콘솔/감시 갱신 후속 수정:** [원인·검증·최신 설치본](docs/GPUI_BACKGROUND_RESULTS.md). **재검사 계약·장시간 검수·최신 disktree 메모리 비교:** [후속 결과](docs/GPUI_REMAINING_RESULTS.md). **공통 노드 메모리 개선 개발 후보(미배포):** [184→168B·검증과 gate](docs/NODE_STORAGE_RESULTS.md). **양쪽 실제 파일·100만 SNS 메모리·종료 검증:** [후속 정량 결과·미완료 조건](docs/BOTH_PLATFORM_FINISH_RESULTS.md). **최신 UI 패치 설치·실행:** [Quick Look 충돌 재현/수정·접근성 초점·184B 엔진 유지](docs/GPUI_PREVIEW_REENTRY_RESULTS.md). 아래 날짜별 기록은 이전 단계 이력입니다.

2026-11-23 Windows 앱: [실제 Windows v0.1 실행·검증 결과](docs/WINDOWS_APP_RESULTS.md).132번 사용자 데스크톱에 설치·실행하고 네이티브/전략 debug·release 각7개와 UI17흐름을 검증했습니다. Win32 reader·공통 worker·native UI를 연결했고 플랫폼 차이는 포트/어댑터·전략·조립 지점으로 분리했습니다. Mac 전체 기능 동등성과 성능 채택은 별도 범위입니다.

2026-11-23 Windows 실기기: [132번 PC의 공통 엔진1단계 검증](docs/WINDOWS_132_PHASE1_RESULTS.md). Windows10 x64에서 debug/release 각22개 통과, 실제9,605파일·worker1/2/4·취소·명시적 재검사를 확인했습니다. Mac 기능+공통 엔진 이식성1단계는 종료 가능하며, Windows 전체 앱과 Mac 성능·배포 gate는 별도 후속입니다.

2026-11-23 성능 재개: [비교 probe 재구축·동일 바이너리 A/A 절차·환경 진입 결과](docs/SCAN_PERFORMANCE_2026_11_23.md). GUI 검증 소스는 유지됐고, 환경 검사 실패로 정식 A/A·표준 성능 판정과 기본 배포는 HOLD입니다.

2026-11-21 최종 채택 검증: [환경 진입·GUI 검증과 추가 watch 수정](docs/SCAN_FINAL_GATE_RESULTS.md). native 삭제 이벤트의 `/private` alias 누락을 수정하고 관련31개·TSAN7개,20만 파일 GUI·60초 watch 반복·ARM/Intel 호환성을 검증했습니다. 안정된 환경의 성능 gate와 기본 배포는 계속 HOLD입니다.

2026-11-21 재검토 수정: [취소·경로 동등성·ENTRYCOUNT 계측 수정 결과](docs/SCAN_REVIEW_FIX_RESULTS.md). 회귀·TSAN·ARM/Intel 검증을 완료했습니다. 정책 실험에서 조회 감소의 p95 개선은 입증되지 않아 기본4후보/64기회를 유지합니다. 성능 채택·GUI 검증·배포는 HOLD이며 설치0.2.1은 유지합니다.

2026-11-21 최신 개발 소스 **V5 후보·미배포**: [다섯 개선 결과](docs/SCAN_ALL_FIVE_RESULTS.md), [채택 TODO](docs/SCAN_ALL_FIVE_TODO.md). bounded 재표본·worker metadata·node/path 저장·독립 census·scratch 재사용을 반영했습니다. 최종 표준7입력 중6개 통과, tiny-folder p95와 A/A 수집 신뢰도는 HOLD입니다. 설치0.2.1은 유지합니다.

2026-11-21 C3 재확인(이전 단계): [C3 대 disktree 실측·남은 개선점](docs/DISKTREE_RECHECK_RESULTS.md), [우선순위 TODO](docs/DISKTREE_RECHECK_TODO.md). 513회 비교+warmup84회에서 속도/메모리 격차를 재확인했고, 첫 sibling에 따라 worker 수락이0/198로 달라지는 admission 맹점을 확인했습니다. 재확인 단계에서는 production 동작·설치 앱을 변경하지 않았습니다.
2026-11-21 C3: [공통 엔진 품질 재검토](docs/SCAN_ENGINE_QUALITY.md). 취소 결과 전달 전 종료·실패 시 무제한 계획 탐색을 재현·수정하고 producer API·permit 수명·종료 계약을 강화했습니다. 검증 기록과 미완료 플랫폼/배포 항목을 구분합니다. 기존 설치 앱은 유지합니다.

2026-11-21 플랫폼 후속: [공통 엔진·OS 어댑터 설계와 검증](docs/SCAN_PLATFORM_ARCHITECTURE.md). worker·지속 공급 window·취소·예산·합산/발행 정책을 독립 패키지로 분리하고 Mac 어댑터에서 사용합니다. Windows native reader·실행 검증은 미완료입니다. 동일 바이너리 A/A에서도 기존 성능 기준이 미달하는 수집 조건을 확인해 기본 배포는 계속 보류합니다.

2026-11-21 후속 **개발 소스 후보·미배포**: [지속 공급 read-ahead 실험](docs/CONTINUOUS_READ_AHEAD_RESULTS.md). 분기 입력에서 약24% 개선했지만 일부 p95 기준 미달로 기본 배포는 보류했습니다. 현재 작업 소스는 rolling 후보이며 일반 build 스크립트는 이 후보를 패키징합니다. 검증된 설치0.2.1 앱은 변경하지 않았습니다.

2026-11-21: [disktree 도입 성과](docs/DISKTREE_ADOPTION_RESULTS.md). 2,079회 비교의 정확성·latency·CPU·RSS 기준을 통과했고 10만 파일 중앙값 약23%, 기존 bulk 상한 초과 입력 약35% 단축을 확인했습니다. 숫자 identity·제자리 순열·합산 batch·read-ahead cadence를 적용하고 GUI·ARM/Intel을 검증했습니다. 0.2.1 설치 및 현재 실행본 구분은 성과표의 설치 기록을 확인하세요. 기존 실행 중인 root 스캔은 보존하며 새 버전은 다음 실행부터 적용합니다. 경쟁 엔진 격차와 남은 과제는 계속 공개합니다.

2026-11-20 완료: [최종 성과표](docs/SCAN_DELIVERY_RESULTS.md). 기본 병렬도2·64 sibling 진입 조건, bounded snapshot 개요 소비·50ms 활성화·native draw 계측을 적용했다. 7입력×51쌍×3변형=1071회에서 지연/CPU/RSS/정확성 gate를 기준선과 직렬 양쪽으로 통과했다. 전체294개(1skip), TSAN34개 실패0. 최종 GUI20회 개요 draw 확인 p95 299ms,20만 파일 상세 재검사1.01초·취소·rename 감시·빈 root 교체를 검증했다. ARM/Intel CLI와 SNS/TXT, 실제 nested-volume GUI도 통과했다. Universal0.2.0/20261120.1을 기본 앱에 설치·서명 검증·실행했고 이전 앱/ZIP은 dist/releases에 백업했다. 전체 실제1TB 완료 시간 보장은 아니며, 현재 선택 볼륨 검사와 관측 개요를 사용한다.

Windows SpaceSniffer 2.2.0.27의 정적 분석 근거를 기준으로 macOS에 옮기는 독립 네이티브 구현입니다. Uderzo Software의 공식 Mac 배포판은 아닙니다. 제품 UI는 Rust/GPUI이며 기존 Swift 엔진과 OS 어댑터를 재사용합니다. SwiftUI/AppKit 구현은 참조·회귀 검증용으로 남겨둡니다.

**기준: UI 표현과 macOS API 대체를 제외한 동작은 원본 근거에 연결합니다. 아직 확인하지 못한 기능을 임의 동작으로 채우지 않습니다.**

2026-11-09 최적화 후속: [실제 전후 측정·수명·패키지 검증](docs/FINAL_OPTIMIZATION_VALIDATION.md), [입력별 무효화 계약](docs/OPTIMIZATION_INVALIDATION.md), [실행 체크](TODO.md). 이번 실행 체크 116/116과 native Space/부분·완전 가림 검증을 마쳤습니다. 원본 Windows 동적 동등성 R01~R15는 별도입니다.

2026-11-19 V01 소스 후보: 권한 거부·경로 소멸은 즉시 기록하고, 지정한 일시적 open 오류만 최대 3회 재시도합니다. 기존 무조건 10회 대기를 제거한 Mac 정책입니다. 접근 오류가 있는 결과는 계속 불완전 상태로 표시합니다. 기본 실행본 채택은 정상 입력 latency CI 경계 때문에 보류했습니다. [성과표](docs/SCAN_SPEED_RESULTS.md), [실행 TODO](docs/SCAN_SPEED_TODO.md).

2026-11-19 V02 소스 후보: local APFS의 16개 이상 폴더에 정렬을 보존하는 batch metadata 조회를 적용했습니다. V02 단독 8개 성능 셀 통과, Swift269개(1 skip)·TSAN44개 실패0입니다. 이전 앱 대비 소형 입력 p95의 엄격 기준이 남아 기본 배포본은 유지합니다. [성과표](docs/SCAN_BULK_RESULTS.md), [Universal 후보 앱](<dist/Mac Space Sniffer V02 Candidate.app>). 아래 build 명령은 현재 후보 소스를 기본 앱 경로에 패키징하므로 검증된 기존 배포본 보존 여부를 확인하세요.

2026-11-19 V00 소스 후보: 선택 볼륨 기본 검사, 다른 볼륨 포함 옵션(GUI/CLI/MCP), System/Data 별칭 처리와 범위별 캐시·watch·부분 재검사를 구현했습니다. 최종 Swift280개(1 skip) 실패0, 실제 중첩 볼륨·ARM/Intel·모드 전환·변경 감시를 검증했습니다. 기본 모드의 동일-input 기준은 통과했고, optional allVolumes의 1만 파일 p95 기준은 보류입니다. [성과표](docs/SCAN_SCOPE_RESULTS.md), [후보 앱](<dist/Mac Space Sniffer Scope Candidate.app>). 기존 앱 실행 중에는 `open -n 'dist/Mac Space Sniffer Scope Candidate.app'`으로 별도 실행할 수 있습니다. 기본 배포본과 기존 검사 프로세스는 유지했습니다.

2026-11-19 V03 실험 소스: 단일 builder의 결과 순서를 보존하는 제한된 폴더 read-ahead를 구현했습니다. 2800회 동일-input 비교에서 1만 파일 분기 입력 p50은48.65→28.96ms로 줄었지만 small/wide/deep 회귀로 기본 적용은 보류합니다. 현재 public concurrency는1이고 기존 앱·Scope 후보는 교체하지 않았습니다. 전체289개(1 skip), TSAN29개, 판정 도구6개 실패0. [성과표](docs/SCAN_PARALLEL_RESULTS.md), [소유권·예산 설계](docs/SCAN_PARALLEL_DESIGN.md). V03 GUI/watch·패키징과 V04 경량 개요는 별도 미완료입니다.

## 실행

```sh
./scripts/build-gpui-app.sh
open 'dist/Mac Space Sniffer GPUI.app'
```

현재 GPUI Mac 배포 검증은 Apple Silicon/arm64, macOS 14 이상입니다. Xcode/Swift와 Rust 1.97이 필요합니다. 빌드 결과는 `dist/gpui-builds`에 새 경로로 생성하고 GPUI latest alias를 갱신합니다. Windows는 VS x64 Developer PowerShell에서 `scripts/build-gpui-app.ps1`을 사용합니다. [빌드·패키징 설명](gpui-app/README.md). Mac ad-hoc 서명, Windows unsigned이며 Developer ID/공증/Authenticode는 별도입니다. 기존 `scripts/build-app.sh --universal`은 SwiftUI 참조 UI·기존 CLI용이며 GPUI 제품 빌드가 아닙니다.

## 탐색

폴더 또는 볼륨을 선택하거나 창에 드래그하면 스캔합니다. 초기 상세 깊이 3은 원본 `initialDetailLevel` 기본값입니다.

- **단일 클릭:** GPUI에서는 폴더 내부로 진입하고 파일은 선택합니다. 원래 스캔은 유지합니다.
- **더블 클릭:** 첫 클릭에서 선택한 폴더를 화면 전체로 확대합니다. 파일을 더블 클릭하면 파일의 부모 폴더로 확대합니다. 파일 실행은 우클릭 메뉴의 별도 작업입니다.
- `⌘[` / `⌘]` 또는 Backspace / Shift+Backspace로 이전·다음 위치를 탐색합니다.
- `⌘R`은 전체 재스캔, `⇧⌘R`은 현재 위치 재스캔입니다. 원본의 전체 스캔과 포커스 스캔 동시 실행은 아직 구현하지 않았습니다.
- 태그는 항목당 색 하나입니다. 같은 색을 다시 지정하면 해제합니다. 1=빨강, 2=노랑, 3=초록, 4=파랑입니다. 필터는 조상의 태그를 OR로 상속하지만 화면에는 항목 자신의 태그만 표시합니다.
- 트리맵에서 1~4는 마우스 아래 항목의 태그, 0은 현재 위치 아래의 모든 태그 해제입니다.

단일 클릭/확대는 `pnlGraphMouseDown`, `pnlGraphDblClick`, `refreshBitmap`, `TTreeMapNode::layout`에서 확인한 동작입니다.

## 원본 필터 문법

```text
*.zip;*.dmg                       ZIP 또는 DMG
*.jpg;*.png;>100kb                JPG/PNG 중 디스크 사용량 100 KiB 이상
logicalsize>1gb                  논리 크기 1 GiB 이상
>30d                            수정 후 30일 이상
<1m                             수정 후 1분 이하
<6months                        수정 후 6개월 이하
\node_modules                   경로에 해당 폴더가 포함된 파일
|*.tmp                          TMP 제외
:tag:red+green-b                 빨강/초록 포함, 파랑 제외
:class:Video/Movies              원본 기본 동영상 클래스
:attr:hidden                    숨김 속성
```

외부 구분자는 `;`입니다. 파일명 마스크는 OR, 제외 마스크는 AND, 크기·기간 등 다른 범주는 각각 결합합니다. `,`는 일반 파일명 OR 구분자가 아닙니다. `m`은 분이고 월은 `month`/`months`입니다. 표시 기호가 `>`/`<`여도 바이너리의 비교는 경계값을 포함합니다. 크기·기간 숫자는 정수만 지원합니다. 크기 단위는 원본처럼 1 KB = 1,024 B입니다.

기본 파일 클래스는 원본의 Video/Movies, Executables/System files, Archives/Disk images, Pictures/Images, Audio/Music을 사용합니다. 사용자가 수정한 Windows XML 설정과 전체 export scripting은 미구현입니다.

## 저장

- **스냅샷:** 원본 SNS v4 바이너리 형식으로 현재 위치와 필터 결과를 저장합니다. UTF-16LE Base64 이름, little-endian 숫자 필드, 노드 종료 레코드를 사용합니다. JSON 파일에 확장자만 붙인 형식이 아닙니다.
- **텍스트 내보내기:** 원본 `Simple file list` 기본 설정을 따릅니다. 파일 경로만 UTF-8/CRLF로 기록하고, 각 폴더에서 파일 우선·크기 내림차순으로 순회합니다. 임의 CSV 프리셋은 제거했습니다.
- 스냅샷은 오프라인으로 열리며 실제 파일 작업을 하지 않습니다. Windows 경로는 Mac 로컬 경로로 바꾸지 않고 보존합니다.

SNS v1/v3/v4 단일 루트 읽기를 구현했습니다. SNS v2의 legacy encoding, 한 파일의 복수 최상위 루트, SNF 형식은 아직 미구현이며 다른 형식으로 추정해서 읽지 않습니다. Windows 원본이 생성한 파일 및 Mac이 쓴 파일을 Windows 원본에서 읽는 동적 왕복 검증은 아직 하지 않았습니다.

## 집계와 플랫폼 차이

원본처럼 경로별 파일 크기를 상위 폴더에 합산합니다. 하드 링크 경로를 임의로 합치지 않으며, 폴더 자체의 메타데이터 블록을 파일 합계에 추가하지 않습니다. 심볼릭 링크는 원본의 reparse-point 제외에 대응해 순회에서 제외합니다.

Windows 파일 API는 macOS `lstat`/FSEvents/NSWorkspace로 대체합니다. Mac 디스크 사용량은 `st_blocks * 512`, 논리 크기는 `st_size`를 사용합니다. 이 합계는 APFS 공유 블록·스냅샷·purgeable 공간의 회수 가능 용량이 아닙니다. 접근 오류가 있는 경로는 계속 스캔하고, UI에는 상세 기록을 최대 500개 표시합니다.

동일한 루트를 여러 뷰가 공유하고 마지막 구독이 닫히면 스캔과 감시를 정리합니다. 필터·집계·트리맵 기하 계산·스냅샷과 보고서 I/O는 메인 UI와 분리합니다. Swift actor/mailbox는 원본 스레드/락의 플랫폼 대체이며 원본 자료구조와 동일하다고 주장하지 않습니다.

## 근거와 검증

```sh
python3 scripts/check-engine-evidence.py
swift test
swift test --sanitize=thread
'dist/Mac Space Sniffer.app/Contents/MacOS/MacSpaceSniffer' --cli --scan /path/to/folder --output /tmp/scan.sns
'dist/Mac Space Sniffer.app/Contents/MacOS/MacSpaceSniffer' --cli --load /tmp/scan.sns --filter '*.zip;*.dmg' --output /tmp/files.txt
```

[분석·차이 기록](docs/ENGINE_REVERSE_ENGINEERING.md), [계약표](docs/engine-contracts.json), [전체 REA 근거](docs/engine-rea-evidence.json), [검증 결과](docs/VALIDATION.md).

공식 Windows ZIP과 동봉 문서는 `References/Windows`에 로컬 보관하며 Mac 앱에 포함하지 않습니다. 재다운로드는 `./scripts/fetch-windows-reference.sh`로 수행합니다. 이 구현의 검증 범위는 위 계약표이며 Windows 원본과의 전체 동등성을 의미하지 않습니다.


레이아웃 변경 시 500ms 애니메이션을 적용했습니다. 곡선은 원본 확대·축소 함수에서 확인했으며, 일반 재배치에 적용하는 부분은 UI 구현 선택입니다. 확장 폴더 헤더에도 용량이 표시됩니다. 확대 후에는 툴바의 **상위 폴더** 또는 **⌘↑**로 부모로 이동합니다. 스캔 시작 루트에서는 해당 버튼이 비활성화됩니다.

변경 대기 경로는 원본처럼 중복·조상 범위를 합치고 독립 분기를 각각 처리합니다. 삭제·필터 제외 시 가까운 부모로 이동하고 방문 기록을 정리하며, 식별 가능한 rename은 확대·선택·방문 기록을 유지합니다. [캐시·탐색 추가 근거](docs/CACHE_AND_REPAINT_FINDINGS.md)를 참고하세요.

큰 snapshot은 페이지를 공유하고 수정된 페이지만 복사합니다. 탐색 경로의 전체 dictionary와 subtree 병합의 전체 노드 dictionary를 제거했습니다. [수정 전후 메모리 검증](docs/MEMORY_VALIDATION.md)을 참고하세요.

필터는 반복 조상 탐색과 불필요한 정규식 처리를 줄였으며, 구조가 같은 파일 변경은 노드 ID를 유지하며 변경 값과 상위 합계만 갱신합니다. [추가 속도·리소스 비교](docs/RESOURCE_OPTIMIZATION.md)에 동일 입력의 전후 측정과 범위를 기록했습니다.


MCP로 실행 중인 앱을 제어하고 정보를 조회할 수 있습니다. 스캔·상위 이동·필터·태그·파일 메타데이터·큰 항목·진행/오류·프로세스 자원·SNS/TXT·앱 화면 캡처를 20개 도구로 제공합니다. [연결과 호출 방법](docs/MCP.md), [MCP 기술 설계](docs/MCP_TECHNICAL_DESIGN.md), [API 상세 명세](docs/MCP_API_REFERENCE.md).


추가 최적화 후보와 metadata 측정: [조사 결과](docs/OPTIMIZATION_AUDIT.md). 탐색 재계산·이벤트 큐·paint·MCP scope·export의 남은 비용과 적용 전 검증 조건을 기록했습니다.


Windows 바이너리에서 직접 확인한 [최적화 기법 20개](docs/WINDOWS_OPTIMIZATIONS.md)는 함수 주소·REA Evidence ID·원문과 함께 별도로 정리했습니다. Mac 구현 제안과 원본에서 관찰한 기법을 구분합니다.


최신 원본 최적화 목록과 Mac 적용 여부: [30개 체크리스트·누락 감사](docs/OPTIMIZATION_CHECKLIST.md). 최초 20개에서 누락된 10개를 보강했으며, 대응 구현·부분 대응·미적용·플랫폼 대체를 구별합니다.


실제 적용 우선순위는 [Mac 실익 기준 최적화 추림](docs/BENEFICIAL_OPTIMIZATIONS.md)에 있습니다. 원본 30개 중 현재 비용을 줄일 우선 5개·후속 2개·조건부 1개 작업으로 묶고, 시스템 차이로 보류한 이유도 기록했습니다.

구체적인 실행 순서·체크 항목·채택 기준은 [최적화 TODO](TODO.md)에 있습니다. 노드/page/scratch 풀과 blocking I/O worker·동시성 제한을 E01/E02 선행 평가로 포함하고, 이전 기록은 [보관본](TODO_HISTORY_2026-11-08.md)에 보존했습니다.

단일 책임 모듈화는 [모듈 설계](docs/OPTIMIZATION_MODULE_DESIGN.md)와 TODO A00에서 추적합니다. 계산·실행 정책·snapshot 저장·출력 형식·파일 전송·표시·접근성의 책임과 수명을 분리하며, 설계 완료와 실제 추출 완료를 구분합니다.

2026-11-09: [ProjectionSession 1차 구현·검증](docs/PROJECTION_SESSION_VALIDATION.md). 계산/실행 책임을 분리하고 same-input 탐색 재사용·복합 view 요청 축소를 적용했습니다. pool/executor와 나머지 모듈 추출은 진행 TODO로 남아 있습니다.

2026-11-09 후속: [스캔 실행기·private scratch 검증](docs/SCAN_RESOURCE_VALIDATION.md). active8/queued64 admission, queued/running 취소 분리, 실제 membership allocation 감소와 Swift68/Python6/실제 MCP101요청을 확인했습니다. 전체 node/page pool과 ArtifactWorker I/O 분리는 남아 있습니다.

2026-11-09 artifact 후속: [SNS/TXT streaming·I/O 검증](docs/ARTIFACT_STREAMING_VALIDATION.md). output 바이트를 유지하며 whole export peak RSS를 줄이고 파일 작업을 serial I/O queue로 옮겼습니다. write/close/게시 실패와 exclusive 경합·고정 입력을 검증했습니다.


2026-11-09 이벤트 큐 후속: 대량 독립 경로에 한해 압축 경로 인덱스와 FIFO 저장소를 사용한다. 배열 oracle 대조·COW/해제·전후 시간과 메모리의 교환관계는 [검증 기록](docs/REFRESH_QUEUE_VALIDATION.md)에 남겼다. B08.01–08 검증 범위 완료. [후속 검증](docs/REFRESH_LIFECYCLE_VALIDATION.md)에서 실제 폭주 중 취소·오래된 callback 차단·큐 저장소 weak 해제를 확인했다.


2026-11-09 B05 AX 부분: 최대 500개 접근성 요소를 path 기준으로 재사용하고 후보 순회를 조기 중단한다. [AppKit 구성 요소 측정과 범위](docs/ACCESSIBILITY_CACHE_VALIDATION.md). 전체 text/font/tooltip/full-frame 최적화 완료는 아니다.


2026-11-09 B05 tooltip 후속: 같은 presentation의 hover redraw에서 native tooltip 재등록을 생략한다. 이동 중 rect·stale callback·metadata는 현재 값으로 검증한다. [구성 요소 측정/한계](docs/TOOLTIP_REGISTRY_VALIDATION.md). text/font/full-frame·VoiceOver 종합 검증은 별도다.
