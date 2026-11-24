# GPUI 이식 TODO

**최신 결정:** 사용자가 1단계 작업 마감을 요청했다. 완료·이관 상태는
[작업 인수인계](WORK_HANDOFF.md)를 기준으로 한다. 아래 성능/과거 종료 원인
미체크 항목은 후속 작업이며, 현재 배포 준비는 검증된 184B 설치본만 사용한다.

2026-11-24 후속: [콘솔·감시 갱신 원인/수정/검증](GPUI_BACKGROUND_RESULTS.md) · [재검사 계약·장시간 검수·최신 메모리 측정](GPUI_REMAINING_RESULTS.md). 사용자 요청으로 OS 마우스·키보드 자동화는 중단했다.

2026-11-23. **Mac arm64 / Windows 132 x64에 GPUI 0.3.0 설치·주요 기능 검증 완료.** 전체 OS 입력·장시간 운영 검수는 아래 미체크 항목을 따른다. [결과·정량 측정·재현](GPUI_COMPLETION_RESULTS.md).

## 구현·실행 완료

- [x] 기존 Swift 엔진을 재사용하고 공통 GPUI UI/탐색/애니메이션으로 조립.
- [x] OS 차이를 platform/native port에 한정하고 창 생성·제어 routing/query/jobs/artifacts/state/view의 책임 분리.
- [x] 실제 mouse 폴더 진입·파일 더블클릭·뒤/앞/상위·상세 화면 유지·원래 scan session 보존.
- [x] 완료 snapshot 없는 진행 중 트리맵, 빈 결과·필터 지우기·오류 창.
- [x] native 고급 필터·SNS/DU·다중 root/코드페이지 선택·취소 보존·기본/설정별 보고서·태그 의미 공유.
- [x] metadata·hover 태그/tooltip·bounded 접근성·단일 파일 루트·SNS/폴더 drop 라우팅.
- [x] Mac Quick Look / Windows native preview, 두 플랫폼 실제 표시 및 Windows resize/Escape/원본 보존.
- [x] Windows root 날짜·용량, 두 플랫폼 실제 mount opt-in UI 100→6100→100, mount fixture 정리.
- [x] projection/geometry의 실행 1개+최신 대기 1개, 표시 2048+나머지, 100만 파일/연속 요청/resize 검증.
- [x] 바이너리 IPC·문서 스트림·payload 버전 경합 수정·부모 종료/임시 세션 수명 검증.
- [x] Unix socket / 사용자 전용 named pipe 제어, 문서 작업·다중 창·최소화/숨김/복귀 후 캡처 회귀 검증.
- [x] 원본과 같은 fixture로 화면 대조, 상세 패널/볼륨 막대/Thin font 기본값 수정, static 4 weight 검증.
- [x] production QA 명령 차단, 양쪽 기본 GPUI 빌드 workflow 실제 실행, Mac 서명 검증·Windows 아이콘/manifest 확인.
- [x] 양쪽 설치·Windows 기존 바로가기 교체·실제 바로가기 실행·번들 DLL·파일 생성/삭제 watch 검증.
- [x] 기존 사용자 분석/복구 데이터 및 SwiftUI/WinForms rollback 보존. 기본 README 빌드를 GPUI로 전환하고 옛 빌드는 참조/CLI로 명시.
- [x] 마지막 소스·artifact SHA-256과 원문 결과 고정. [증거](validation/gpui-2026-11-23/completion/README.md).

## 2026-11-24 후속 수정

- [x] Windows child console 생성 정책을 platform 어댑터로 분리하고 scan/document/preview 실행에 적용.
- [x] 활성/주차 문서의 watch 갱신은 기존 backend 재사용. 종료된 엔진만 재생성하고 하위 볼륨 설정 유지.
- [x] scan_start의 감시/하위 볼륨 옵션을 전체 검증 후 적용. 명시적 false와 생략 구분.
- [x] 빈/목록/진행 화면으로 전환 시 이전 geometry 대기 정리 및 복귀 시 새 계산.
- [x] Python named pipe 교체/연결 경합 처리. 명령 쓰기 이후 재전송 금지.
- [x] 수동 프레임 12곳의 GPUI arena 해제 누락을 공통 frame 함수로 수정. 직접 draw 우회 구조 검사.
- [x] 양쪽 Rust 26개·clippy, Python 11개와 실제 Windows transport 확인.
- [x] 양쪽 최종 15분 hidden QA와 Windows 콘솔/프로세스/RSS 예산 검증. 콘솔 0·backend 최대 1·잔류 0.
- [x] 최종 Mac 100만 파일 import/교체·취소/종료 재검증.
- [x] 최종 패키지/설치 hash 및 서명 검증. 기존 설치본 보존, 자동 실행 없음.

