# SpaceSniffer 리버싱 기반 Mac 이식 TODO

최신 최적화 점검은 [30개 통합 체크리스트](docs/OPTIMIZATION_CHECKLIST.md)를 기준으로 합니다. 대응 구현 6 / 부분 대응 6 / 핵심 미적용 11 / 플랫폼 대체 6 / 적용 검토 1입니다. 아래 과거 작업의 `[x]`에는 조사·문서·이전 검증 완료도 포함되므로 전체 Mac 최적화 구현 완료로 읽지 않습니다.

기준: Windows SpaceSniffer 2.2.0.27 x64. **UI와 플랫폼 차이를 제외한 동작은 원본 근거를 확보한 뒤 이식한다.**

`[x]`는 현재 근거 확보·구현 또는 명시한 검사를 완료했다는 뜻이다. Windows 원본과의 전체 동등성을 뜻하지 않는다. 이미 반영된 항목도 남겨두고, 미완료 하위 항목을 이어서 처리한다.

## 작업 방식

- [x] 공식 Windows 배포물 확보 및 EXE SHA-256 고정.
- [x] Ghidra 정적 분석 결과 107개를 원본 해시·주소·Evidence ID와 함께 보관.
- [x] 구현 계약표와 근거 연결 검사 구성: core 16파일, 계약 23개.
- [ ] 새로 확인하는 동작마다 호출자·피호출자·설정값·예외 경로까지 추적하고 근거를 추가한다.
- [ ] 동작별 입력 → 상태 변경 → 출력 계약을 먼저 기록하고 Swift 구현에 연결한다.
- [ ] 변경할 때마다 계약표, 테스트, 분석 기록의 미구현 목록을 함께 갱신한다.

## P0 — 애니메이션과 캐시 확인

### 애니메이션

- [x] `zoomFromTo` (`0x42bb40`)의 확대·축소 보간과 비트맵 사용 확인.
- [x] 기본 시간 500ms와 곡선 `1 - ((cos(t × 3.1415) + 1) / 2)^2` 확인.
- [x] 확인한 곡선을 Mac 확대·레이아웃 전환 UI에 적용.
- [x] 전환 중 재배치가 오면 현재 표시 위치에서 이어지도록 처리.
- [x] 폴더 헤더 용량 표시와 상위 폴더 버튼·⌘↑ 반영 및 UI 확인.
- [x] DynaSmooth 갱신 주기와 변경 노드 색상 강조를 위치 보간과 구분해 기록.
- [ ] **원본 일반 재배치에서도 사각형 좌표가 보간되는지 판정한다.**
  - `setCoords` (`0x468320`), 자식 배치 (`0x468360`), `refreshBitmap` (`0x4295a0`), repaint timer (`0x42c760`)의 호출 흐름을 연결한다.
  - 이전 좌표·새 좌표 저장소, 중간 비트맵, 타이머별 변환이 있는지 역추적한다.
  - 원본에서 스캔 진행·파일 크기 변경·필터 변경·단일 클릭·더블 클릭을 각각 녹화해 구분한다.
  - 결과가 확인될 때까지 Mac 일반 재배치 애니메이션은 UI 구현 선택으로 유지한다.

### 캐시

- [x] `TDataCache::getRootData` (`0x43ec60`): 루트 경로·agent GUID 기준 트리 공유 확인.
- [x] `releaseNode` (`0x43f230`): 마지막 참조 해제 시 스캔·감시 정리 확인.
- [x] Mac에서 같은 루트의 중복 스캔 방지, 구독 수명, 태그 공유 반영 및 테스트.
- [x] 원본 노드 색상 포인터 캐시와 재귀 무효화 (`0x469770`, `0x46bb00`) 확인.
- [x] 원본 확대·축소 비트맵 캐시 확인. Mac 표시 항목·문자열·색상 캐시 반영.
- [x] 원본 캐시 함수 내부의 정확한 문자열 비교·agent GUID·부모/자식 루트 분리 확인. Mac 정규화 루트 공유·독립 하위 루트 테스트.
- [ ] Windows 실행에서 경로 대소문자·끝 구분자·호출자 정규화에 따른 cache hit/miss를 대조한다.
- [x] 재스캔·필터·태그·감시·설정 변경의 확인된 재사용/갱신 경로를 표로 기록. 설정 변경의 색상 캐시 reset은 vtable 슬롯까지 대조.
- [x] 마지막 감시 구독 해제 시 상태 broadcast 누락 수정. 중지된 감시의 늦은 이벤트는 세대 검사로 차단.
- [x] TDataCache 생성·조회·참조 해제·소멸 경로에서 자동 디스크 저장/복원 호출을 찾지 못했음을 기록.
- [ ] 영구 디스크 캐시 존재 여부를 종료·재시작 파일 I/O 실험으로 확인한다.
  - 현재 확인된 것은 메모리 캐시다. SNS 수동 저장·열기와 자동 캐시를 구분한다.
  - 영구 캐시가 확인되지 않으면 임의로 엔진 기능에 추가하지 않는다.

