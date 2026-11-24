# GPUI 기능 이식 재검토

최신 상태: [GPUI 0.3.0 구현·양쪽 설치·실행 결과](GPUI_COMPLETION_RESULTS.md), [현재 TODO](GPUI_MIGRATION_TODO.md). 초기 표의 미이식 항목 상당수는 이후 완료됐다. 실제 OS 입력·장시간 검수의 잔여 항목은 현재 TODO를 따른다.

<details>
<summary>초기 재검토와 단계별 이력</summary>


2026-11-23. **최신 상태는 [후속 구현·검증 결과](GPUI_COMPLETION_RESULTS.md)를 따른다.** 아래 표는 초기 재검토 이력으로 보존한다. 설정 export/hover/접근성/MCP/Windows mount·preview 등의 후속 구현은 최신 결과에서 확인한다. 전체 이식 최종 판정은 남은 gate 통과 후 한다. 화면 배치·렌더러가 존재하는 것과 기존 기능의 의미가 같은 것은 다르다. 기존 TODO의 ‘핸들러 구현’ 체크를 전체 동등성 통과로 해석하지 않는다.

기준: `Sources/MacSpaceSniffer/ContentView.swift`, `ScanStore.swift`, `TreemapView.swift`, `App.swift` 및 기존 Core 계약.

| 기존 기능 | 현재 GPUI 상태 | 검증/남은 작업 |
|---|---|---|
| 스캔 중 트리맵 | 연결 완료 | 완료 snapshot 없이 progress 입력으로 실제 GPU 렌더 검증 |
| 폴더 클릭 진입 | 이번에 수정 | 사용자 요청대로 한 번 클릭. 경로로 탐색하고 숫자 ID를 가정하지 않음 |
| 완료된 트리맵 클릭 | 수정·검증 | 실제 GPUI mouse-down/up 이벤트를 통한 진입 확인 |
| 뒤로·앞으로·상위·경로 탐색 | 수정·검증 | path 기반 history. 전체 스캔은 별도 문서로 유지하고 visible branch만 추가 분석 |
| 파일 클릭/더블클릭 | 수정·검증 | 클릭은 선택, 더블클릭은 포함 폴더 확대. 기본 앱을 잘못 실행하지 않음 |
| 전체 재검사 중 상세 화면 유지 | 이번에 수정 | focus가 상세 폴더이면 root progress가 지도를 덮지 않도록 분리 |
| 스캔·중지·변경 감시 | 기존 엔진 재사용, 추가 검수 필요 | 감시 등록/해제를 actor 밖으로 분리하고 등록 gap의 journal replay 검증. parked root도 이벤트 소비. 취소는 열린 scan session에 전달. branch 이탈 시 해당 branch만 정리 |
| 원본 고급 필터 | native 연결·검증 | 기존 ScanFilter를 두 플랫폼에서 그대로 사용. 크기 경계·폴더 OR·태그 상속·숨김·날짜·잘못된 입력 회복 확인 |
| SNS/DU 열기·SNS 저장·root 선택·부분 범위 저장 | native 연결·검증 | 기존 코덱/선택기 재사용. 바이너리 SNS, 명시적 root/인코딩 선택, 취소 시 기존 문서 보존. 구형 JSON은 열람용 호환 경로 |
| 기본 보고서·설정별 export | 기본 보고서 완료, 설정 export 미완료 | TXT는 원본 paths-only/정렬/LF 인코더 사용. 설정 XML·사용자 template를 고르는 GPUI/자동화 연결은 남음 |
| 태그·숫자키·색상 | 수정·검증 | 1/2/4/8 비트마스크, 같은 색 재입력 해제, 직접 태그 첫 색 표시, 조상 OR는 필터에만 적용. 0키는 focus 범위 해제. hover 대상 숫자키는 남음 |
| 빠른 보기(Space) | Mac 검증, Windows 구현·실행 검증 대기 | Mac은 기존 Swift QuickLook 재사용. Windows는 별도 native helper의 텍스트·이미지·Shell preview/metadata와 Job 수명 관리 구현, C++/Rust 교차 검사 통과. 132 PC 연결 불가로 실제 창 검증 미완료. helper가 없으면 비활성화 |
| 열기·탐색기·경로 복사·휴지통 | 핸들러 존재 | offline/scan/선택 경계, 실제 파일 동작과 취소/복원 검수 필요 |
| 수정·생성·접근일 metadata | 연결·검증 | native wire/inspector 연결. Windows 디렉터리 열거의 FILETIME 재사용, 파일별 추가 조회 없음. Windows root 자체 날짜/볼륨 용량은 남음 |
| 다른 볼륨 포함·현재 폴더 재검사 | 부분 완료 | 현재 폴더 명령/Shift+재검사 연결. Mac 기존 부분 갱신, Windows는 하드 링크 정확성을 위한 전체 root 재검사. Mac mounted-volume opt-in UI 연결 및 실제 중첩 mount 100→6100→100개 검증 완료. Windows opt-in과 mount 목록 갱신은 남음 |
| SNS drag/drop | 연결 | 파일 drop/실행 인자는 문서 열기 경로, 폴더는 스캔 경로 사용. OS에서 실제 drag 입력 최종 검수는 남음 |
| 빈 필터 결과·필터 지우기·오류 sheet | 빈 결과/지우기 검증, 오류 표현 검수 남음 | 0건 안내·필터 지우기·재투영 통과. 불러오기 실패/취소는 기존 문서 유지. 오류는 현재 인라인/상태바 표시 |
| hover tooltip·가상 접근성·단축키 전체 | 일부 구현 | 원본 MapAccessibility/tooltip/selection 계약 전체 검수 필요 |
| 자동화/MCP·다중 창·숨김/종료 수명 | 미이식/검수 미완료 | 기존 제어 기능을 새 UI owner에 연결해야 함 |
| 대규모 메모리·IPC·작업 교체 | 일부 개선, 전체 gate 미완료 | 부모/이름 경로 압축, 64KiB 문서 스트림, 불러오기 교체/취소, 큰 그래프 해제 분리. 전체 tree JSON·Rust 전체 경로·geometry/연속 필터 취소 한도는 남음 |
| release·서명·기본 배포 교체 | 미완료 | 기존 production Mac 앱은 유지. preview 동작 통과와 제품 전체 완료를 구분 |

