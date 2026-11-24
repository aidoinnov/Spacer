# 원본 근거와 Mac 구현 경계

2026-11-08. 사용자 지시: **UI와 플랫폼 특성을 제외한 동작에는 리버싱 근거가 있어야 한다.** 이전의 단순화한 규칙을 이 기준으로 다시 대조했습니다.

## 대상

공식 SpaceSniffer 2.2.0.27 x64, EXE 8,691,097 bytes. SHA-256 `192176a0ff46d84d27885e9d38e60157bc692eaf5d1e5b75ca56b3beaa0de7a6`. ZIP SHA-1 `1b0f676927e37747566075b1970615138d3de26a`.

Ghidra 12.1.4, 이미지 베이스 `0x400000`, 분석된 함수 23,724개. 함수 심볼과 본문, 데이터 바이트를 연결했습니다. [공식 다운로드](https://www.uderzo.it/main_products/space_sniffer/download_alt.html)에서 확보한 원본 ZIP을 별도 보관합니다.

`engine-rea-evidence.json`은 원본 해시·도구·주소·본문·분석 한계를 보관합니다. `engine-contracts.json`은 구현의 규칙, 원본 Evidence ID, UI/플랫폼 예외, 미구현 범위를 연결합니다. `scripts/check-engine-evidence.py`는 연결 누락과 잘못된 대상 해시를 검사합니다. 이 검사는 추적 가능성을 확인하며 런타임 동등성을 증명하지 않습니다.

## 원본과 대조해 고친 내용

| 동작 | 원본 근거 | 반영한 계약 |
|---|---|---|
| 단일 클릭 상세화 | `pnlGraphMouseDown` `0x42b5c0`, `refreshBitmap` `0x4295a0`, `layout` `0x468db0` | 현재 위치는 유지하고 선택 경로와 그 자식을 기본 깊이 이상으로 노출 |
| 더블 클릭 | `pnlGraphDblClick` `0x42c590` | 폴더는 전체 확대, 파일은 부모로 확대. 파일 자동 실행 제거 |
| 더블 클릭의 표적 | 같은 함수의 `0x761` mouse-down 차단 플래그 | 첫 클릭으로 자식이 나타나도 두 번째 클릭 표적은 원래 노드 유지 |
| 초기 깊이 | `getConfig` `0x40c420`: `initialDetailLevel` offset `0x5c` 기본값 3 | 기본 깊이 3 유지. 3은 임의 설정이 아님 |
| 파일명 조건 | ctor `0x43f450`, `patternMatch_internal` `0x445050` | 외부 구분자 `;`, 긍정 파일명 OR, 제외는 모두 만족. 쉼표 OR와 `!` 제외 단순화 제거 |
| 크기/기간 | `isIncluded` `0x444870`, size `0x43fd20`, age `0x440810` | 정수 숫자, 경계값 포함. `m=60초`, `month=2,592,000초`. 생성/접근/수정 필드 구분 |
| 퍼지 접두사 | `fuzzyMatch` `0x445420`, 재귀 `0x4460a0` | 첫 문자 일치 후 부분 수열로 접두사 판정. 임의 fuzzy 검색 아님 |
| 폴더 필터 | ctor 및 `getFolderPatternMatchingParents` `0x408670` | `\temp` 접두사 문법, 조상 폴더 포함/제외. 임의 `temp/` 문법 제거 |
| 태그 색상 | `examineTagToken` `0x4455b0`, 바이트 `0x740d80` | 빨강=1, 노랑=2, 초록=4(키3), 파랑=8(키4). 매뉴얼 일부 예제와 충돌하므로 바이너리 기준 |
| 항목 자신의 태그 | `FormKeyDown` `0x42f0a0`, `setTag` `0x408300` | 항목당 색 하나, 같은 색은 해제. 조상의 마스크는 OR 상속하되 자신의 색만 표시 |
| 태그 조건 | `isTag` `0x441b00`, `tokenize` `0x445bd0`, `isIncluded` | 여러 포함 태그 OR, 제외 태그 우선. `+/-/,` 토큰과 외부 `|` 부호 처리 |
| 태그 rename | `elementChange` `0x406d30` action 4 | 같은 노드의 이름을 바꾸므로 태그 유지. 삭제를 기존 하드 링크 별칭으로 잘못 이관하지 않음 |
| 파일 집계 | `snifChildrenPaths` `0x455be0`, `node init` `0x4051a0`, `deltaSize` `0x405a00` | 파일 경로별 기여분을 조상에 합산. 임의 inode dedup 및 폴더 메타데이터 가산 제거 |
| 순회 제외/재시도 | 같은 `snifChildrenPaths` | reparse/symlink 제외에 대응. 원본은 디렉터리 열기 실패 총 10회/10ms. Mac은 2026-11-19부터 오류별 즉시 실패 또는 최대 3회/요청 대기 20ms로 분리한 플랫폼 정책 |
| 루트 캐시 | `getRootData` `0x43ec60`, `releaseNode` `0x43f230` | 같은 루트 공유, 리스너 참조 해제, 마지막 참조의 스캔/감시 정리 |
| 필터 작업 교체 | `applyFilterTo` `0x42cba0`, `terminateFilterThread` `0x429020` | 오래된 필터 작업 취소 후 새 입력 반영. 원본의 경로별 refilter packing은 `0x42e130` |
| SNS 저장 | `exportHardCoded` `0x408a80`, group end `0x408a10`, `exportNode` `0x416650` | v4 바이너리 노드 레코드, UTF16LE Base64 이름, LE 정수/FILETIME, 종료 `01 00` |
| SNS 읽기 | `importHardCoded` `0x408ef0`, internal `0x4093c0`, agent `0x4576f0` | 확인한 v1/v3/v4 읽기. JSON 대체 제거, 불명확한 v2는 거부 |
| 텍스트 내보내기 | export 기본 설정 ctor `0x413b30`, `compareTo` `0x46b6b0`, `exportNode` | 원본 `Simple file list`: 경로만, files-first, size-desc, UTF8/LF. 임의 CSV 프리셋 제거 |

`getPhysicalSize` `0x406380`은 Windows cluster 단위 반올림을 수행합니다. Mac에서는 대응 OS 할당량인 `st_blocks * 512`를 사용합니다. 이 차이는 플랫폼 대체이며 별도의 정리/중복 제거 정책을 넣는 근거가 아닙니다.

## SNS 레코드

원본 v4 쓰기 순서:

1. 버전 u8 = 4, 노드 종류 u8.
2. 이름 길이 u32 LE, Base64(UTF16LE 이름). 원본 길이 한계 8192 bytes.
3. 논리 크기 i64 LE, 디스크 크기 i64 LE.
4. Windows attributes u32 LE.
5. 생성/접근/수정 FILETIME 각 u64 LE.
6. 자신의 태그 u8, 내부 flags u8.
7. 자식들을 같은 구조로 쓰고, 각 노드를 `01 00`으로 종료.

노드 종류는 1 drive, 2 file, 3 folder, 4 free, 5 unknown, 6 missing입니다. 버전 1은 UTF8 이름, 버전 3은 UTF16LE Base64 이름과 논리 크기 대비 i32 할당량 차이를 읽습니다. 버전 2 legacy encoding은 추가 확인 전 지원하지 않습니다.

파일 형식 근거는 정적 분석입니다. 테스트의 golden bytes는 이 명세에서 독립적으로 구성한 바이트이며 Windows 앱이 실제 생성한 fixture라고 주장하지 않습니다. 원본에서 읽고 다시 저장하는 왕복 검증도 아직 하지 않았습니다.

## 플랫폼과 UI 경계

- Windows `FindFirstFileExW`/`FindNextFileW` → macOS 디렉터리 열거와 `lstat`.
- Windows `ReadDirectoryChangesW` → FSEvents 전용 큐. old/new rename 쌍이 없으므로 유일한 새 inode 경로만 연결하며, 모호한 경우 추측하지 않습니다.
- FSEvents 변경 범위를 부모 폴더 재검사로 반영합니다. 이벤트 손실은 루트 재검사로 복구합니다. 원본의 직접 노드 mutation과 구현 자료구조가 같다는 주장은 하지 않습니다.
- 원본 락/이벤트/TThread → actor, 취소 토큰, 불변 스냅샷, worker mailbox. mailbox 용량이 원본과 같다는 주장은 하지 않습니다. 원본의 오래된 필터 취소 계약을 지킵니다.
- Finder/Quick Look/Trash/권한 안내 → macOS API. 운영체제 작업은 UI 확인 후 worker에서 수행합니다.
- 색상, 여백, 폰트, 툴바, Squarified rectangle 배치, 파일 유형 색 분류, 표시 단위, 진단 행 제한은 UI 예외입니다. 폴더를 파고드는 선택/확대 계약은 별도 원본 근거를 따릅니다.

## 미구현과 미검증

근거 없는 대체 동작을 제공하는 대신 아래 범위를 명시적으로 남깁니다.

- SNS v2는 명시적 원본 ANSI codepage로 읽고, 복수 최상위 루트는 선택해 연다. 추가로 확인된 원본 loader는 `.DU`이며 이전의 `SNF` 표기는 근거가 없어 정정한다. Windows 실제 왕복 검증은 남아 있다.
- Windows XML 설정의 사용자 수정 전체와 export scripting 전체. 현재는 확인한 기본 클래스와 `Simple file list`만 제공합니다.
- master scan과 별도 focused scan의 동시 실행. 현재 UI는 전체 스캔이 끝난 뒤 범위 재스캔을 허용합니다.
- 원본의 focus-first 부분 refilter 알고리즘과 직접 per-node 이벤트 갱신의 완전한 재현.
- Windows 실행 환경에서 실제 결과·타이밍·파일 왕복 비교. 31개의 테스트 통과가 이를 대신하지 않습니다.

위 범위까지 구현된 것처럼 표현하지 않습니다. 향후 엔진 변경 시 계약표와 실제 원본 근거를 함께 갱신합니다.


## 애니메이션·화면 캐시 추가 분석

대상은 위에 고정한 Windows 2.2.0.27 x64 바이너리입니다. 아래는 정적 디컴파일 근거이며 Windows 실행 장면을 관찰한 결과는 아닙니다.

| 확인 항목 | 원본 근거 | 결론 |
|---|---|---|
| 확대·축소 | `TfrmView::zoomFromTo` `0x42bb40`, 상수 `0x73f4e0`, 설정 `0x40c420` | 기본 5 × 100ms = 500ms. 진행률 `1 - ((cos(t × 3.1415) + 1) / 2)^2`. 원본은 출발·도착 비트맵과 선택적인 재렌더링을 사용 |
| DynaSmooth | `updateRefreshDelay` `0x42cd00`, repaint timer `0x42c760` | 기본 50/100ms 갱신 주기를 조절. 이것만으로 개별 사각형 위치 보간이 증명되지는 않음 |
| 변경 강조 | `TTreeMapNode::paint` `0x469770` | 변경 노드의 약 500ms 색상 강조. 위치 이동 애니메이션과 구분 |
| 노드 색상 캐시 | `paint` `0x469770`, `resetCache` `0x46bb00` | 노드 `+0x50` 색상 테이블 포인터 재사용, 무효화 시 재귀적으로 비움 |
| 확장 폴더 용량 | `paint` `0x469770` | 확장된 폴더의 제목에도 용량 문자열을 조합 |
| 공유 스캔 캐시 | `TDataCache::getRootData` `0x43ec60`, `releaseNode` `0x43f230` | 루트 경로와 agent GUID에 맞는 기존 트리를 리스너 간 공유. 마지막 참조 해제 때 관련 스캔·감시 정리 |

일반 레이아웃 재배치에서 모든 노드가 이전 좌표→새 좌표로 보간된다는 근거는 아직 확보하지 못했습니다. `setCoords` `0x468320`과 자식 배치 `0x468360`에서는 좌표를 직접 기록합니다. 해당 현상을 원본과 같다고 단정하지 않습니다.

Mac의 `TreemapMotion`은 확인한 확대·축소 곡선과 500ms를 사용합니다. 이를 사용자가 요청한 레이아웃 전환에도 적용한 것은 UI 범위의 구현 선택입니다. 경로로 이전·새 사각형을 연결하고, 중단된 전환은 현재 표시 위치에서 이어갑니다. 들어오거나 사라지는 항목의 투명도 전환, 표시 항목·용량 문자열·색상 캐시, Reduce Motion 준수도 Mac UI 구현입니다.

공유 트리와 화면 캐시는 메모리 캐시입니다. 재실행 후 스캔을 자동 복원하는 영구 디스크 캐시는 이번 분석에서 확인하지 못했습니다. 사용자가 명시적으로 저장·여는 SNS 스냅샷과 구분합니다.


## 추가 반영

캐시 식별·설정별 무효화·일반 repaint 호출 흐름, 변경 경로 FIFO packing, 삭제·필터 제외·rename 뒤 탐색 상태를 추가 추적했습니다. Mac의 변경 범위 큐와 NavigationState에 반영했으며, 세부 근거·플랫폼 차이·미완료 검증은 [캐시·다시 그리기 분석](CACHE_AND_REPAINT_FINDINGS.md)에 기록했습니다.


## Windows 원본의 최적화 구조

현재 바이너리에서 확인한 재사용·증분 갱신·작업 축소 기법 20개를 [별도 조사서](WINDOWS_OPTIMIZATIONS.md)로 정리했습니다. 기존 근거 재검토와 새 함수/assembly 조회를 합쳐 139개 REA 기록을 보관했으며, Mac의 독자적인 자료구조 최적화와 원본 동작의 근거를 구분했습니다. 증분 형제 정렬·text 치수/tooltip 캐시·노드 재활용·순차 file sink 등의 추가 원문도 포함합니다.
