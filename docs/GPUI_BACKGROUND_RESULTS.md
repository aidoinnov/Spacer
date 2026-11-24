# GPUI 후속 수정·검증 — 2026-11-24

Windows 콘솔 창과 backend 누적, 반복 캡처의 임시 프레임 해제 누락을 수정했다. **Mac arm64와 Windows 132 x64 설치본에 반영했고, 최종 같은 소스의 숨김 QA에서 양쪽 15분 반복 시험이 통과했다.** 사용자 요청 후 OS 마우스·키보드 자동화는 중단했다. 설치본을 자동으로 앞에 띄우지 않았다.

후속의 폴더 지정 재검사와 최신 메모리 비교는 [남은 작업 후속](GPUI_REMAINING_RESULTS.md)을 따른다. 아래 15분 결과와 해당 패키지는 완료 당시의 고정 기록이다.

## 원인과 수정

- 감시 갱신마다 `start()`로 새 backend를 실행했다. 동일 root의 backend 32개가 실제로 관찰됐다. 활성 문서는 기존 재스캔 경로를 사용하고, 주차 문서도 살아 있는 session에 `rescan`을 전달한다. 종료된 엔진만 재생성하며 하위 볼륨 설정을 유지한다.
- Windows console subsystem 엔진을 기본 process 옵션으로 실행했다. `platform::configure_child_process` 어댑터에서 Windows는 `CREATE_NO_WINDOW`, Mac은 기본 동작을 조립한다. scan/document/preview 생성 경로에 적용했다. 콘솔 표시 억제와 프로세스 재사용을 각각 해결했다.
- GPUI `Window::draw`의 `ArenaClearNeeded`를 `let _`로 버리던 수동 렌더 12곳이 있었다. transient element arena를 해제하지 않아 이전 source/backend lease도 붙잡을 수 있었다. 공통 `ui/frame.rs`의 `draw(cx).clear(cx)`로 통일하고 구조 검사에서 직접 draw 우회를 거부한다. 일반 GPUI 이벤트 루프의 프레임 처리는 그대로 사용한다.
- `scan_start`가 감시/하위 볼륨 옵션을 무시했다. `control_scan.rs`에서 전체 요청을 검증한 뒤 적용하며 명시적 false와 생략을 구분한다.
- 빈 폴더/목록/진행 화면은 canvas를 그리지 않아 이전 geometry receiver가 대기로 남을 수 있었다. 해당 화면에서 이전 cache 대기를 정리하고 복귀 시 새 geometry를 요청한다.
- Windows Python discovery가 pipe 교체 공백을 앱 종료로 판단했다. 연결 획득 단계만 제한적으로 재시도하며 쓰기 이후 명령은 재전송하지 않는다.

공통 UI에 OS 분기는 추가하지 않았다. 엔진/문서/필터는 기존 canonical Swift 소스를 공유한다.

## 최종 정량 결과

| 항목 | Mac | Windows 132 |
|---|---:|---:|
| 반복 변경 시간 | 900.22초 | 900.27초 |
| 반복 회차 | 586 | 328 |
| 파일 생성/이동/교체/수정/삭제 작업 | 46,880 | 26,240 |
| 파일·바이트·폴더 수 디스크 대조 | 1,373회 | 771회 |
| 숨김 화면 렌더/캡처 | 2,063회 | 1,449회 |
| 분기 이동 후 root 복귀 변경 확인 | 12회 | 12회 |
| GUI 종료 | 65.9ms | 79.8ms |
| 자체 fixture 정리 | 통과 | 통과 |

양쪽 모두 scan_start 감시 off/on 및 하위 볼륨 all/selected 옵션, 빈 폴더·목록·검색 결과 없음·트리맵 복귀, watch 정지를 확인했다. 실제 파일/바이트/폴더 수가 매 단계 일치해야 통과한다. projection/geometry는 최대 동시 1개와 대기 1개를 유지했다. root 복귀 검사는 별도 branch document 생성 여부를 강제한 검사가 아니다.

Windows 로그인 세션에서 1,450회 창/프로세스를 관찰했다. **보이는 backend 콘솔 최대 0개, backend 최대 1개, 종료 후 잔류 0개.** 연속 변경 구간의 같은 PID 16796 유지도 확인했다. 콘솔 표시 또는 backend 4개 초과 시 시험을 중단한다.

Windows tiny-fixture 반복 캡처는 60초 워밍업 후 RSS 증가 **7.76MiB**, 허용 예산 64MiB를 통과했다. 기준 103.4MiB, 이후 관찰 최대 111.1MiB였다. 프레임 수정 전에는 backend가 1개여도 약 11분 시점 GUI RSS 약 446MiB까지 증가했다. 이전 시험은 중단 자료이며 동등 환경 성능 비교나 감소율로 사용하지 않는다.