## 2026-11-24 남은 작업 후속

- [x] `scan_rescan(path)`의 지정 경로·원래 루트 생략 계약 구현. 화면 위치/이동 기록 유지와 주차 문서 소유 세션 갱신.
- [x] Mac 하위 트리/Windows 소유 루트 범위를 platform 어댑터로 선언하고 실제 범위를 응답에 표시.
- [x] canonical Swift JSON scope codec 공유. 실제 줄바꿈 파일명·제어 명령 경계 검증.
- [x] Windows 없는 경로의 부모 canonical 표기와 기존 경로의 끝 구분자 회귀 수정·단위/실제 앱 검증.
- [x] Mac Rust 29개/Windows 30개·clippy, Python 11개·공통 경계·canonical 43개 검사.
- [x] 양쪽 실제 hidden API 재검사 전체 시나리오와 Mac 100만 파일 import/교체/취소·정상 종료 추가 검증.
- [x] 원격 최신 disktree 커밋 확인·18회 탐색 메모리/노드 layout 측정. 순차 수집 기준 미충족과 정식 비교 미완료를 명시.

- [x] 양쪽 강제 주차 watch 12회·branch 화면 유지·root 복귀 oracle·종료 코드 0의 별도 짧은 검증. 중지 중 fixture 변경을 기준 재검사로 먼저 동기화.

- [x] 확장 watch/반복 작업: 최종 Mac/Windows 각 30분, 이전 Windows 콘솔 수정 1시간. 콘솔 0·backend 최대 1·잔류 0·OS 종료 상태 0 확인.
- [x] 종료 코드 0 검사를 harness에 추가하고 양쪽 짧은 smoke 검증. 사용한 이전 harness와 독립 종료 관측 원문 보존.
- [x] 양쪽 최신 패키지/설치 hash 검증과 rollback 보존. 사용자 preview 유지·자동 활성화 없음.

- [x] 공통 노드 184→168바이트 개발 후보·합성 RSS·양쪽 공유 테스트·TSAN 검증. [결과](NODE_STORAGE_RESULTS.md).

## 2026-11-24 양쪽 후속 검증

- [x] 실제 파일 10만 개의 수정 전후 메모리 비교 및 자체 fixture 제거.
- [x] 같은 frontend·100만 파일 SNS로 Mac/Windows 각 3쌍 native/GUI RSS 비교.
- [x] 양쪽 5회씩 대형 import/교체/취소/resize/종료·독립 OS 종료 코드 0·native 잔류 0.
- [x] 공통 시나리오와 OS metrics/exit/diagnostic 어댑터 분리 및 후보 패키지 준비. [후속 정량 결과](BOTH_PLATFORM_FINISH_RESULTS.md).

## 2026-11-24 실제 입력·종료 재조사

- [x] Mac 최신 설치본의 실제 폴더 선택·트리맵 진입·뒤/앞/상위 키, 휴지통 취소·확인·이동 후 실제 파일 oracle 대조. Finder 생성 `.DS_Store`를 포함해 대조.
- [x] 과거 실패와 같은 단일 폴더 100만 파일 SNS로 Mac/Windows 각 5회 import/교체/취소/종료 정상 확인.
- [x] 자체 sleep 프로세스에서 Mac stack sample/Windows MiniDump 및 독립 OS 종료 관찰 실동작 검증. [원인 조사 범위](EXIT_DELAY_INVESTIGATION.md).
- [x] Mac 휴지통 OS 복원·내용·watch oracle 완료. 양쪽 나머지 실제 입력은 아래 잔여 검수로 이동.

## 2026-11-24 실제 검수에서 발견한 충돌 수정