## P1 — 스캔·감시·워커의 남은 차이

### 스캔과 집계

- [x] 파일 경로별 크기를 조상에 합산하고 하드 링크를 임의로 dedup하지 않도록 수정.
- [x] 폴더 자체 메타데이터 블록 가산 제거, reparse/symlink 순회 제외 반영.
- [x] 디렉터리 열기 총 10회, 재시도 간 10ms 반영.
- [x] 논리 크기와 할당 크기 분리. macOS 할당량은 `st_blocks × 512`로 대응.
- [ ] 접근 거부·스캔 중 삭제·취소 시 부분 결과 및 완료 상태를 원본과 대조한다.
- [ ] 오래 걸리는 전체 재스캔에서 진행 중 부분 snapshot 교체가 focus/history를 너무 일찍 정리하는지 검사하고 원본의 기존 트리 유지와 대조한다.
- [ ] 원본 free/unknown/missing 노드의 생성·갱신·집계 규칙을 추적하고 Mac 적용 범위를 정한다.

### 워커와 갱신

- [x] 스캔·필터·기하 계산·파일 I/O를 메인 UI에서 분리.
- [x] 오래된 필터 중단 후 새 입력 실행 계약 반영. Swift mailbox 구조는 플랫폼 대체로 명시.
- [x] FSEvents 전용 큐, 변경 범위 재검사·병합 및 실제 파일 생성 감지 테스트.
- [x] rename 시 태그 유지: FSEvents에서는 유일한 새 inode 경로만 연결.
- [ ] `scanFocused` (`0x430270`)와 master scan의 동시 실행·취소·병합 순서를 추적한다.
- [ ] 확인한 계약대로 전체 스캔 중 focused scan을 지원하고 공유 트리 일관성을 검사한다.
- [x] `addRefilterRequest`·`getRefilterRequest`·`isOnPathTo`를 연결해 중복·조상 packing과 독립 분기 FIFO 확인. Mac 변경 범위 큐에 적용.
- [ ] 원본 focus-first 부분 필터 갱신을 projection worker에 이식한다. 현재는 전체 projection 재계산이며 filesystem 범위 큐와 구분한다.
- [ ] `elementChange` (`0x406d30`)의 추가·수정·삭제·rename별 delta와 부모 합계 변경을 대조한다.
- [ ] 현재 부모 범위 재검사 방식이 원본과 다른 결과를 만드는 경우를 찾고 수정한다.
- [ ] 감시 overflow·이벤트 폭주·재스캔 중 변경의 복구 규칙을 원본 근거로 보강한다.

## P1 — 탐색·필터·태그 대조

- [x] 초기 상세 깊이 3, 단일 클릭 상세화, 더블 클릭 확대 및 첫 클릭 표적 유지 반영.
- [x] 파일 더블 클릭은 부모 확대. 임의 자동 실행 제거.
- [x] 외부 `;`, 긍정 파일명 OR·제외 AND, 경계 포함 크기·기간, 정수 단위 반영.
- [x] 퍼지 접두사·폴더 조상 조건·생성/접근/수정 시간·기본 클래스·속성 조건 반영.
- [x] 태그 색 비트, 자신의 단일 태그 토글, 조상 OR, 포함 OR·제외 우선 반영.
- [ ] 빈 토큰·잘못된 문법·반복 조건·Unicode·대소문자 경계를 원본 실행 결과와 대조한다.
- [ ] 확대·뒤로·앞으로·상위 이동 후 선택과 상세 깊이 복원 규칙을 대조한다.
- [x] 원본 `treeMapNodeRemoved`와 `updateFiltering`을 근거로 필터 제외·삭제 시 focus/selection/history 정리 반영 및 테스트.
- [x] rename 시 동일 식별자의 유일한 새 경로로 focus/selection/history 유지. 기존 하드 링크 별칭으로 임의 이동하지 않음.
- [x] 최종 QA 앱에서 실제 FSEvents rename 뒤 확대 유지, 필터 제외·폴더 제거 뒤 가까운 부모 이동, 필터 해제 뒤 위치 유지 확인.
- [ ] Windows 실행에서 필터 제외·삭제·rename의 탐색 상태와 태그 결과를 최종 대조한다.

