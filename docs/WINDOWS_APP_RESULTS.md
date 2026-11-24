# Windows 앱 v0.1 — 실제 실행·동작 검증, 2026-11-23

**132번 PC에 Windows 앱을 설치하고 실제 사용자 데스크톱에서 실행했다.** 기존 공통 엔진 테스트만 돌린 단계에서 더 진행해, 네이티브 스캔 백엔드와 UI를 연결했다. 폴더 분석·개요·트리맵·탐색·필터·저장·감시·취소의 핵심 흐름을 검증했다.

- 바탕화면: **Space Sniffer Windows** 바로가기.
- 설치: `%LOCALAPPDATA%\Programs\SpaceSniffer-Windows\0.1.0`.
- 현재 창: 동봉 Demo의 실제24파일 분석 결과. 자동 변경 감시는 끈 상태다. `폴더 선택`으로 사용자 폴더/드라이브를 선택해 분석할 수 있다.
- [Windows ZIP](../dist/windows/SpaceSniffer-Windows-x64-0.1.0.zip) · [실측·SHA](validation/windows-app-2026-11-23/summary.json) · [최종 화면](validation/windows-app-2026-11-23/final-window/desktop-window.png).

기본 사용이 가능한 Windows v0.1의 기능 검증 완료다. Mac의 전체 기능 동등성이나 전체 성능 채택을 완료했다는 뜻은 아니다. 스냅샷 형식은 이 버전의 JSON이며 SNS와 혼용하지 않는다.

## 구조: 플랫폼 분기를 패턴으로 고정

| 경계 | 구현 | 책임 |
|---|---|---|
| 공통 포트 | `DirectoryBatchReader` | OS reader를 받는 generic 계약 |
| 공통 엔진 | `SpaceSnifferScanEngine` | worker·ticket·permit·bounded window·취소; production의 OS 분기0개 |
| Windows 조립 지점 | `WindowsScanner` | reader·경로 전략·Windows 자원 정책을 선택해 주입 |
| Windows 정책 | `WindowsScanPolicy` | worker/IO/queue/미리 읽기 상한/heartbeat 값; 공통 코드가 OS 값을 조회하지 않음 |
| 경로 전략 | `WindowsPath` | 공개 경로와 Win32 장경로 prefix/UNC 변환; 존재 여부에 따른 alias 조회 없음 |
| I/O 어댑터 | `WindowsDirectoryReader` + C `WindowsDirectoryIO` | UTF-16·Win32 handle·native error·file ID·batch capability/fallback |
| 트리 빌더 | `WindowsTreeBuilder<Reader>` 실행 경로 | 주입된 포트로 읽고 ID·children·합계를 독점 소유. Win32 호출 및 concrete reader 생성 없음 |
| UI 어댑터 | WinForms `MainWindow`·`TreemapControl` | native window·controls·탐색·필터·Windows 감시 |
| 프로세스 경계 | `ScanProcess` ↔ Swift `WindowsScan.exe` | JSONL 진행·취소 요청과 terminal snapshot. 스캔 IO가 UI thread를 막지 않음 |

`DirectoryWorkerPool` 구현을 Windows에서 다시 복사하지 않았다. UI는 기존 Mac AppKit/SwiftUI와 별개의 Windows host이며, OS 조건문으로 한 화면 안에서 플랫폼을 구분하지 않는다. Windows 파일 변경 감시는 Windows host의 `FileSystemWatcher`를 사용한다.

[구조 검사](../scripts/windows-app/check-boundaries.py)는 공통 엔진의 OS import/분기 부재, 빌더의 reader 주입, Win32 어댑터 위치와 UI/엔진 경계를 검사한다. 테스트는 실제 파일 외에도 가짜 reader를 주입해 Win32 IO 없이 빌더가 동작함을 확인했다. 단순한 파일명 분리가 아니라 의존 방향을 검증한다.

## 실제 동작

Win32 `GetFileInformationByHandleEx(FileIdExtdDirectoryInfo)`로 디렉터리 metadata를 batch 조회한다. 미지원 capability에서는 `FindFirstFileExW`/`FindNextFileW`와 파일 metadata 조회로 fallback한다. handle은 어댑터에서 닫는다. worker 결과는4,096개로 제한하고 초과하면 builder에서 inline 재조회한다.

128-bit file ID와 volume을 보존해 hard link의 할당량은 한 번만 합산한다. 논리 용량은 경로별로 유지한다. junction/symlink 등 reparse 항목은 표시하지만 자동으로 따라가지 않고 제외 개수로 보고한다. API 오류는 코드와 경로로 남기며 오류·제외가 있는 결과를 전체 볼륨 coverage로 표현하지 않는다.

