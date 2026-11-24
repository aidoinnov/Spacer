> 후속: [실제 OS 입력·취소 역할 수정 및 최신 설치](GPUI_OS_INPUT_RESULTS.md). 아래 SHA/PID와 대기 항목은 이 보고서 작성 시점의 기록이다.

# Quick Look 재진입·접근성 초점 수정 — 2026-11-24

**Mac·Windows 132에 공통 UI 수정본을 설치하고 실제 설치 경로의 실행·스캔을 확인했다.** Mac 실제 검수에서 발견한 Quick Look 종료를 재현·수정했고, 접근성 클릭의 키보드 초점도 보완했다. 기존 184B 엔진을 그대로 사용한 UI 패치다. **168B 엔진 후보는 미채택**이며 정식 성능 판정과 OS 입력 잔여 검수는 아래 범위를 따른다.

## 발견한 종료와 수정

Mac 설치본 PID 27711의 실제 Space 검수에서 SIGABRT가 발생했다. 원문 `MacSpaceSniffer-2026-11-24-174704.ips`는 `QuickLook.show` → 네이티브 QuickLookUI 중첩 이벤트 루프 → GPUI `Explorer::new` 타이머 → `panic_already_borrowed`를 포함한다. 이벤트 리스너가 GPUI App/Explorer의 가변 빌림을 유지한 채 Quick Look을 직접 호출했고, 중첩 루프에서 타이머가 다시 App 상태에 접근했다.

`Command::Preview`는 공통 `file_actions::preview_selected`에 위임한다. 선택 경로를 소유 값으로 복사하고 약한 entity 핸들로 전경 작업을 예약한다. 리스너의 상태 빌림이 끝난 뒤 같은 UI 스레드에서 네이티브 미리보기를 호출한다. 창이 사라지면 호출을 생략하고, 실패 상태는 별도 entity update로 반영한다. macOS UI를 background worker에서 호출하지 않으며 네이티브 ABI도 바꾸지 않았다.

접근성 트리맵 클릭은 파일 선택/폴더 이동만 하고 이전 입력란·버튼의 키보드 초점을 남길 수 있었다. 같은 경로의 접근성 action에서 `window.focus`를 적용해 마우스 클릭과 동일하게 지도에 초점을 둔다. 이후 Space/숫자키가 이전 버튼이나 입력란으로 흐르지 않게 했다. **두 수정 모두 공통 UI에 있으며 OS 조건을 추가하지 않았다.**

## 같은 조건의 재진입 비교

자체 번들에 300ms 중첩 메인 run loop를 실행하는 시험용 네이티브 포트를 넣고 **실제 CUA Space 입력**으로 비교했다. 포트와 184B 엔진의 SHA가 동일한 수정 전/후 번들이다. 이 포트는 재진입 조건을 만드는 시험용이며 실제 Quick Look 렌더러가 아니다.

| 항목 | 수정 전 | 수정 후 |
|---|---|---|
| 실제 키 입력의 네이티브 호출 진입 | 확인 | 확인 |
| 중첩 루프 종료 | 미완료 | 302.33ms 후 완료 |
| 프로세스 | SIGABRT·동일 borrow panic | 생존·RPC 응답 정상 |
| 추가 Space 3회 요청 | 수행 안 함 | 최종 호출 완료·창 유지 |

수정 전 PID 80161의 `MacSpaceSniffer-2026-11-24-180220.ips`에서 SIGABRT와 borrow panic을 직접 대조했다. 수정 후 PID 84367은 입력란에 초점을 둔 뒤 접근성 트리맵 클릭→Space를 수행해 초점 회복도 함께 확인했다. 코드가 다른 앱을 제어하지 않도록 실행 경로와 PID를 확인했으며, 첫 PID 선택 착오는 실제 실행 경로 확인 후 정정했다. 최종 paired JSON은 올바른 두 PID만 사용한다.

초기 일반 QA에서는 **수정 전도 통과**했다. QA 자체가 main dispatch 작업 안에서 키를 직접 dispatch하는 경로에서는 중첩 타이머 재진입이 관찰되지 않았다. 호출 출처 차이가 검사를 가렸다는 해석이며, 실제 AppKit 입력 경로를 별도로 검사해야 함을 보여준다. 이 시도는 장애 재현 근거로 사용하지 않는다. 실제 AppKit 입력 경로에서 재현한 결과와 분리해 원문을 보존한다.

## 실제 네이티브 동작·회귀 검사

- Mac 새 UI의 실제 Space 입력 후 앱 생존·스캔 상태·경로 유지 확인. 실제 Quick Look 라이브러리를 쓴 별도 QA에서는 함수가 확인한 `QLPreviewPanel.isVisible`이 true였으며 정상 종료했다. CUA의 앱 창 캡처는 보조 Quick Look 창을 직접 포함하지 않아 캡처만으로 가시성을 주장하지 않는다.
- Windows 실제 네이티브 텍스트 preview ready: **884×661**, visible=true. native projection, Return 확대, 태그, SNS 저장/열기, 보고서, 다중 root 선택/취소, offline 재투영과 빈 필터 복귀도 통과했다. 내부 키 dispatch 시험이며 실제 OS 키보드 입력 전체를 대신하지 않는다.
- Windows 첫 hidden QA는 **invalid capture**로 실패했다. 숨김 창의 1×1 GPU 표면이 원인인 실행 설정 문제다. 캡처 최소 1000×600 조건은 낮추지 않고, `--qa-visible`의 비활성 창으로 재검사해 통과했다. 실패 JSON과 재검사 JSON/PNG를 모두 보존한다.
- 새 소스 release Rust 테스트 **Mac 29/29, Windows 30/30**, 양쪽 QA/all-targets clippy `-D warnings` 통과. 의존성 `block`의 future-incompatibility 안내와 현재 clippy 오류 0을 구분한다.
- 공통 GPUI/스캔 플랫폼 경계 검사 통과. 이전 30분/1시간 soak는 이번 두 UI 수정 전 자료이며 새 패치의 soak로 표시하지 않는다.