## P2 — 스냅샷·설정·내보내기

- [x] SNS v4 바이너리 쓰기, v1/v3/v4 단일 루트 읽기 구현.
- [x] UTF16LE Base64·LE 정수·FILETIME·노드 종료 `01 00` 반영.
- [x] 독립 구성 golden bytes, 잘못된 길이·잘린 레코드·Windows 경로 보존 테스트.
- [x] 원본 Simple file list: 경로만, files-first·size-desc, UTF8/CRLF 반영.
- [x] 임의 CSV 프리셋과 JSON 스냅샷 대체 제거.
- [ ] SNS v2 legacy encoding 분기를 리버싱하고 실제 원본 fixture로 검증한다.
- [ ] 한 SNS 파일의 복수 최상위 루트 읽기·쓰기 규칙을 구현한다.
- [ ] SNF text snapshot 문법·escaping·오류 처리 규칙을 추적해 구현한다.
- [ ] Windows XML 설정 중 엔진 동작에 영향을 주는 값을 기본값·범위와 함께 정리한다.
- [ ] 사용자 수정 파일 클래스와 export scripting의 문법·평가·정렬·encoding을 순서대로 이식한다.

## P0/P3 — 원본 실행 비교와 완료 판정

- [x] 현재 Swift 테스트 44개와 ThreadSanitizer 검사 통과.
- [x] Universal arm64/x86_64 빌드, 서명 검사, arm64 SNS 저장·Rosetta SNS 읽기/TXT 출력 확인.
- [ ] 원본 Windows 실행 환경을 확보한다. 현재 정적 분석만으로 동등성 완료 처리하지 않는다.
- [ ] Windows/Mac 양쪽에 동일한 이름·내용·트리의 fixture를 만들고 플랫폼별 속성 차이를 별도 기록한다.
- [ ] 먼저 P0의 애니메이션·캐시 시나리오를 관찰해 남은 가설을 판정한다.
- [ ] 파일별 논리 크기·폴더 합계·필터 결과·태그·탐색 상태를 비교한다. 할당량 차이는 OS 차이를 구분한다.
- [ ] Windows 생성 SNS → Mac 읽기, Mac 생성 SNS → Windows 읽기 양방향 검증.
- [ ] 변경·rename·삭제·취소·재시작 시나리오를 반복하고 불일치마다 근거와 수정 기록을 남긴다.
- [ ] 대규모 트리에서 스캔 중 UI 반응, 메모리, 캐시 재사용·해제, 취소 지연을 측정한다.
- [ ] 완료 항목마다 원본 근거 + Mac 코드 + 검증 결과를 연결한다. 미확인 항목은 미확인으로 남긴다.

## 근거 파일

- [분석 및 차이 기록](docs/ENGINE_REVERSE_ENGINEERING.md)
- [구현 계약표](docs/engine-contracts.json)
- [원본 REA 근거](docs/engine-rea-evidence.json)
- [현재 검증 결과](docs/VALIDATION.md)

추가 근거와 이번 반영 상세: [캐시·다시 그리기 분석](docs/CACHE_AND_REPAINT_FINDINGS.md). Windows 동적 비교는 등록된 VM 부재로 미완료다.


## P0 — 대규모 스캔 정체 후속