## 이번 탐색 수정의 책임 경계

- `navigation.rs`: OS 분기 없는 location/breadcrumb 값.
- `ui/navigation.rs`: scope·history·문서 전환. 원래 root scan은 유지하고, 떠나는 branch의 session만 정리한다. 비활성 문서는 3개로 제한한다.
- `ui/scan_document.rs`: 비활성 root의 진행/완료/watch 갱신 수신.
- `ui/canvas.rs`: 표시된 타일의 hit → 경로/파일 선택 변환. 합산용 나머지 영역은 폴더 탐색 대상으로 만들지 않는다.
- `platform`: Foundation/Windows의 경로 표기 차이를 모은다. UI에 `target_os` 조건을 추가하지 않았다.

## 근거

- [Mac 실제 mouse 이벤트 검증](validation/gpui-2026-11-23/mac/navigation-click.json): progress 폴더 클릭, 완료 map 클릭, 파일 더블클릭, history, 상세 화면 유지, 원래 scan PID 보존.
- [Windows visible-window 검증](validation/gpui-2026-11-23/windows/navigation-click.json): 동일한 GPUI 이벤트 경로. 숨김 창의 1×1 viewport 시험은 통과 근거로 쓰지 않았다.
- 실제 Mac `/Volumes/develop` 창에서도 CUA 한 번 클릭으로 `Code` 진입과 뒤로 복귀를 확인했다. root 진행은 69.8GB → 238.7GB로 계속됐고 root scan process는 유지됐다.
- [12개 테스트](validation/gpui-2026-11-23/navigation-tests.log), [clippy](validation/gpui-2026-11-23/navigation-clippy.log), [공통 UI 경계](validation/gpui-2026-11-23/platform-boundary.log).

다음 완료 판정은 위 미이식 항목을 구현하고 실제 입력으로 확인한 뒤 한다. 이번 클릭 수정은 전체 기능 이식 완료가 아니다.

## 문서·필터 이식 후 검증

[성과와 재현 명령](GPUI_DOCUMENT_RESULTS.md). `validation/gpui-2026-11-23/documents/`에 source manifest, Mac/Windows GUI 결과, 스트림/필터 결과와 로그를 고정한다. 기존 엔진의 입력·선택·인코더를 공유하며 OS API는 어댑터로 분리했다. 이 단계도 전체 이식/정식 배포 완료를 뜻하지 않는다.

## 볼륨 범위·미리보기 후속

[구현·정량 검증과 남은 Windows 실행 시나리오](GPUI_PREVIEW_SCOPE_RESULTS.md). 드라이브 용량보다 파일 할당량 합계가 큰 SNS의 재로드 회귀도 수정했다. 실행 중인 사용자 창은 보존했으며 후속 변경의 적용 상태는 결과 문서를 따른다.

</details>