이는 32개 분기의 작은 자체 fixture와 반복 캡처에 대한 **제한된 15분 안정성 판정**이다. RSS는 resident working set이며 private allocation/GPU 메모리 전체가 아니다. 감시 debounce·렌더·캡처·폴링을 포함하므로 파일시스템 탐색 처리량, OS 간 우열, disktree 비교나 장시간 무누수 보장을 의미하지 않는다. Mac은 100만 파일 시험과 일부 겹친 부하를 포함한다.

## 회귀·대형 입력

- Rust Mac/Windows 각각 26개, 양쪽 QA/all-targets clippy `-D warnings` 통과. scan 요청 및 geometry 이탈/복귀 회귀 포함.
- Python 11개 통과. 실제 Windows client/named pipe 연결과 연속 요청도 확인했다.
- 구조 검사와 canonical 소스 41개 검사 통과. 수동 프레임은 공통 함수만 사용한다.
- 최종 Mac QA에서 100만 파일 SNS 반복 import 2회, 큰 import를 작은 문서로 교체/취소, resize revision 보존과 native child 종료를 통과했다. 종료 21.0ms. 100ms 샘플 최대 GUI RSS 약 872MiB, GUI+native 약 1.55GiB. 이전 visible 시험과 캡처 조건이 달라 메모리 성능 전후 비교로 쓰지 않는다.

## 이전 검사의 한계와 재현

이전 콘솔 probe는 `AttachConsole=false`, `HWND=0`인데도 `!visible`만으로 pass를 기록했다. 그 판정은 유효하지 않다. 원본을 보존했고 이번에는 로그인 세션의 ConsoleWindowClass/backend 경로 창과 실제 자식 프로세스를 직접 관찰한다. 500ms 간격 관찰과 OS 생성 플래그를 함께 검증했다.

Windows 초기 fixture의 Win32 5는 Python mode-0700 폴더 owner가 Administrators이고 OWNER RIGHTS/Administrators/SYSTEM만 허용된 경우였다. 상속 ACL의 같은 데이터는 limited GUI에서 통과했다. 기존 폴더 ACL이나 앱 권한은 바꾸지 않았다.

Mac 휴지통 확인→이동→재스캔은 통과했다. Finder의 .DS_Store도 oracle에 포함했다. 임시/캐시 origin의 Put Back은 비활성이었으며 입력 중단 후 자체 파일만 복원해 hash를 확인했다. OS UI 복원 완료로 표시하지 않는다.

재현 도구는 `scripts/gpui-app/check-watch-soak.py`, `check-windows-console-watch.ps1`, `check-macos-lifecycle.py --background-qa`다. QA-feature binary가 필요하며 production은 QA 옵션을 exit 64로 거부한다. Windows guard는 interactive limited 세션에서 자체 hidden QA만 실행한다. 실제 실행 PowerShell은 증거 폴더에 보존했다.

## 설치·패키지와 남은 검수

Mac ~/Applications/Mac Space Sniffer.app, Windows %LOCALAPPDATA%\Programs\SpaceSniffer-Windows\0.3.0-GPUI에 최종 수정본을 설치했다. Windows 바로가기는 같은 경로의 새 executable을 사용한다. 전체 설치 파일 hash(Mac 9개/Windows 38개), Mac ad-hoc 서명 및 production QA 옵션 거부를 확인했다. 기존 설치본/legacy와 사용자 Mac preview를 보존했다.

디스크 공간 부족으로 Mac 중간 패키징이 실패한 로그도 보존했다. SNIFFER_OUTPUT_ROOT를 지원해 내부 디스크에서 기본 빌드를 완료했다. 기록 저장 때 공간이 다시 부족해 자체 재생성 가능한 Cargo cache를 정리했다. 최종 ZIP/manifest는 ~/Downloads/SpaceSniffer-GPUI-0.3.0-20261124-console-fix 및 dist/releases/gpui-0.3.0-console-fix 링크에 있다. dist/releases/gpui-0.3.0은 11월 23일 보관본이다. ZIP CRC와 manifest 전체 SHA-256을 대조했다.

실제 OS 앱 간 drag/drop, Windows 기본 앱/클립보드/휴지통 전체 UI 흐름, 전체 단축키/접근성은 입력 중단에 따라 남는다. 더 긴 soak, 이전 OS E-state/8초 종료 초과 원인, scan_rescan(path) 지정 경로 계약도 미완료다. hidden QA는 최신 설치본의 수동 화면 검수를 대신하지 않는다. Mac Developer ID/notarization과 Windows Authenticode는 수행하지 않았다.

[원문·source/artifact manifest](validation/gpui-2026-11-24/background/README.md) · [TODO](GPUI_MIGRATION_TODO.md).