- [x] 실행 앱 sample로 배열 복사·전체 집계·필터 재계산 병목 확인.
- [x] 원본 deltaSize에 따른 조상 합계 증분 갱신으로 변경.
- [x] 가벼운 진행 상태와 큰 트리 발행을 분리하고 동일 tree revision 재필터 방지.
- [x] hot loop URL 생성 제거, POSIX opendir/readdir 열거 적용.
- [x] 현재 경로·대기 폴더·일부 결과·시스템 사용량·오류가 있는 종료 상태를 UI에 표시하고 QA 확인.
- [x] 200만 진행 후보의 선형 발행량, delta 합계, 취소 회귀 검사 포함 34개 ThreadSanitizer 통과.
- [ ] 수정 빌드로 develop 전체 스캔을 완료하고 폴더별 합계·접근 오류·시스템 사용량 차이를 대조한다.
- [x] 대규모 projection·snapshot·subtree 병합의 메모리 비교와 불필요한 전체 dictionary 제거. 페이지 저장·완료 작업 해제 반영.
- [x] 실제 앱에서 25만 파일 합성 SNS 로드·탐색과 메모리 관측.
- [ ] 전체 develop filesystem scan과 장시간 반복 변경의 최대 메모리·해제를 추가 관측한다.

상세: [스캔 성능 조사](docs/SCAN_PERFORMANCE.md).

메모리 수정 및 재현 결과: [MEMORY_VALIDATION.md](docs/MEMORY_VALIDATION.md).


## 추가 속도·리소스 최적화

- [x] 필터의 반복 문자열 정리·범위 dictionary 순회 제거.
- [x] ICU 결과를 유지하는 ASCII literal/suffix 경로와 조상 조건 사전 계산·1byte context 적용.
- [x] 추적 경로 검색의 조기 종료와 계층 경로 조회 적용.
- [x] 구조가 같은 변경은 ID를 유지하며 변경 페이지·조상 delta만 반영. 구조 변경 fallback 유지.
- [x] 재검사 시간 표시에서 대기 시간을 제외하도록 시작 시각 수정.
- [x] 최종 44개 ThreadSanitizer, 전후 교차 측정, 실제 필터 상태의 FSEvents 크기 변경 검증.
- [x] navigation-only membership/weight 재사용 후보 검토·25만 파일 합성 측정. 구현 완료는 아님.
- [ ] same-input navigation 재사용 구현과 시간 필터·0바이트·삭제/rename 회귀 검증.
- [ ] 대량 변경 이벤트의 prefix packing을 FIFO/조상 계약을 유지하는 인덱스로 최적화.

상세와 측정 한계: [RESOURCE_OPTIMIZATION.md](docs/RESOURCE_OPTIMIZATION.md).


## MCP — 요청한 플랫폼 연동

- [x] 실제 앱 상태/worker와 연결하는 사용자 전용 Unix socket + STDIO MCP bridge.
- [x] 스캔·탐색·필터·태그·SNS/TXT·진행/오류·자원·화면 캡처 20개 도구.
- [x] 페이지/검사 예산·revision 보호·비동기 artifact 상태·기존 파일 덮어쓰기 방지.
- [x] Codex 서버 등록 및 정식 앱의 상태/자원 조회 확인.
- [x] Swift ThreadSanitizer 51개, Python 6개, 별도 실제 QA 앱 99회 MCP 호출 통과.
- [x] Universal 빌드·서명 및 캡처 이미지 확인. [사용법/범위](docs/MCP.md), [결과](docs/validation/mcp-integration.json).

- [x] MCP 기술 설계서·20개 도구 API 상세 명세·입력 스키마 카탈로그 작성. 상태/오류/수명/스레드/보안/운영/검증 한계와 재시도 예제 포함.
- [x] 문서 JSON 예시 34개·도구 입력 예시 20개·로컬 링크 31개·상태 필드 38개 정합성 확인.


## 마지막 추가 최적화 조사 — 2026-11-08