빠른 개요는 현재 관측한 상위16개 root bucket만 IPC로 보낸다. 진행 메시지에 큰 children 배열을 담지 않는다. 마지막에는 정확한 트리를 합산한다. 기존 완료 결과의 재검사를 취소하면 그 결과를 유지한다. root 교체 시 이전 화면과 세대가 섞이지 않게 한다.

트리맵은 현재 폴더의 크기를 표현하고 더블 클릭으로 폴더를 탐색한다.2,000개를 넘는 그림 항목은 나머지를 `기타`로 합산하며, virtual detail 목록에는 전체 항목을 유지한다. 이름 mask OR·크기 AND·이름 제외·폴더 경로 조건, 논리/할당 크기·숨김 전환을 제공한다. 잘못된 필터는 오류를 표시하며 원래 데이터를 버리지 않는다.

JSON 스냅샷을 읽을 때 ID·parent/children·파일 수·오류 수·합계를 검증한다. 저장·TXT 내보내기는 같은 디렉터리의 임시 파일에 완성한 후 교체한다. 오프라인 스냅샷은 live rescan을 막는다. 감시는 이벤트를 모아 전체 root 재검사를 요청하며 overflow도 재검사한다. 이 버전의 감시는 Mac의 부분 subtree 갱신과 동일한 최적화 수준은 아니다.

## 정량 검증

| 검증 | 결과 | 근거 |
|---|---|---|
| 네이티브+전략 테스트 | debug7개·release7개, 실패0 | [debug](validation/windows-app-2026-11-23/native-debug.log), [release](validation/windows-app-2026-11-23/native-release.log) |
| 실제 Win32 조회 |2,051파일의 직렬/4worker 이름·logical·allocated 일치 | native test |
| 큰 폴더 |4,097파일 worker 제한 초과 후 inline 재조회, 누락0 | native test |
| 경계·취소 | junction target 제외·hard link 중복 제거·사전/중간 취소·없는 root 오류 | native test |
| UI 핵심 흐름 |17개 통과,6,150파일·66폴더 | [실행 결과](validation/windows-app-2026-11-23/ui/ui-result.json) |
| UI 용량 oracle | logical6,607,392B·allocated25,194,496B | 실제 입력+hard link |
| 독립 창 검사 | session1·실제 창/버튼/입력창·전면 화면 캡처 확인 | [UI Automation](validation/windows-app-2026-11-23/ui/external-window.json), [화면](validation/windows-app-2026-11-23/ui/desktop-window.png) |
| 배포본 | Swift DLL 동봉, PATH를 Windows/System32로 제한해 동일17흐름 통과 | [배포 manifest](validation/windows-app-2026-11-23/deployment.json) |

서로 다른 신규 테스트는7개이고 UI 흐름은 별도17개다. 기존 공통 엔진22개 Windows 테스트 결과는 [이전 단계](WINDOWS_132_PHASE1_RESULTS.md)이며 이를 신규 테스트처럼 중복 집계하지 않는다. 소량 warm scan의 화면 경과 시간을 Mac/경쟁 프로그램 대비 성능 성과로 사용하지 않는다.

최종 앱은 실제 로그인된 desktop session1에서 실행 중이다. 독립 screen capture 과정에서 다른 프로그램의 로그인 창이 앞을 가린 경우도 있어 원자료를 보존했고, 우리 창만 일시적으로 위로 올려 다시 캡처한 뒤 원래 z-order 정책으로 돌렸다. 다른 프로그램을 종료하거나 로그인 정보를 입력하지 않았다. 우리 앱이 항상 입력 focus를 독점한다고 주장하지 않는다.

## 배포·정리·후속

[설치/바로가기/정리 기록](validation/windows-app-2026-11-23/final-launch.json). 시험 fixture는 삭제했고 현재 보이는24파일 Demo만 의도적으로 남겼다. Mac 설치 앱은 변경하지 않았다. 인증 정보는 스크립트/배포물에 저장하지 않았다.

최초 빌드의 빈 test target, WinSDK BOOL 테스트 타입 오류, Foundation `/` 경로와 장경로 prefix 조합 오류를 각각 보존·수정했다. junction 실패 후 테스트의 잘못된 배열 접근도 수정하고7개 전체를 다시 통과했다. 배포 스크립트의 PowerShell5 UTF-8 읽기·명령 길이 문제는 제품 오류와 구분해 보존했다.

후속 범위는 기존 Mac SNS·태그·고급 필터·설정 포맷 전체 동등성, Windows 부분 갱신 최적화, ReFS/네트워크/클라우드 등 추가 filesystem 인증, 대규모 메모리·A/A·경쟁 성능 비교다. 이 항목들을 v0.1 완료에 섞지 않는다. Windows10 x64의 구현된 핵심 기능과 실제 실행은 검증 완료다.