## 설치와 실제 실행

| 항목 | Mac arm64 | Windows 132 x64 |
|---|---|---|
| 설치 manifest 검증 | 9개 파일 | 38개 파일 |
| UI SHA-256 접두사 | `5ef5e33cbd0f` | `b58a0cbc794c` |
| 엔진 SHA-256 접두사 | `a8ab73ee1e9f` | `1bf91efa01a4` |
| production QA 옵션 | exit 64 | exit 64 |
| 실제 설치본 파일/폴더 oracle | 5 / 4 | 3 / 4 |
| logical bytes | 102,399 | 52,049 |

Mac은 실제 설치 경로의 PID 86851에서 파일 oracle, 접근성 폴더 진입, 부분 재검사·상세 위치 유지와 실제 Space 입력을 확인했다. Windows는 실제 설치 경로 PID 17180의 visible 스캔 완료, snapshot/geometry 안정, 파일 oracle과 native backend 1개를 확인하고 Parsec 화면에서도 실행된 공통 UI를 관찰했다. Windows의 이 검증은 앱을 실행한 시험이며 OS 클릭·클립보드·휴지통 전체 검수 통과가 아니다.

Mac `~/Applications/Mac Space Sniffer.app`, Windows `%LOCALAPPDATA%\Programs\SpaceSniffer-Windows\0.3.0-GPUI`에 설치했다. Mac ad-hoc deep/strict 서명과 양쪽 전체 파일 hash를 확인했다. 이전 앱/폴더는 timestamp rollback으로 보존했고 Windows 바로가기 대상은 유지했다. 두 설치본의 엔진은 교체 전과 **전체 파일 SHA가 동일**하다. 사용자 preview PID 85872와 복구 자료는 보존했다. 확인용 새 설치 앱은 양쪽 검사용 폴더에서 열어뒀으며 자체 실행 예약 작업은 제거했다.

## 실제 입력 검수 진척

Mac의 이번 패치 전 실제 입력으로 폴더 선택, 트리맵, 뒤/앞/상위, SNS 저장/열기, TXT 보고서 저장, 새 창/닫기, 숫자 태그 1/2/3/4·동일 키 해제·0·Escape, 빈 필터 복귀를 확인했다. 태그 값 1/2/4/8은 native 조회와 대조했다. UI 휴지통 취소→이동→재분석→Finder ‘되돌려 놓기’→원본 내용과 watch oracle 복원도 완료했다. Finder가 만든 `.DS_Store`는 실제 파일 oracle에 포함한다. 패치 후 기본 탐색·부분 재검사·Space와 설치 경로를 다시 확인했고 새 패키지의 native 문서 QA도 통과했다. 모든 앞선 실제 입력을 패치 후 전부 재실행했다고 표시하지 않는다.

남은 것은 Mac/Windows의 실제 앱 간 SNS·폴더 드래그, Windows OS 기본 앱/클립보드/휴지통·전체 단축키/접근성 입력 조합이다. CUA의 Finder 내부 드래그도 실제 파일 이동으로 이어지지 않았고, Parsec 시작 메뉴·트리맵 클릭에서도 기대 동작을 확인하지 못했다. 원인을 앱 문제로 단정하거나 통과로 바꾸지 않았다. CUA 도구 지침은 다른 입력 기술을 사용자 명시 요청 시에만 허용하므로 CGEvent·UI Automation/SendInput 사용 여부를 질문한 상태다.

## 속도와 과거 종료 지연의 현재 상태

사용자가 VM·folio-dev 종료를 허용했다. folio-dev는 이미 실행 중이지 않았다. Docker GUI 종료와 공식 `docker desktop stop --timeout 30`은 VM 종료로 이어지지 않았다. 실패한 자체 CLI만 종료하고, Apple VM 실행 경로·동일 사용자·실제 Docker.raw 소유를 확인한 대상만 임시 SIGSTOP했다. 정상 종료/부모 소실/제한 시간에 재개하는 lease와 watchdog을 적용했다. VM은 검사 후 정상 경로에서 SIGCONT로 재개됐고 watchdog은 발동하지 않았다. 임의 프로세스는 거부하는 음성 검사도 2개 통과했다.

90초 안정화 후 기존 정식 runner를 한 번 실행했지만 **CPU idle 43.62–52.98%, pressure 2**로 host_not_admitted였다. load/swap/disk는 통과했다. 다른 프로젝트의 검색·Medio·Go/sqlite·브라우저 테스트 등이 동시 실행 중이며 승인 범위 밖 작업을 종료하지 않았다. **A/A 100쌍·정식 7입력 21쌍은 실행하지 않았고 168B 후보도 설치하지 않았다.** UI 충돌 패치를 배포한 것을 엔진 속도 채택 통과로 표시하지 않는다.

이번 SIGABRT 원인은 확인·수정했지만, 과거 한 번의 **8초 종료 회수 초과는 별개로 미확정**이다. 같은 단일 폴더 100만 SNS의 양쪽 5회 정상 종료와 timeout 진단 포트 실검증은 [종료 지연 조사](EXIT_DELAY_INVESTIGATION.md)를 따른다. 새 borrow panic을 과거 지연의 원인이라고 연결하지 않는다.

[ZIP·원문·소스·전체 hash](validation/gpui-preview-fix-2026-11-24/README.md) · [전체 TODO](GPUI_MIGRATION_TODO.md).