- [x] 현재 core/UI/MCP 경로 점검, metadata probe 8개 시나리오 × 3회 실행.
- [x] 탐색 10회 전체 projection/재사용 실험 비교, 독립 이벤트 1,000/2,000/4,000개 삽입·drain 측정.
- [x] 동일 target 파일 10개에서 scope 밖 노드 수에 따른 MCP largest 비용 측정.
- [x] export의 중복 membership과 전체 문자열/Data 생성, paint의 매 프레임 tooltip/AX 재구성 확인.
- [ ] paint에서 tooltip·접근성 element 재사용과 lazy 500개 제한 적용 전 frame/할당 계측.
- [ ] MCP largest의 subtree 순회, query cursor 호환성·budget/cancellation 설계.
- [ ] TXT/SNS streaming 및 단일 membership 재사용 설계·바이트 동등성 검증.
- [ ] view_set 동일 값/복합 변경의 중복 submit 계측 후 합치기.
- [ ] selection/resize의 형제 geometry/정렬 캐시를 면적·선택 계약을 유지하며 검토.

우선순위·소스 위치·원본 계약·수치/한계·재현: [OPTIMIZATION_AUDIT.md](docs/OPTIMIZATION_AUDIT.md). 이번에는 배포 앱과 Sources를 변경하지 않았다.


## Windows 원본 최적화 근거 재조사 — 2026-11-08

- [x] 동일 EXE hash를 확인하고 기존 107개 + 새 32개 REA 기록으로 20개 기법 추출.
- [x] 함수 53개의 읽기 쉬운 원문·주소·전체 Evidence ID와 payload hash 보관.
- [x] 탐색 재사용·focus-first skip·조상 delta·형제 국소 정렬·변경 의존성 필터·태그 context 확인.
- [x] repaint 병합/가시성/간격·layout/paint 분리·palette/text/tooltip 캐시·노드 재활용 pool 확인.
- [x] bounded thread pool과 event wait 확인. maxConcurrency data 기본값 1을 관찰했으며 다중 병렬 실행을 가정하지 않음.
- [x] LARGE_FETCH 열거 분기·segment path 저장·파일 sink SNS/TXT 순차 출력·zoom bitmap 분기 확인.
- [x] 이전 Mac 후보 7개를 원본 직접 대응/의미 계약 대응/Mac 별도 구현으로 재분류. trie/hash 큐 근거 없음 명시.
- [x] EXE·bundle·Evidence target/authority·원문 payload 일치 검사 추가.
- [ ] Windows 실행에서 실제 옵션·동시성·CPU/RSS·성능을 비교한다.
- [ ] 확인한 원본 기법을 Mac에 적용할 때 별도 구현과 회귀/바이트/UI 검증을 수행한다.

상세: [WINDOWS_OPTIMIZATIONS.md](docs/WINDOWS_OPTIMIZATIONS.md), [구조화 근거](docs/windows-optimization-findings.json). 이번 작업은 원본 조사이며 Mac 엔진 적용 완료가 아니다.


## 원본 최적화 통합 목록 — 누락 감사 후 30개

아래 `[x]`는 현재 대응 코드가 있는 항목이며 Windows 동적 동등성·전체 성능 완료가 아닙니다. 부분·미적용·플랫폼 대체·적용 검토는 원본 기법 그대로 완료한 것으로 체크하지 않습니다. 세부 근거·소스·미완료 하위 항목은 [통합 문서](docs/OPTIMIZATION_CHECKLIST.md)를 따릅니다.