- [x] Quick Look 중첩 이벤트 루프의 App borrow panic을 실제 입력으로 재현하고 공통 UI 전경 작업 경계에서 수정.
- [x] 접근성 지도 클릭 시 지도 초점 복원. 같은 포트·엔진의 수정 전 SIGABRT/수정 후 302ms 루프 완료·반복 3회 비교.
- [x] Mac 실제 Quick Look / Windows 884×661 네이티브 preview·문서 QA. Windows hidden 1×1 capture 실패는 보존하고 비활성 visible QA로 통과.
- [x] 새 UI Mac Rust 29/Windows 30·양쪽 clippy·공통 경계 검사.
- [x] 양쪽 UI 패치 설치·manifest/QA 차단·rollback·실제 설치 경로 실행/파일 oracle. **184B 엔진 유지, 168B 미채택.**
- [x] Mac UI 휴지통→Finder OS 복원→watch/내용 oracle 완료.
- [x] 승인된 VM 임시 정지·lease/watchdog·재개 및 대상 거부 검사. 다른 부하 때문에 정식 host admission 실패 원문 보존.

[이전 충돌 원인·정량 비교](GPUI_PREVIEW_REENTRY_RESULTS.md). **최신 설치·실제 OS 입력 결과는 [취소 역할·OS 검수](GPUI_OS_INPUT_RESULTS.md)**를 따른다.

## 남은 검수

- [x] 최신 production 설치 경로의 visible 실행·스캔·파일 oracle 양쪽 확인. Mac 실제 접근성 진입·부분 재검사·Space 추가 확인.
- [x] 최종 양쪽 설치본의 실제 실행·스캔·Escape 취소·원본 보존. Mac 29/Windows 30 재검사 및 양쪽 clippy 통과. 전체 이전 입력을 새 패치에서 전수 재실행했다는 뜻은 아님.
- [x] 양쪽 실제 앱 간 SNS/폴더 drag/drop 4/4. Windows 실제 탐색·방향키·태그·새 창/닫기 입력과 native 문서 선택/저장/열기/보고서/폴더 선택 대조. 모든 상태·접근성 조합의 전수 검사는 범위 제한으로 유지.
- [x] Windows 실제 문맥 메뉴→시스템 메모장 열기·경로 복사/클립보드 복원·UI 휴지통→재스캔→OS recycle 복원·내용 hash 대조. 취소 역할 수정 후 설치본 Escape 취소도 재확인. Mac Finder 복원은 이전에 완료.
- [x] 최신 UI/기존·후보 엔진 3조건×양쪽 각 5회(60회)와 Mac visible production 2회 추가 검사. 상태 우선 보존·metrics 조회 실패 오판정 수정·양쪽 실제 sample/dump 검증. [추가 결과](PERFORMANCE_EXIT_RECHECK_RESULTS.md).
- [ ] 이전 종료 회수 8초 초과 1회의 환경/제품 원인 확정. 이번 62회에서 재현되지 않았으며 당시 stack/PID 증거는 없다.
- [ ] 안정된 호스트·최소 여유 공간 확보 후 A/A·7입력 성능 판정 및 최신 disktree 처리량/메모리 순차 비교.
- [ ] 노드 후보의 정식 성능 gate·양쪽 설치 반영 및 설치 경로 재검수. 실제 파일/GUI RSS 비교와 후보 패키지는 완료, 현재 설치본 유지.

Mac 실제 PNG 기본 앱 열기·경로 복사/붙여넣기·Finder 선택·native SNS 선택기·Space Quick Look·Cmd+N/W/Q·휴지통 확인 취소는 완료했다. 휴지통 API 실제 이동/복원은 양쪽 자체 fixture에서 통과했다. Windows 실제 visible GPUI renderer와 이번 native OS 입력 시나리오는 완료했다. 이전 internal dispatch QA와 이번 UI Automation/SendInput/파일 oracle을 별도로 기록했다.

Intel Mac runtime, Developer ID/notarization, Windows Authenticode, 모든 preview 형식, system chrome/SF Symbols의 픽셀 일치는 이번 통과 범위가 아니다. 기존 엔진 성능 HOLD나 최신 disktree 비교도 이 UI 시험과 분리한다. 이전 단계 근거는 [기능 재검토 이력](GPUI_FEATURE_PARITY.md), [문서 단계](GPUI_DOCUMENT_RESULTS.md), [볼륨/preview 단계](GPUI_PREVIEW_SCOPE_RESULTS.md)에 유지한다.