- [x] W01 루트 데이터·리스너 공유 캐시 — 대응 구현
- [ ] W02 탐색 시 기존 필터 트리 재사용 — 핵심 미적용
- [ ] W03 focus 우선 필터 후 중복 subtree 제외 — 핵심 미적용
- [ ] W04 조상 delta 누적 — 부분 대응
- [ ] W05 기존 형제 정렬의 변경 항목 재배치 — 핵심 미적용
- [ ] W06 변경 의존성에 따른 재필터 제한 — 핵심 미적용
- [x] W07 상속 태그 context의 재귀 전달 — 대응 구현
- [x] W08 오래된 필터 작업 취소·교체 — 대응 구현
- [x] W09 변경 요청 중복·조상 packing과 FIFO — 대응 구현
- [ ] W10 repaint 병합·간격 조절·가려진 창 생략 — 핵심 미적용
- [ ] W11 layout/paint 분리와 표시 재귀 제한 — 부분 대응
- [x] W12 palette 포인터 캐시와 명시적 무효화 — 대응 구현
- [ ] W13 문자열 치수 memoization — 부분 대응
- [ ] W14 지속 tooltip 객체와 dirty rebuild — 핵심 미적용
- [ ] W15 노드 재활용 pool과 busy 참조 제외 — 플랫폼 대체
- [ ] W16 상한 있는 스캔 스레드 pool·event 대기 — 플랫폼 대체
- [ ] W17 OS 디렉터리 열거의 큰 버퍼 경로 — 플랫폼 대체
- [ ] W18 경로 segment 저장·필요 시 full path 조합 — 핵심 미적용
- [ ] W19 파일 stream에 순차 export — 핵심 미적용
- [ ] W20 확대 bitmap 재사용과 옵션별 재렌더 — 부분 대응
- [ ] W21 기존 filtered TM 노드 보존·차이만 생성/제거 — 핵심 미적용 / 이번 누락 보강
- [ ] W22 감시 buffer/event 재사용·batch 직접 변경 — 부분 대응 / 이번 누락 보강
- [ ] W23 열거 metadata 재사용·조건부 추가 size query — 플랫폼 대체 / 이번 누락 보강
- [x] W24 필터 조건 사전 분류·숫자 변환·빠른 조건 판정 — 대응 구현 / 이번 누락 보강
- [ ] W25 사각형·가시성으로 계층형 hit-test 가지치기 — 핵심 미적용 / 이번 누락 보강
- [ ] W26 동일 FS 노드의 중복 스캔 진입 방지 — 플랫폼 대체 / 이번 누락 보강
- [ ] W27 설정 객체 lazy 생성·메모리 재사용 — 적용 검토 / 이번 누락 보강
- [ ] W28 SNS 입력의 record 단위 stream 읽기 — 플랫폼 대체 / 이번 누락 보강
- [ ] W29 자식 이름 조회의 hint 주변 양방향 검색 — 핵심 미적용 / 이번 누락 보강
- [ ] W30 전체 스캔과 별도 focus 재스캔 worker 경로 — 부분 대응 / 이번 누락 보강

- [x] 최초 20개와 Mac 코드 30개 항목 전부 대조.
- [x] 최초 미참조 pseudocode 55개에 처리 상태 부여: 추가 기법 직접 근거 19 / 기법 보강 24 / 동작·형식 11 / 미해결 1.
- [x] 추가 함수/심벌 조회 6개 보관, EXE/두 bundle/원문/source anchor/ID·집계·링크 검사 통과.
- [ ] Q01~Q05: 바이너리 전체 미분석 경로·Windows runtime·일반 재배치/영구 캐시·filter ID/metadata flags·DU/SNF agent 미해결 추적.

원본 바이너리 전체의 누락 0건이라고 단정하지 않습니다. 이번에는 실제로 빠진 목록 10개를 추가하고 기존 자료 범위의 누락을 추적 가능한 상태로 만들었습니다.


## Mac 실익 기준으로 추린 적용 작업

원본 구조를 그대로 복제하지 않고 현재 Mac에서 제거할 비용이 있는 작업만 추렸습니다. [실익 기준 상세](docs/BENEFICIAL_OPTIMIZATIONS.md). 모든 항목은 적용 전이며, `[x]`로 구현 완료 처리하지 않습니다.

- [ ] B01 우선: 같은 입력의 탐색 membership/weights 재사용.
- [ ] B02 우선: 변경 의존성별 filter/합계/paint 분리와 불필요한 submit 억제.
- [ ] B05 우선: text/tooltip 수명을 paint와 분리. AX 재사용은 Mac 추가 구현.
- [ ] B08 우선: 원본 packing/FIFO를 보존하는 Mac 이벤트 큐 index. 원본 trie로 표시하지 않음.
- [ ] B07 우선: 한 번 판정하고 SNS/TXT sink로 순차 출력. 바이트·부분 실패 계약 검증.
- [ ] B04 후속: 같은 weights의 형제 순서/unchanged geometry 재사용.
- [ ] B03 후속: 작은 변경의 filtered membership/합계 증분 갱신. dirty 입력 계약부터 정의.
- [ ] B06 조건부: 실제 visibility별 CPU를 확인하고 가려진 창의 시각 작업 억제.

- [x] 원본 30개 전부에 선택/기존 유지/플랫폼 개선/보류 이유 부여. 선택은 적용 전후 성능 보장이 아니며 동일 결과와 실제 시간/RSS 개선을 통과해야 채택.
